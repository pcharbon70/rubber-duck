defmodule RubberDuck.Verdict.Configuration.VerdictConfigurationResolver do
  @moduledoc """
  Verdict-specific configuration resolver that extends the existing
  three-tier preference system with domain-specific resolution logic.
  
  This module integrates with the existing PreferenceResolver to provide
  hierarchical configuration resolution specifically for Verdict framework
  settings, following the pattern: System -> User -> Project.
  
  Key responsibilities:
  - Resolve Verdict configurations through three-tier hierarchy
  - Apply domain-specific validation and defaults
  - Integrate with existing caching infrastructure
  - Handle configuration inheritance and override logic
  """
  
  use GenServer
  
  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.CacheManager
  alias RubberDuck.Verdict.VerdictSystemConfiguration
  alias RubberDuck.Verdict.UserVerdictPreferences
  alias RubberDuck.Verdict.ProjectVerdictSettings
  alias RubberDuck.Verdict.EvaluationCriteriaTemplate
  
  require Logger
  
  @cache_namespace :verdict_configuration
  @default_cache_ttl 3600
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Resolve complete Verdict configuration for a user and optional project.
  
  Follows three-tier hierarchy: System -> User -> Project
  Returns merged configuration with all overrides applied.
  """
  def resolve_configuration(user_id, project_id \\ nil, options \\ []) do
    cache_key = build_cache_key(user_id, project_id, options)
    
    case get_from_cache(cache_key) do
      {:hit, config} ->
        Logger.debug("Verdict configuration cache hit for user #{user_id}")
        {:ok, config}
        
      :miss ->
        case resolve_fresh_configuration(user_id, project_id, options) do
          {:ok, config} ->
            cache_configuration(cache_key, config)
            {:ok, config}
          {:error, reason} = error ->
            Logger.error("Failed to resolve Verdict configuration: #{inspect(reason)}")
            error
        end
    end
  end
  
  @doc """
  Get system-level Verdict configuration defaults.
  """
  def get_system_configuration(options \\ []) do
    cache_key = {:system, :verdict_config, options}
    
    case get_from_cache(cache_key) do
      {:hit, config} -> {:ok, config}
      :miss ->
        case load_system_configuration() do
          {:ok, config} ->
            cache_configuration(cache_key, config)
            {:ok, config}
          error -> error
        end
    end
  end
  
  @doc """
  Get user-specific Verdict preferences.
  """
  def get_user_preferences(user_id, options \\ []) do
    cache_key = {:user, user_id, :verdict_preferences, options}
    
    case get_from_cache(cache_key) do
      {:hit, preferences} -> {:ok, preferences}
      :miss ->
        case load_user_preferences(user_id) do
          {:ok, preferences} ->
            cache_configuration(cache_key, preferences)
            {:ok, preferences}
          error -> error
        end
    end
  end
  
  @doc """
  Get project-specific Verdict settings.
  """
  def get_project_settings(project_id, options \\ []) do
    cache_key = {:project, project_id, :verdict_settings, options}
    
    case get_from_cache(cache_key) do
      {:hit, settings} -> {:ok, settings}
      :miss ->
        case load_project_settings(project_id) do
          {:ok, settings} ->
            cache_configuration(cache_key, settings)
            {:ok, settings}
          error -> error
        end
    end
  end
  
  @doc """
  Invalidate Verdict configuration cache for specific user/project.
  """
  def invalidate_cache(user_id, project_id \\ nil) do
    patterns = [
      build_cache_key(user_id, project_id, []),
      {:user, user_id, :verdict_preferences, :_},
      {:project, project_id, :verdict_settings, :_}
    ]
    
    Enum.each(patterns, &CacheManager.delete(@cache_namespace, &1))
    
    # Also invalidate system cache if this is a system admin action
    CacheManager.delete(@cache_namespace, {:system, :verdict_config, :_})
    
    Logger.info("Invalidated Verdict configuration cache for user #{user_id}, project #{project_id}")
    :ok
  end
  
  @doc """
  Resolve configuration for evaluation template application.
  """
  def resolve_with_template(user_id, project_id, template_id, options \\ []) do
    with {:ok, base_config} <- resolve_configuration(user_id, project_id, options),
         {:ok, template} <- load_evaluation_template(template_id) do
      
      merged_config = apply_template_to_configuration(base_config, template)
      {:ok, merged_config}
    else
      error -> error
    end
  end
  
  # GenServer callbacks
  
  def init(opts) do
    # Subscribe to configuration change notifications
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "verdict_configuration_changes")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "preference_changes")
    
    state = %{
      cache_ttl: Keyword.get(opts, :cache_ttl, @default_cache_ttl),
      stats: %{
        cache_hits: 0,
        cache_misses: 0,
        resolutions: 0
      }
    }
    
    Logger.info("VerdictConfigurationResolver started")
    {:ok, state}
  end
  
  def handle_info({:configuration_changed, type, id}, state) do
    Logger.debug("Verdict configuration changed: #{type} #{id}")
    
    case type do
      :system -> invalidate_system_cache()
      :user -> invalidate_user_cache(id)
      :project -> invalidate_project_cache(id)
      :template -> invalidate_template_cache(id)
    end
    
    {:noreply, state}
  end
  
  def handle_info(_msg, state), do: {:noreply, state}
  
  # Private implementation
  
  defp resolve_fresh_configuration(user_id, project_id, options) do
    Logger.debug("Resolving fresh Verdict configuration for user #{user_id}, project #{project_id}")
    
    with {:ok, system_config} <- get_system_configuration(options),
         {:ok, user_config} <- resolve_user_configuration(user_id, system_config),
         {:ok, final_config} <- resolve_project_configuration(project_id, user_config) do
      
      # Apply any runtime options
      final_config = apply_runtime_options(final_config, options)
      
      Logger.debug("Successfully resolved Verdict configuration")
      {:ok, final_config}
    else
      error ->
        Logger.error("Failed to resolve Verdict configuration: #{inspect(error)}")
        error
    end
  end
  
  defp resolve_user_configuration(user_id, system_config) do
    case get_user_preferences(user_id) do
      {:ok, user_preferences} ->
        merged_config = UserVerdictPreferences.apply_user_preferences(system_config, user_preferences)
        {:ok, merged_config}
      
      {:error, :not_found} ->
        Logger.debug("No user Verdict preferences found for user #{user_id}, using system defaults")
        {:ok, system_config}
      
      error -> error
    end
  end
  
  defp resolve_project_configuration(nil, user_config), do: {:ok, user_config}
  defp resolve_project_configuration(project_id, user_config) do
    case get_project_settings(project_id) do
      {:ok, project_settings} ->
        merged_config = ProjectVerdictSettings.apply_project_settings(user_config, project_settings)
        {:ok, merged_config}
      
      {:error, :not_found} ->
        Logger.debug("No project Verdict settings found for project #{project_id}, using user/system config")
        {:ok, user_config}
      
      error -> error
    end
  end
  
  defp load_system_configuration do
    case VerdictSystemConfiguration.get_active_configuration() do
      {:ok, config} ->
        config_map = Map.from_struct(config) |> Map.drop([:__meta__, :__struct__])
        {:ok, config_map}
      
      {:error, :not_found} ->
        Logger.info("No system Verdict configuration found, using defaults")
        {:ok, VerdictSystemConfiguration.get_default_configuration()}
      
      error -> error
    end
  end
  
  defp load_user_preferences(user_id) do
    case UserVerdictPreferences.by_user(user_id) do
      {:ok, preferences} ->
        preferences_map = Map.from_struct(preferences) |> Map.drop([:__meta__, :__struct__])
        {:ok, preferences_map}
      
      error -> error
    end
  end
  
  defp load_project_settings(project_id) do
    case ProjectVerdictSettings.by_project(project_id) do
      {:ok, settings} ->
        settings_map = Map.from_struct(settings) |> Map.drop([:__meta__, :__struct__])
        {:ok, settings_map}
      
      error -> error
    end
  end
  
  defp load_evaluation_template(template_id) do
    case Ash.get(EvaluationCriteriaTemplate, template_id) do
      {:ok, template} ->
        template_map = Map.from_struct(template) |> Map.drop([:__meta__, :__struct__])
        {:ok, template_map}
      
      error -> error
    end
  end
  
  defp apply_template_to_configuration(config, template) do
    config
    |> Map.put(:evaluation_criteria_weights, Map.get(template, :criteria_weights, %{}))
    |> Map.put(:quality_thresholds, Map.get(template, :quality_thresholds, %{}))
    |> Map.put(:evaluation_prompts, Map.get(template, :evaluation_prompts, %{}))
    |> Map.put(:judge_instructions, Map.get(template, :judge_instructions, %{}))
    |> Map.put(:escalation_rules, Map.get(template, :escalation_rules, %{}))
    |> Map.put(:template_id, Map.get(template, :id))
    |> Map.put(:template_version, Map.get(template, :version))
  end
  
  defp apply_runtime_options(config, options) do
    options
    |> Enum.reduce(config, fn {key, value}, acc ->
      case key do
        :force_detailed_evaluation -> Map.put(acc, :progressive_evaluation_enabled, false)
        :override_quality_threshold -> Map.put(acc, :default_quality_threshold, value)
        :budget_override -> Map.put(acc, :global_daily_budget, value)
        :provider_override -> Map.put(acc, :preferred_providers, List.wrap(value))
        _ -> acc
      end
    end)
  end
  
  defp build_cache_key(user_id, project_id, options) do
    base_key = if project_id do
      {:verdict_config, user_id, project_id}
    else
      {:verdict_config, user_id, :no_project}
    end
    
    case options do
      [] -> base_key
      opts -> {base_key, :erlang.phash2(opts)}
    end
  end
  
  defp get_from_cache(cache_key) do
    case CacheManager.get(@cache_namespace, cache_key) do
      {:ok, value} -> {:hit, value}
      {:error, :not_found} -> :miss
      {:error, _reason} -> :miss
    end
  end
  
  defp cache_configuration(cache_key, config) do
    CacheManager.put(@cache_namespace, cache_key, config, @default_cache_ttl)
  end
  
  defp invalidate_system_cache do
    CacheManager.delete_pattern(@cache_namespace, {:system, :_, :_})
  end
  
  defp invalidate_user_cache(user_id) do
    CacheManager.delete_pattern(@cache_namespace, {:user, user_id, :_, :_})
    CacheManager.delete_pattern(@cache_namespace, {:verdict_config, user_id, :_})
  end
  
  defp invalidate_project_cache(project_id) do
    CacheManager.delete_pattern(@cache_namespace, {:project, project_id, :_, :_})
    CacheManager.delete_pattern(@cache_namespace, {:verdict_config, :_, project_id})
  end
  
  defp invalidate_template_cache(template_id) do
    # Templates affect resolved configurations that use them
    CacheManager.delete_pattern(@cache_namespace, {:verdict_config, :_, :_})
    Logger.debug("Invalidated configuration cache due to template #{template_id} change")
  end
  
  # Configuration resolution utilities
  
  def validate_resolved_configuration(config) do
    VerdictSystemConfiguration.validate_configuration(config)
  end
  
  def get_configuration_source_chain(user_id, project_id \\ nil) do
    chain = []
    
    # Add system configuration
    chain = case get_system_configuration() do
      {:ok, _config} -> [%{level: :system, source: "system_configuration"} | chain]
      _ -> [%{level: :system, source: "default_fallback"} | chain]
    end
    
    # Add user preferences if they exist
    chain = case get_user_preferences(user_id) do
      {:ok, _preferences} -> [%{level: :user, source: "user_preferences", user_id: user_id} | chain]
      _ -> chain
    end
    
    # Add project settings if they exist and project_id provided
    chain = if project_id do
      case get_project_settings(project_id) do
        {:ok, _settings} -> [%{level: :project, source: "project_settings", project_id: project_id} | chain]
        _ -> chain
      end
    else
      chain
    end
    
    Enum.reverse(chain)
  end
  
  def get_configuration_diff(user_id, project_id \\ nil) do
    with {:ok, system_config} <- get_system_configuration(),
         {:ok, final_config} <- resolve_configuration(user_id, project_id) do
      
      diff = calculate_configuration_differences(system_config, final_config)
      source_chain = get_configuration_source_chain(user_id, project_id)
      
      {:ok, %{
        diff: diff,
        source_chain: source_chain,
        override_count: map_size(diff),
        inheritance_levels: length(source_chain)
      }}
    else
      error -> error
    end
  end
  
  defp calculate_configuration_differences(base_config, final_config) do
    base_config
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc ->
      base_value = Map.get(base_config, key)
      final_value = Map.get(final_config, key)
      
      if base_value != final_value do
        Map.put(acc, key, %{
          system_value: base_value,
          final_value: final_value,
          overridden: true
        })
      else
        acc
      end
    end)
  end
  
  # Performance and monitoring utilities
  
  def get_cache_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def warm_cache_for_user(user_id) do
    Logger.debug("Warming Verdict configuration cache for user #{user_id}")
    
    # Pre-load user configuration
    resolve_configuration(user_id)
    
    # Pre-load user's project configurations
    case get_user_projects(user_id) do
      {:ok, projects} ->
        Enum.each(projects, fn project ->
          resolve_configuration(user_id, project.id)
        end)
      _ -> :ok
    end
  end
  
  def clear_all_cache do
    CacheManager.clear(@cache_namespace)
    Logger.info("Cleared all Verdict configuration cache")
    :ok
  end
  
  # Integration with existing preference system
  
  def integrate_with_preference_resolver do
    # Register Verdict domain with existing PreferenceResolver
    PreferenceResolver.register_domain(:verdict, %{
      resolver_module: __MODULE__,
      cache_namespace: @cache_namespace,
      default_ttl: @default_cache_ttl,
      validation_module: RubberDuck.Verdict.Configuration.ConfigurationValidator
    })
  end
  
  def resolve_preference_key(key, user_id, project_id \\ nil) do
    with {:ok, config} <- resolve_configuration(user_id, project_id) do
      value = get_nested_value(config, key)
      {:ok, value}
    else
      error -> error
    end
  end
  
  defp get_nested_value(config, key) when is_binary(key) do
    key
    |> String.split(".")
    |> Enum.reduce(config, fn part, acc ->
      case acc do
        acc when is_map(acc) -> Map.get(acc, part) || Map.get(acc, String.to_atom(part))
        _ -> nil
      end
    end)
  end
  
  defp get_nested_value(config, key) when is_atom(key) do
    Map.get(config, key)
  end
  
  defp get_user_projects(_user_id) do
    # This would integrate with the existing project system
    # For now, return empty list
    {:ok, []}
  end
  
  # GenServer implementation
  
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  def handle_call({:resolve_configuration, user_id, project_id, options}, _from, state) do
    result = resolve_configuration(user_id, project_id, options)
    
    updated_stats = case result do
      {:ok, _} -> Map.update!(state.stats, :resolutions, &(&1 + 1))
      _ -> state.stats
    end
    
    {:reply, result, %{state | stats: updated_stats}}
  end
  
  def handle_call(_msg, _from, state), do: {:reply, :ok, state}
  
  def handle_cast({:invalidate_cache, user_id, project_id}, state) do
    invalidate_cache(user_id, project_id)
    {:noreply, state}
  end
  
  def handle_cast(_msg, state), do: {:noreply, state}
  
  # Configuration validation helpers
  
  def validate_configuration_consistency(user_id, project_id \\ nil) do
    with {:ok, config} <- resolve_configuration(user_id, project_id),
         :ok <- validate_resolved_configuration(config) do
      
      # Additional Verdict-specific consistency checks
      validation_results = [
        validate_budget_threshold_consistency(config),
        validate_provider_model_consistency(config),
        validate_criteria_escalation_consistency(config)
      ]
      
      case Enum.find(validation_results, fn result -> result != :ok end) do
        nil -> {:ok, config}
        error -> error
      end
    else
      error -> error
    end
  end
  
  defp validate_budget_threshold_consistency(config) do
    budget = Map.get(config, :global_daily_budget, 0)
    max_tokens = Map.get(config, :max_tokens_per_evaluation, 1500)
    
    # Rough cost estimation: $0.01 per 1000 tokens for screening model
    estimated_cost_per_eval = max_tokens * 0.01 / 1000
    max_daily_evaluations = budget / estimated_cost_per_eval
    
    if max_daily_evaluations < 1 do
      {:error, "Daily budget too low for configured max tokens per evaluation"}
    else
      :ok
    end
  end
  
  defp validate_provider_model_consistency(config) do
    providers = Map.get(config, :preferred_providers, [])
    screening_model = Map.get(config, :default_screening_model)
    detailed_model = Map.get(config, :default_detailed_model)
    
    # Validate that specified models are compatible with preferred providers
    model_provider_map = %{
      "gpt-4o" => "openai",
      "gpt-4o-mini" => "openai", 
      "claude-3-sonnet" => "anthropic",
      "claude-3-haiku" => "anthropic"
    }
    
    screening_provider = Map.get(model_provider_map, screening_model)
    detailed_provider = Map.get(model_provider_map, detailed_model)
    
    cond do
      screening_provider && screening_provider not in providers ->
        {:error, "Screening model #{screening_model} requires provider #{screening_provider}"}
      detailed_provider && detailed_provider not in providers ->
        {:error, "Detailed model #{detailed_model} requires provider #{detailed_provider}"}
      true -> :ok
    end
  end
  
  defp validate_criteria_escalation_consistency(config) do
    quality_threshold = Map.get(config, :default_quality_threshold, 0.8)
    escalation_threshold = Map.get(config, :escalation_threshold, 0.6)
    
    quality_float = case quality_threshold do
      %Decimal{} = d -> Decimal.to_float(d)
      f when is_number(f) -> f
      _ -> 0.8
    end
    
    escalation_float = case escalation_threshold do
      %Decimal{} = d -> Decimal.to_float(d)
      f when is_number(f) -> f
      _ -> 0.6
    end
    
    if escalation_float >= quality_float do
      {:error, "Escalation threshold must be lower than quality threshold"}
    else
      :ok
    end
  end
end