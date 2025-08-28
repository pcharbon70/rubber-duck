defmodule RubberDuck.SkillsActions.SkillsRegistry do
  @moduledoc """
  Centralized skills registry for discovery, registration, and capability matching.

  This registry provides a unified interface for managing agent skills across the
  RubberDuck system including:
  - Dynamic skill discovery and registration
  - Intelligent capability matching for agent needs
  - Skill versioning and evolution tracking
  - Performance monitoring and optimization
  - Integration with Universal LLM Provider System
  - Configuration-aware skill preferences

  The registry works with existing Jido.Skill patterns while adding sophisticated
  orchestration and discovery capabilities.
  """

  use GenServer
  require Logger

  alias RubberDuck.LlmProviders.UniversalProviderService

  @registry_name __MODULE__
  @skill_modules [
    RubberDuck.Skills.LearningSkill,
    RubberDuck.Skills.ThreatDetectionSkill,
    RubberDuck.Skills.ProjectManagementSkill,
    RubberDuck.Skills.AuthenticationSkill,
    RubberDuck.Skills.CodeAnalysisSkill,
    RubberDuck.Skills.PolicyEnforcementSkill,
    RubberDuck.Skills.QueryOptimizationSkill,
    RubberDuck.Skills.TokenManagementSkill,
    RubberDuck.Skills.UserManagementSkill
  ]

  # 5 minutes
  @default_cache_ttl 300_000

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Register a skill module with the registry.
  """
  def register_skill(skill_module, metadata \\ %{}) do
    GenServer.call(@registry_name, {:register_skill, skill_module, metadata})
  end

  @doc """
  Discover skills matching specific capability requirements.
  """
  def discover_skills(capability_requirements) do
    GenServer.call(@registry_name, {:discover_skills, capability_requirements})
  end

  @doc """
  Get all registered skills with their capabilities.
  """
  def get_all_skills do
    GenServer.call(@registry_name, :get_all_skills)
  end

  @doc """
  Get capabilities for specific skill module.
  """
  def get_skill_capabilities(skill_module) do
    GenServer.call(@registry_name, {:get_capabilities, skill_module})
  end

  @doc """
  Resolve dependencies for a set of skills.
  """
  def resolve_skill_dependencies(skill_modules) do
    GenServer.call(@registry_name, {:resolve_dependencies, skill_modules})
  end

  @doc """
  Find optimal skill for specific agent need using LLM-assisted recommendation.
  """
  def recommend_optimal_skill(agent_need, context, user_id \\ nil) do
    GenServer.call(@registry_name, {:recommend_skill, agent_need, context, user_id})
  end

  @doc """
  Get registry statistics and performance metrics.
  """
  def get_registry_stats do
    GenServer.call(@registry_name, :get_stats)
  end

  @doc """
  Auto-register all existing skills in the system.
  """
  def auto_register_existing_skills do
    GenServer.cast(@registry_name, :auto_register_skills)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    # Subscribe to skill and configuration changes
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "skills_registry_events")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "preference_changes")

    state = %{
      skills: %{},
      capabilities_cache: %{},
      dependency_graph: %{},
      performance_metrics: %{},
      stats: %{
        total_skills_registered: 0,
        discovery_requests: 0,
        recommendation_requests: 0,
        cache_hits: 0,
        cache_misses: 0
      },
      config: %{
        cache_ttl: Keyword.get(opts, :cache_ttl, @default_cache_ttl),
        capability_matching_algorithm: Keyword.get(opts, :matching_algorithm, :weighted_overlap),
        performance_monitoring_enabled: Keyword.get(opts, :performance_monitoring, true),
        llm_recommendations_enabled: Keyword.get(opts, :llm_recommendations, true)
      }
    }

    Logger.info("Skills Registry started successfully")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_skill, skill_module, metadata}, _from, state) do
    Logger.info("Registering skill: #{skill_module}")

    case extract_skill_metadata(skill_module, metadata) do
      {:ok, skill_metadata} ->
        updated_skills = Map.put(state.skills, skill_module, skill_metadata)

        updated_dependency_graph =
          update_dependency_graph(state.dependency_graph, skill_module, skill_metadata)

        # Clear capabilities cache since new skill affects discovery
        updated_cache = %{}

        updated_stats = Map.update!(state.stats, :total_skills_registered, &(&1 + 1))

        new_state = %{
          state
          | skills: updated_skills,
            dependency_graph: updated_dependency_graph,
            capabilities_cache: updated_cache,
            stats: updated_stats
        }

        # Broadcast skill registration
        Phoenix.PubSub.broadcast(
          RubberDuck.PubSub,
          "skills_registry_events",
          {:skill_registered, skill_module, skill_metadata}
        )

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to register skill #{skill_module}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:discover_skills, capability_requirements}, _from, state) do
    Logger.debug("Discovering skills for requirements: #{inspect(capability_requirements)}")

    cache_key = :erlang.phash2(capability_requirements)

    case Map.get(state.capabilities_cache, cache_key) do
      nil ->
        # Cache miss - perform discovery
        matching_skills =
          perform_capability_matching(state.skills, capability_requirements, state.config)

        # Cache the result
        updated_cache =
          Map.put(state.capabilities_cache, cache_key, {matching_skills, DateTime.utc_now()})

        updated_stats =
          state.stats
          |> Map.update!(:discovery_requests, &(&1 + 1))
          |> Map.update!(:cache_misses, &(&1 + 1))

        new_state = %{state | capabilities_cache: updated_cache, stats: updated_stats}

        {:reply, {:ok, matching_skills}, new_state}

      {cached_skills, cached_at} ->
        # Check cache expiration
        if DateTime.diff(DateTime.utc_now(), cached_at, :millisecond) < state.config.cache_ttl do
          # Cache hit
          updated_stats =
            state.stats
            |> Map.update!(:discovery_requests, &(&1 + 1))
            |> Map.update!(:cache_hits, &(&1 + 1))

          {:reply, {:ok, cached_skills}, %{state | stats: updated_stats}}
        else
          # Cache expired - perform fresh discovery
          matching_skills =
            perform_capability_matching(state.skills, capability_requirements, state.config)

          updated_cache =
            Map.put(state.capabilities_cache, cache_key, {matching_skills, DateTime.utc_now()})

          updated_stats =
            state.stats
            |> Map.update!(:discovery_requests, &(&1 + 1))
            |> Map.update!(:cache_misses, &(&1 + 1))

          new_state = %{state | capabilities_cache: updated_cache, stats: updated_stats}

          {:reply, {:ok, matching_skills}, new_state}
        end
    end
  end

  @impl true
  def handle_call(:get_all_skills, _from, state) do
    skills_with_capabilities =
      state.skills
      |> Enum.map(fn {skill_module, metadata} ->
        {skill_module,
         Map.put(
           metadata,
           :performance_metrics,
           Map.get(state.performance_metrics, skill_module, %{})
         )}
      end)
      |> Enum.into(%{})

    {:reply, {:ok, skills_with_capabilities}, state}
  end

  @impl true
  def handle_call({:get_capabilities, skill_module}, _from, state) do
    case Map.get(state.skills, skill_module) do
      nil ->
        {:reply, {:error, :skill_not_found}, state}

      skill_metadata ->
        capabilities = Map.get(skill_metadata, :capabilities, %{})
        performance_metrics = Map.get(state.performance_metrics, skill_module, %{})

        enhanced_capabilities =
          Map.merge(capabilities, %{
            performance_metrics: performance_metrics,
            last_updated: Map.get(skill_metadata, :registered_at)
          })

        {:reply, {:ok, enhanced_capabilities}, state}
    end
  end

  @impl true
  def handle_call({:resolve_dependencies, skill_modules}, _from, state) do
    dependency_resolution =
      resolve_skill_dependency_chain(skill_modules, state.dependency_graph, state.skills)

    {:reply, {:ok, dependency_resolution}, state}
  end

  @impl true
  def handle_call({:recommend_skill, agent_need, context, user_id}, _from, state) do
    Logger.debug("Recommending skill for agent need: #{agent_need}")

    if state.config.llm_recommendations_enabled do
      # Use Universal LLM Provider System for intelligent skill recommendation
      case get_llm_skill_recommendation(agent_need, context, state.skills, user_id) do
        {:ok, recommendation} ->
          updated_stats = Map.update!(state.stats, :recommendation_requests, &(&1 + 1))
          {:reply, {:ok, recommendation}, %{state | stats: updated_stats}}

        error ->
          # Fallback to traditional capability matching
          fallback_recommendation = fallback_skill_recommendation(agent_need, state.skills)
          updated_stats = Map.update!(state.stats, :recommendation_requests, &(&1 + 1))
          {:reply, {:ok, fallback_recommendation}, %{state | stats: updated_stats}}
      end
    else
      # Traditional capability matching only
      recommendation = fallback_skill_recommendation(agent_need, state.skills)
      updated_stats = Map.update!(state.stats, :recommendation_requests, &(&1 + 1))
      {:reply, {:ok, recommendation}, %{state | stats: updated_stats}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        cache_hit_rate: calculate_cache_hit_rate(state.stats),
        total_capabilities: count_total_capabilities(state.skills),
        dependency_complexity: calculate_dependency_complexity(state.dependency_graph),
        last_updated: DateTime.utc_now()
      })

    {:reply, {:ok, enhanced_stats}, state}
  end

  @impl true
  def handle_cast(:auto_register_skills, state) do
    Logger.info("Auto-registering all existing skills")

    updated_state =
      Enum.reduce(@skill_modules, state, fn skill_module, acc_state ->
        case extract_skill_metadata(skill_module, %{auto_registered: true}) do
          {:ok, metadata} ->
            updated_skills = Map.put(acc_state.skills, skill_module, metadata)

            updated_dependency_graph =
              update_dependency_graph(acc_state.dependency_graph, skill_module, metadata)

            %{
              acc_state
              | skills: updated_skills,
                dependency_graph: updated_dependency_graph,
                stats: Map.update!(acc_state.stats, :total_skills_registered, &(&1 + 1))
            }

          {:error, reason} ->
            Logger.warning("Failed to auto-register skill #{skill_module}: #{inspect(reason)}")
            acc_state
        end
      end)

    Logger.info(
      "Auto-registration completed: #{map_size(updated_state.skills)} skills registered"
    )

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:skill_performance_update, skill_module, performance_data}, state) do
    # Update skill performance metrics
    updated_performance = Map.put(state.performance_metrics, skill_module, performance_data)

    # Clear relevant cache entries since performance affects recommendations
    updated_cache = clear_performance_related_cache(state.capabilities_cache)

    {:noreply,
     %{state | performance_metrics: updated_performance, capabilities_cache: updated_cache}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp extract_skill_metadata(skill_module, additional_metadata) do
    case safe_extract_skill_metadata(skill_module, additional_metadata) do
      {:ok, metadata} -> {:ok, metadata}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_extract_skill_metadata(skill_module, additional_metadata) do
    # Extract metadata from Jido.Skill configuration
    skill_name = get_skill_name(skill_module)
    signal_patterns = get_skill_signal_patterns(skill_module)
    capabilities = analyze_skill_capabilities(skill_module)
    dependencies = analyze_skill_dependencies(skill_module)

    metadata =
      Map.merge(
        %{
          name: skill_name,
          module: skill_module,
          signal_patterns: signal_patterns,
          capabilities: capabilities,
          dependencies: dependencies,
          version: get_skill_version(skill_module),
          performance_class: classify_skill_performance(skill_module),
          integration_points: get_skill_integration_points(skill_module),
          registered_at: DateTime.utc_now()
        },
        additional_metadata
      )

    {:ok, metadata}
  rescue
    error ->
      {:error, "Failed to extract skill metadata: #{Exception.message(error)}"}
  end

  defp get_skill_name(skill_module) do
    # Extract skill name from module configuration or module name
    case skill_module.__info__(:attributes) do
      attributes when is_list(attributes) ->
        # Look for Jido.Skill name configuration
        case List.keyfind(attributes, :jido_skill_name, 0) do
          {:jido_skill_name, [name]} -> name
          _ -> module_to_skill_name(skill_module)
        end

      _ ->
        module_to_skill_name(skill_module)
    end
  end

  defp module_to_skill_name(skill_module) do
    skill_module
    |> to_string()
    |> String.replace("Elixir.RubberDuck.Skills.", "")
    |> String.replace("Skill", "")
    |> Macro.underscore()
  end

  defp get_skill_signal_patterns(skill_module) do
    # Extract signal patterns from Jido.Skill configuration
    case skill_module.__info__(:attributes) do
      attributes when is_list(attributes) ->
        case List.keyfind(attributes, :jido_skill_patterns, 0) do
          {:jido_skill_patterns, patterns} -> patterns
          _ -> []
        end

      _ ->
        []
    end
  end

  defp analyze_skill_capabilities(skill_module) do
    # Analyze skill module to extract capabilities
    functions = skill_module.__info__(:functions)

    %{
      public_functions: extract_public_functions(functions),
      signal_handling: length(get_skill_signal_patterns(skill_module)),
      complexity_score: calculate_skill_complexity(functions),
      integration_capabilities: analyze_integration_capabilities(skill_module),
      performance_characteristics: estimate_performance_characteristics(skill_module)
    }
  end

  defp analyze_skill_dependencies(skill_module) do
    # Analyze skill dependencies by examining its code and configuration
    %{
      # Would analyze actual dependencies
      required_skills: [],
      optional_skills: [],
      external_dependencies: [],
      llm_provider_usage: skill_uses_llm_providers?(skill_module),
      configuration_requirements: analyze_configuration_needs(skill_module)
    }
  end

  defp get_skill_version(skill_module) do
    # Extract version from module attributes or default to 1.0.0
    case skill_module.__info__(:attributes) do
      attributes when is_list(attributes) ->
        case List.keyfind(attributes, :skill_version, 0) do
          {:skill_version, [version]} -> version
          _ -> "1.0.0"
        end

      _ ->
        "1.0.0"
    end
  end

  defp classify_skill_performance(skill_module) do
    # Classify skill based on expected performance characteristics
    skill_name = module_to_skill_name(skill_module)

    case skill_name do
      name when name in ["learning", "query_optimization"] -> :lightweight
      name when name in ["threat_detection", "code_analysis"] -> :compute_intensive
      name when name in ["project_management", "user_management"] -> :io_bound
      _ -> :standard
    end
  end

  defp get_skill_integration_points(skill_module) do
    # Analyze what systems the skill integrates with
    %{
      # All skills use Jido
      jido_framework: true,
      ash_resources: skill_uses_ash_resources?(skill_module),
      llm_providers: skill_uses_llm_providers?(skill_module),
      external_apis: skill_uses_external_apis?(skill_module),
      database: skill_uses_database?(skill_module)
    }
  end

  defp perform_capability_matching(skills, requirements, config) do
    algorithm = config.capability_matching_algorithm

    case algorithm do
      :weighted_overlap ->
        perform_weighted_overlap_matching(skills, requirements)

      :semantic_similarity ->
        perform_semantic_similarity_matching(skills, requirements)

      :performance_optimized ->
        perform_performance_optimized_matching(skills, requirements)

      _ ->
        perform_simple_matching(skills, requirements)
    end
  end

  defp perform_weighted_overlap_matching(skills, requirements) do
    # Sophisticated capability matching with weighted overlap
    required_capabilities = Map.get(requirements, :capabilities, [])
    performance_requirements = Map.get(requirements, :performance, %{})
    context_requirements = Map.get(requirements, :context, %{})

    skills
    |> Enum.map(fn {skill_module, metadata} ->
      capabilities = Map.get(metadata, :capabilities, %{})

      # Calculate capability overlap score
      capability_score = calculate_capability_overlap(required_capabilities, capabilities)

      # Calculate performance score
      performance_score = calculate_performance_match(performance_requirements, capabilities)

      # Calculate context score
      context_score = calculate_context_match(context_requirements, metadata)

      overall_score = capability_score * 0.5 + performance_score * 0.3 + context_score * 0.2

      {skill_module,
       %{
         metadata: metadata,
         match_score: overall_score,
         capability_score: capability_score,
         performance_score: performance_score,
         context_score: context_score
       }}
    end)
    # Threshold for relevance
    |> Enum.filter(fn {_module, scores} -> scores.match_score > 0.3 end)
    |> Enum.sort_by(fn {_module, scores} -> scores.match_score end, :desc)
  end

  defp perform_simple_matching(skills, requirements) do
    # Simple matching fallback
    required_signals = Map.get(requirements, :signals, [])

    skills
    |> Enum.filter(fn {_skill_module, metadata} ->
      skill_signals = Map.get(metadata, :signal_patterns, [])

      # Check if skill handles any required signals
      signal_overlap =
        MapSet.intersection(
          MapSet.new(required_signals),
          MapSet.new(skill_signals)
        )

      MapSet.size(signal_overlap) > 0
    end)
    |> Enum.map(fn {skill_module, metadata} ->
      {skill_module, %{metadata: metadata, match_score: 0.7}}
    end)
  end

  defp get_llm_skill_recommendation(agent_need, context, available_skills, user_id) do
    # Use Universal LLM Provider System for intelligent skill recommendation
    skill_descriptions =
      available_skills
      |> Enum.map(fn {skill_module, metadata} ->
        "#{metadata.name}: #{Map.get(metadata, :description, "No description")}"
      end)
      |> Enum.join("\n")

    recommendation_prompt = """
    Agent Need: #{agent_need}
    Context: #{inspect(context)}

    Available Skills:
    #{skill_descriptions}

    Please recommend the most appropriate skill(s) for this agent need and context.
    Consider capability overlap, performance characteristics, and contextual relevance.

    Respond in JSON format: {"recommended_skills": ["skill_name1", "skill_name2"], "reasoning": "explanation"}
    """

    case UniversalProviderService.complete(recommendation_prompt, :orchestration, %{
           use_case: :skill_recommendation,
           user_id: user_id,
           specialized_features: [:cost_optimization],
           max_tokens: 500,
           temperature: 0.3
         }) do
      {:ok, llm_response} ->
        parse_llm_skill_recommendation(llm_response.content, available_skills)

      error ->
        Logger.warning("LLM skill recommendation failed: #{inspect(error)}")
        error
    end
  end

  defp parse_llm_skill_recommendation(llm_content, available_skills) do
    case Jason.decode(llm_content) do
      {:ok, %{"recommended_skills" => skill_names, "reasoning" => reasoning}} ->
        # Map skill names back to modules
        recommended_modules =
          skill_names
          |> Enum.map(fn skill_name ->
            find_skill_module_by_name(skill_name, available_skills)
          end)
          |> Enum.filter(&(!is_nil(&1)))

        {:ok,
         %{
           recommended_skills: recommended_modules,
           reasoning: reasoning,
           recommendation_source: :llm_assisted,
           confidence: 0.85
         }}

      {:error, _json_error} ->
        # Fallback to text parsing
        {:ok,
         %{
           recommended_skills: extract_skill_names_from_text(llm_content, available_skills),
           reasoning: llm_content,
           recommendation_source: :llm_text_parsed,
           confidence: 0.7
         }}
    end
  end

  defp fallback_skill_recommendation(agent_need, available_skills) do
    # Simple fallback recommendation based on keyword matching
    need_keywords = extract_keywords_from_need(agent_need)

    matching_skills =
      available_skills
      |> Enum.filter(fn {_module, metadata} ->
        skill_name = Map.get(metadata, :name, "")
        skill_keywords = String.split(skill_name, "_")

        keyword_overlap =
          MapSet.intersection(
            MapSet.new(need_keywords),
            MapSet.new(skill_keywords)
          )

        MapSet.size(keyword_overlap) > 0
      end)
      |> Enum.map(fn {module, _metadata} -> module end)

    %{
      recommended_skills: matching_skills,
      reasoning: "Keyword-based matching fallback",
      recommendation_source: :keyword_matching,
      confidence: 0.6
    }
  end

  defp extract_keywords_from_need(agent_need) do
    agent_need
    |> String.downcase()
    |> String.split(~r/[\s\-_]+/)
    |> Enum.filter(&(String.length(&1) > 2))
  end

  defp find_skill_module_by_name(skill_name, available_skills) do
    available_skills
    |> Enum.find(fn {_module, metadata} ->
      metadata.name == skill_name or String.contains?(metadata.name, skill_name)
    end)
    |> case do
      {module, _metadata} -> module
      nil -> nil
    end
  end

  defp extract_skill_names_from_text(text, available_skills) do
    available_skill_names =
      available_skills
      |> Map.values()
      |> Enum.map(&Map.get(&1, :name, ""))

    available_skill_names
    |> Enum.filter(&String.contains?(String.downcase(text), &1))
    |> Enum.map(&find_skill_module_by_name(&1, available_skills))
    |> Enum.filter(&(!is_nil(&1)))
  end

  # Helper functions for skill analysis

  defp extract_public_functions(functions) do
    functions
    |> Enum.filter(fn {function_name, arity} ->
      # Filter out Jido framework and private functions
      not String.starts_with?(to_string(function_name), "_") and
        function_name not in [:__info__, :child_spec, :start_link]
    end)
    |> Enum.map(fn {function_name, arity} -> {function_name, arity} end)
  end

  defp calculate_skill_complexity(functions) do
    # Simple complexity estimation based on number of public functions
    public_functions = extract_public_functions(functions)

    case length(public_functions) do
      count when count <= 3 -> :simple
      count when count <= 7 -> :moderate
      count when count <= 12 -> :complex
      _ -> :very_complex
    end
  end

  defp analyze_integration_capabilities(skill_module) do
    %{
      jido_integration: true,
      ash_integration: skill_uses_ash_resources?(skill_module),
      llm_integration: skill_uses_llm_providers?(skill_module),
      external_integration: skill_uses_external_apis?(skill_module)
    }
  end

  defp estimate_performance_characteristics(skill_module) do
    skill_name = module_to_skill_name(skill_module)

    # Estimate based on skill type and typical usage patterns
    case skill_name do
      name when name in ["learning", "authentication"] ->
        %{execution_time_ms: 50, memory_usage_mb: 2, cpu_intensity: :low}

      name when name in ["threat_detection", "code_analysis"] ->
        %{execution_time_ms: 500, memory_usage_mb: 10, cpu_intensity: :high}

      name when name in ["project_management", "user_management"] ->
        %{execution_time_ms: 200, memory_usage_mb: 5, cpu_intensity: :medium}

      _ ->
        %{execution_time_ms: 100, memory_usage_mb: 3, cpu_intensity: :medium}
    end
  end

  defp skill_uses_ash_resources?(skill_module) do
    # Simple heuristic - check if module source contains Ash references
    # In production, would do more sophisticated analysis
    String.contains?(to_string(skill_module), "Ash") or
      String.contains?(to_string(skill_module), "Resource")
  end

  defp skill_uses_llm_providers?(skill_module) do
    # Check if skill likely uses LLM providers
    skill_name = module_to_skill_name(skill_module)
    skill_name in ["learning", "code_analysis", "threat_detection"]
  end

  defp skill_uses_external_apis?(skill_module) do
    # Estimate external API usage
    skill_name = module_to_skill_name(skill_module)
    skill_name in ["threat_detection", "project_management"]
  end

  defp skill_uses_database?(skill_module) do
    # Estimate database usage
    skill_name = module_to_skill_name(skill_module)
    skill_name in ["user_management", "authentication", "project_management"]
  end

  defp analyze_configuration_needs(skill_module) do
    skill_name = module_to_skill_name(skill_module)

    case skill_name do
      "authentication" -> %{requires_user_config: true, requires_project_config: false}
      "project_management" -> %{requires_user_config: true, requires_project_config: true}
      "threat_detection" -> %{requires_user_config: false, requires_project_config: true}
      _ -> %{requires_user_config: false, requires_project_config: false}
    end
  end

  defp update_dependency_graph(graph, skill_module, metadata) do
    dependencies = Map.get(metadata, :dependencies, %{})
    required_skills = Map.get(dependencies, :required_skills, [])

    Map.put(graph, skill_module, required_skills)
  end

  defp resolve_skill_dependency_chain(skill_modules, dependency_graph, skills) do
    # Resolve complete dependency chain for set of skills
    all_dependencies =
      skill_modules
      |> Enum.reduce(MapSet.new(), fn skill_module, acc ->
        direct_deps = Map.get(dependency_graph, skill_module, [])
        MapSet.union(acc, MapSet.new(direct_deps))
      end)
      |> MapSet.to_list()

    # Check for circular dependencies
    circular_deps = detect_circular_dependencies(skill_modules, dependency_graph)

    %{
      required_skills: all_dependencies,
      circular_dependencies: circular_deps,
      resolution_order: topological_sort(skill_modules, dependency_graph),
      dependency_depth: calculate_dependency_depth(skill_modules, dependency_graph)
    }
  end

  defp detect_circular_dependencies(skill_modules, dependency_graph) do
    # Simple circular dependency detection
    skill_modules
    |> Enum.filter(fn skill ->
      dependencies = Map.get(dependency_graph, skill, [])
      # Self-dependency is circular
      skill in dependencies
    end)
  end

  defp topological_sort(skill_modules, dependency_graph) do
    # Simple topological sort for dependency order
    # Would implement proper topological sort in production
    skill_modules
  end

  defp calculate_dependency_depth(skill_modules, dependency_graph) do
    # Calculate maximum dependency depth
    skill_modules
    |> Enum.map(fn skill ->
      deps = Map.get(dependency_graph, skill, [])
      length(deps)
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp calculate_capability_overlap(required_capabilities, skill_capabilities) do
    if Enum.empty?(required_capabilities) do
      # Neutral score if no specific requirements
      0.5
    else
      public_functions = Map.get(skill_capabilities, :public_functions, [])
      function_names = Enum.map(public_functions, fn {name, _arity} -> to_string(name) end)

      # Calculate overlap between required capabilities and available functions
      overlap_count =
        required_capabilities
        |> Enum.count(fn capability ->
          Enum.any?(function_names, &String.contains?(&1, capability))
        end)

      overlap_count / length(required_capabilities)
    end
  end

  defp calculate_performance_match(performance_requirements, skill_capabilities) do
    skill_performance = Map.get(skill_capabilities, :performance_characteristics, %{})

    # Simple performance matching
    required_speed = Map.get(performance_requirements, :max_execution_time_ms, 1000)
    skill_speed = Map.get(skill_performance, :execution_time_ms, 100)

    if skill_speed <= required_speed do
      # Better performance = higher score
      1.0 - skill_speed / required_speed * 0.5
    else
      # Performance requirement not met
      0.3
    end
  end

  defp calculate_context_match(context_requirements, skill_metadata) do
    # Context matching based on skill characteristics
    required_integration = Map.get(context_requirements, :integration_type)
    skill_integrations = Map.get(skill_metadata, :integration_points, %{})

    case required_integration do
      :llm_integration -> if skill_integrations.llm_integration, do: 1.0, else: 0.5
      :ash_integration -> if skill_integrations.ash_integration, do: 1.0, else: 0.5
      :external_integration -> if skill_integrations.external_integration, do: 1.0, else: 0.5
      # Default context score
      _ -> 0.8
    end
  end

  defp calculate_cache_hit_rate(stats) do
    total_cache_requests = stats.cache_hits + stats.cache_misses

    if total_cache_requests > 0 do
      stats.cache_hits / total_cache_requests
    else
      0.0
    end
  end

  defp count_total_capabilities(skills) do
    skills
    |> Map.values()
    |> Enum.map(fn metadata ->
      capabilities = Map.get(metadata, :capabilities, %{})
      public_functions = Map.get(capabilities, :public_functions, [])
      length(public_functions)
    end)
    |> Enum.sum()
  end

  defp calculate_dependency_complexity(dependency_graph) do
    if map_size(dependency_graph) == 0 do
      0.0
    else
      total_dependencies =
        dependency_graph
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()

      total_dependencies / map_size(dependency_graph)
    end
  end

  defp clear_performance_related_cache(capabilities_cache) do
    # Clear cache entries that might be affected by performance updates
    # For simplicity, clear all cache in this implementation
    %{}
  end

  # Performance monitoring stubs (would integrate with actual monitoring)

  defp perform_semantic_similarity_matching(_skills, _requirements) do
    # Future implementation - would use embeddings for semantic matching
    []
  end

  defp perform_performance_optimized_matching(skills, requirements) do
    # Performance-first matching
    performance_requirements = Map.get(requirements, :performance, %{})
    max_execution_time = Map.get(performance_requirements, :max_execution_time_ms, 1000)

    skills
    |> Enum.filter(fn {_module, metadata} ->
      capabilities = Map.get(metadata, :capabilities, %{})
      performance = Map.get(capabilities, :performance_characteristics, %{})
      execution_time = Map.get(performance, :execution_time_ms, 100)

      execution_time <= max_execution_time
    end)
    |> Enum.map(fn {module, metadata} ->
      {module, %{metadata: metadata, match_score: 0.8}}
    end)
    |> Enum.sort_by(fn {_module, data} ->
      capabilities = Map.get(data.metadata, :capabilities, %{})
      performance = Map.get(capabilities, :performance_characteristics, %{})
      Map.get(performance, :execution_time_ms, 100)
    end)
  end
end
