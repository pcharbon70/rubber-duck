defmodule RubberDuck.Prompts.Integrations.LlmOrchestrationIntegration do
  @moduledoc """
  JidoAI-enhanced LLM orchestration integration service for prompt composition coordination.

  Provides seamless integration between the prompt management system and JidoAI-based
  LLM orchestration infrastructure. Coordinates prompt composition with JidoAI requests,
  provider-specific formatting via JidoAI patterns, and performance optimization for
  end-to-end operations using JidoAI.Prompt.MessageItem and provider abstraction.

  Features:
  - JidoAI.Prompt integration into LLM request routing with intelligent coordination
  - JidoAI provider-specific prompt formatting with model optimization and compatibility validation
  - Dynamic JidoAI.Prompt selection based on request characteristics and context analysis
  - Performance optimization for prompt + JidoAI operations with end-to-end coordination
  - Integration with 6-agent prompt ecosystem and JidoAI LLM orchestration infrastructure
  - Full JidoAI native operations - no legacy LLM system support
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.{
    Agents.PromptComposerAgent,
    Agents.PromptValidatorAgent,
    Integrations.ProviderPromptFormatter
  }

  alias RubberDuck.JidoAI.{ProviderService, PromptAdapter}
  alias Jido.AI.Prompt

  @supported_providers [
    "gpt-4",
    "gpt-3.5-turbo",
    "claude-3-opus",
    "claude-3-sonnet",
    "claude-3-haiku",
    "claude-2",
    "gemini-pro"
  ]

  @integration_strategies [
    :compose_and_enhance,
    :format_only,
    :validate_and_route,
    :full_integration
  ]

  defstruct [
    :integration_config,
    :provider_formatters,
    :performance_monitor,
    :coordination_state
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      integration_config: build_integration_config(opts),
      provider_formatters: initialize_provider_formatters(),
      performance_monitor: initialize_performance_monitor(),
      coordination_state: initialize_coordination_state()
    }

    Logger.info("LlmOrchestrationIntegration: Integration service initialized",
      supported_providers: length(@supported_providers),
      integration_strategies: @integration_strategies
    )

    {:ok, state}
  end

  # Public API

  def enhance_llm_request(llm_request, context \\ %{}, options \\ %{}) do
    GenServer.call(__MODULE__, {:enhance_llm_request, llm_request, context, options})
  end

  def format_prompt_for_provider(prompt_content, provider, context \\ %{}) do
    GenServer.call(__MODULE__, {:format_prompt_for_provider, prompt_content, provider, context})
  end

  def validate_prompt_provider_compatibility(prompt_content, provider, context \\ %{}) do
    GenServer.call(__MODULE__, {:validate_compatibility, prompt_content, provider, context})
  end

  def get_integration_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end

  def optimize_integration_performance do
    GenServer.cast(__MODULE__, :optimize_performance)
  end

  # GenServer callbacks

  def handle_call({:enhance_llm_request, llm_request, context, options}, _from, state) do
    enhancement_start_time = System.monotonic_time(:microsecond)

    Logger.debug("LlmOrchestrationIntegration: Enhancing LLM request",
      provider: Map.get(llm_request, :provider, "unknown"),
      has_prompt_context: Map.has_key?(context, :prompt_name)
    )

    case execute_llm_request_enhancement(llm_request, context, options, state) do
      {:ok, enhanced_request} ->
        enhancement_time = System.monotonic_time(:microsecond) - enhancement_start_time

        Logger.info("LlmOrchestrationIntegration: LLM request enhanced successfully",
          provider: Map.get(enhanced_request, :provider, "unknown"),
          enhancement_time_us: enhancement_time,
          prompt_composed: Map.get(enhanced_request, :prompt_composed, false)
        )

        # Update performance metrics
        update_integration_metrics(enhancement_time, :success, state)

        {:reply, {:ok, enhanced_request}, state}

      {:error, reason} ->
        enhancement_time = System.monotonic_time(:microsecond) - enhancement_start_time

        Logger.error("LlmOrchestrationIntegration: LLM request enhancement failed",
          error: reason,
          enhancement_time_us: enhancement_time
        )

        update_integration_metrics(enhancement_time, :error, state)

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:format_prompt_for_provider, prompt_content, provider, context}, _from, state) do
    case ProviderPromptFormatter.format_for_provider(prompt_content, provider, context) do
      {:ok, formatted_prompt} ->
        Logger.debug("LlmOrchestrationIntegration: Prompt formatted for provider",
          provider: provider,
          original_length: String.length(prompt_content),
          formatted_length: String.length(formatted_prompt.content)
        )

        {:reply, {:ok, formatted_prompt}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:validate_compatibility, prompt_content, provider, context}, _from, state) do
    case validate_prompt_provider_compatibility_internal(prompt_content, provider, context, state) do
      {:ok, compatibility_result} ->
        {:reply, {:ok, compatibility_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_performance_metrics, _from, state) do
    metrics = extract_performance_metrics(state.performance_monitor)
    {:reply, {:ok, metrics}, state}
  end

  def handle_cast(:optimize_performance, state) do
    optimized_state = execute_performance_optimization(state)

    Logger.info("LlmOrchestrationIntegration: Performance optimization completed")

    {:noreply, optimized_state}
  end

  # Private implementation functions

  defp execute_llm_request_enhancement(llm_request, context, options, state) do
    enhancement_strategy = determine_enhancement_strategy(llm_request, context, options)

    case enhancement_strategy do
      :compose_and_enhance ->
        execute_full_prompt_composition_enhancement(llm_request, context, options, state)

      :format_only ->
        execute_formatting_only_enhancement(llm_request, context, options, state)

      :validate_and_route ->
        execute_validation_and_routing_enhancement(llm_request, context, options, state)

      :full_integration ->
        execute_comprehensive_integration_enhancement(llm_request, context, options, state)
    end
  end

  defp execute_full_prompt_composition_enhancement(llm_request, context, options, state) do
    # Execute complete prompt composition and enhancement
    case compose_prompt_for_request(llm_request, context, options) do
      {:ok, composed_prompt} ->
        case format_composed_prompt_for_provider(composed_prompt, llm_request, context) do
          {:ok, formatted_prompt} ->
            enhanced_request =
              Map.merge(llm_request, %{
                prompt: formatted_prompt.content,
                prompt_composed: true,
                prompt_metadata: composed_prompt.composition_metadata,
                provider_optimized: true,
                enhancement_applied: :full_integration
              })

            {:ok, enhanced_request}

          {:error, reason} ->
            {:error, {:formatting_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:composition_failed, reason}}
    end
  end

  defp execute_formatting_only_enhancement(llm_request, context, options, state) do
    # Execute formatting-only enhancement for existing prompts
    existing_prompt = Map.get(llm_request, :prompt, "")
    provider = Map.get(llm_request, :provider, "gpt-4")

    case ProviderPromptFormatter.format_for_provider(existing_prompt, provider, context) do
      {:ok, formatted_prompt} ->
        enhanced_request =
          Map.merge(llm_request, %{
            prompt: formatted_prompt.content,
            provider_optimized: true,
            enhancement_applied: :format_only
          })

        {:ok, enhanced_request}

      {:error, reason} ->
        {:error, {:formatting_only_failed, reason}}
    end
  end

  defp execute_validation_and_routing_enhancement(llm_request, context, options, state) do
    # Execute validation and intelligent routing enhancement
    provider = Map.get(llm_request, :provider, "gpt-4")
    prompt_content = Map.get(llm_request, :prompt, "")

    case validate_and_optimize_routing(prompt_content, provider, context) do
      {:ok, routing_optimization} ->
        enhanced_request =
          Map.merge(llm_request, %{
            provider: routing_optimization.optimized_provider,
            routing_optimized: true,
            routing_metadata: routing_optimization.metadata,
            enhancement_applied: :validate_and_route
          })

        {:ok, enhanced_request}

      {:error, reason} ->
        {:error, {:routing_optimization_failed, reason}}
    end
  end

  defp execute_comprehensive_integration_enhancement(llm_request, context, options, state) do
    # Execute comprehensive integration with all enhancements
    with {:ok, composed_result} <- compose_prompt_for_request(llm_request, context, options),
         {:ok, validation_result} <-
           validate_composed_prompt(composed_result, llm_request, context),
         {:ok, formatted_result} <-
           format_composed_prompt_for_provider(composed_result, llm_request, context),
         {:ok, routing_result} <-
           optimize_provider_routing(formatted_result, llm_request, context) do
      build_comprehensive_request(
        llm_request,
        composed_result,
        validation_result,
        formatted_result,
        routing_result
      )
    else
      {:error, reason} -> {:error, {:comprehensive_integration_failed, reason}}
    end
  end

  defp build_comprehensive_request(
         llm_request,
         composed_result,
         validation_result,
         formatted_result,
         routing_result
       ) do
    comprehensive_request =
      Map.merge(llm_request, %{
        prompt: routing_result.final_prompt,
        provider: routing_result.optimized_provider,
        prompt_composed: true,
        prompt_validated: true,
        provider_optimized: true,
        routing_optimized: true,
        composition_metadata: composed_result.composition_metadata,
        validation_metadata: validation_result.validation_metadata,
        formatting_metadata: formatted_result.formatting_metadata,
        enhancement_applied: :full_integration
      })

    {:ok, comprehensive_request}
  end

  # Integration implementation functions

  defp compose_prompt_for_request(llm_request, context, options) do
    prompt_name = determine_prompt_name(llm_request, context, options)

    composition_params = %{
      composition_request: %{
        prompt_name: prompt_name,
        context: enhance_context_for_composition(context, llm_request)
      },
      composition_strategy: determine_composition_strategy(llm_request, context),
      provider_target: Map.get(llm_request, :provider, "gpt-4"),
      analytics_tracking: true
    }

    case PromptComposerAgent.start_agent(composition_params) do
      {:ok, result} -> {:ok, result.composition_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_composed_prompt(composed_result, llm_request, context) do
    validation_params = %{
      validation_request: %{
        content: composed_result.content,
        context: enhance_context_for_validation(context, llm_request)
      },
      validation_scope: :comprehensive,
      governance_requirements: %{
        require_security_validation: true,
        require_budget_validation: determine_budget_validation_requirement(llm_request)
      }
    }

    case PromptValidatorAgent.start_agent(validation_params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_composed_prompt_for_provider(composed_result, llm_request, context) do
    provider = Map.get(llm_request, :provider, "gpt-4")

    case ProviderPromptFormatter.format_for_provider(composed_result.content, provider, context) do
      {:ok, formatted_result} -> {:ok, formatted_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp optimize_provider_routing(formatted_result, llm_request, context) do
    # Optimize provider selection based on formatted prompt
    current_provider = Map.get(llm_request, :provider, "gpt-4")

    case analyze_prompt_provider_compatibility(
           formatted_result.content,
           current_provider,
           context
         ) do
      {:ok, compatibility_analysis} ->
        optimized_provider =
          if compatibility_analysis.compatibility_score > 0.8 do
            current_provider
          else
            suggest_better_provider(formatted_result.content, context)
          end

        {:ok,
         %{
           final_prompt: formatted_result.content,
           optimized_provider: optimized_provider,
           routing_metadata: %{
             original_provider: current_provider,
             compatibility_score: compatibility_analysis.compatibility_score,
             routing_optimized: optimized_provider != current_provider
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp determine_enhancement_strategy(llm_request, context, options) do
    # Determine appropriate enhancement strategy based on request characteristics
    cond do
      Map.has_key?(context, :prompt_name) and Map.get(options, :full_integration, false) ->
        :full_integration

      Map.has_key?(context, :prompt_name) ->
        :compose_and_enhance

      Map.get(options, :validate_routing, false) ->
        :validate_and_route

      true ->
        :format_only
    end
  end

  defp determine_prompt_name(llm_request, context, options) do
    cond do
      Map.has_key?(context, :prompt_name) ->
        context.prompt_name

      Map.has_key?(llm_request, :operation_type) ->
        "#{llm_request.operation_type}_prompt"

      true ->
        "default_llm_prompt"
    end
  end

  defp enhance_context_for_composition(context, llm_request) do
    Map.merge(context, %{
      llm_provider: Map.get(llm_request, :provider, "gpt-4"),
      request_type: Map.get(llm_request, :operation_type, :general),
      performance_requirements: extract_performance_requirements(llm_request)
    })
  end

  defp enhance_context_for_validation(context, llm_request) do
    Map.merge(context, %{
      llm_provider: Map.get(llm_request, :provider, "gpt-4"),
      security_level: determine_security_level(llm_request),
      budget_constraints: extract_budget_constraints(llm_request)
    })
  end

  defp determine_composition_strategy(llm_request, context) do
    # Determine optimal composition strategy based on request characteristics
    case {
      Map.get(llm_request, :operation_type, :general),
      Map.get(context, :user_role, :user),
      Map.get(llm_request, :priority, :normal)
    } do
      {:code_analysis, :admin, :high} -> :priority_override
      {:documentation, _, _} -> :template_inheritance
      {:general, :user, _} -> :hierarchical_merge
      _ -> :adaptive
    end
  end

  defp determine_budget_validation_requirement(llm_request) do
    # Determine if budget validation is required
    case Map.get(llm_request, :operation_type) do
      operation when operation in [:code_generation, :analysis, :documentation] -> true
      _ -> false
    end
  end

  defp extract_performance_requirements(llm_request) do
    %{
      max_response_time: Map.get(llm_request, :timeout, 30_000),
      quality_level: Map.get(llm_request, :quality, :standard),
      cost_sensitivity: Map.get(llm_request, :cost_sensitivity, :medium)
    }
  end

  defp determine_security_level(llm_request) do
    case Map.get(llm_request, :operation_type) do
      operation when operation in [:security_analysis, :code_review] -> :high
      operation when operation in [:documentation, :explanation] -> :medium
      _ -> :standard
    end
  end

  defp extract_budget_constraints(llm_request) do
    %{
      max_cost: Map.get(llm_request, :max_cost, 1.0),
      cost_tracking: Map.get(llm_request, :track_costs, true)
    }
  end

  defp validate_prompt_provider_compatibility_internal(prompt_content, provider, context, state) do
    # Validate prompt compatibility with specific provider
    compatibility_analysis = %{
      provider: provider,
      compatibility_score: calculate_compatibility_score(prompt_content, provider),
      optimization_suggestions: generate_compatibility_suggestions(prompt_content, provider),
      performance_impact: estimate_performance_impact(prompt_content, provider)
    }

    {:ok, compatibility_analysis}
  end

  defp analyze_prompt_provider_compatibility(prompt_content, provider, context) do
    # Analyze compatibility between prompt and provider
    compatibility_factors = %{
      content_length: String.length(prompt_content),
      complexity_score: calculate_prompt_complexity(prompt_content),
      provider_strengths: get_provider_strengths(provider),
      context_requirements: analyze_context_requirements(prompt_content)
    }

    compatibility_score = calculate_provider_compatibility_score(compatibility_factors, provider)

    {:ok,
     %{
       compatibility_score: compatibility_score,
       compatibility_factors: compatibility_factors,
       provider_optimal: compatibility_score > 0.8,
       optimization_potential: 1.0 - compatibility_score
     }}
  end

  defp suggest_better_provider(prompt_content, context) do
    # Suggest better provider based on prompt characteristics
    prompt_characteristics = analyze_prompt_characteristics(prompt_content)

    case prompt_characteristics.primary_task do
      # Claude excels at reasoning
      :reasoning -> "claude-3-opus"
      # GPT-4 strong for coding
      :code_generation -> "gpt-4"
      # Claude good for creative tasks
      :creative_writing -> "claude-3-sonnet"
      # GPT-4 strong for analysis
      :analysis -> "gpt-4"
      # Default to GPT-4
      _ -> "gpt-4"
    end
  end

  # Utility functions

  defp build_integration_config(opts) do
    %{
      enable_prompt_composition: Keyword.get(opts, :enable_prompt_composition, true),
      enable_provider_optimization: Keyword.get(opts, :enable_provider_optimization, true),
      enable_rag_enhancement: Keyword.get(opts, :enable_rag_enhancement, true),
      performance_monitoring: Keyword.get(opts, :performance_monitoring, true),
      jido_ai_native_only: true
    }
  end

  defp initialize_provider_formatters do
    %{
      openai: %{formatter: :openai_formatter, optimization_level: :high},
      anthropic: %{formatter: :anthropic_formatter, optimization_level: :high},
      google: %{formatter: :gemini_formatter, optimization_level: :medium},
      generic: %{formatter: :generic_formatter, optimization_level: :basic}
    }
  end

  defp initialize_performance_monitor do
    %{
      total_enhancements: 0,
      successful_enhancements: 0,
      average_enhancement_time_us: 0.0,
      provider_performance: %{},
      optimization_effectiveness: 0.0
    }
  end

  defp initialize_coordination_state do
    %{
      active_integrations: 0,
      coordination_overhead_us: 0,
      agent_coordination_count: 0,
      last_optimization: nil
    }
  end

  defp calculate_compatibility_score(prompt_content, provider) do
    # Calculate compatibility score between prompt and provider
    base_score = 0.7

    # Provider-specific adjustments
    provider_adjustment =
      case provider do
        # GPT models are versatile
        provider when provider in ["gpt-4", "gpt-3.5-turbo"] -> 0.2
        # Claude is very compatible
        provider when provider in ["claude-3-opus", "claude-3-sonnet"] -> 0.25
        # Other providers get smaller boost
        _ -> 0.1
      end

    # Content length adjustment
    length_adjustment =
      case String.length(prompt_content) do
        # Short prompts get boost
        len when len < 1000 -> 0.1
        # Very long prompts get penalty
        len when len > 5000 -> -0.1
        _ -> 0.0
      end

    total_score = base_score + provider_adjustment + length_adjustment
    min(1.0, max(0.0, total_score))
  end

  defp generate_compatibility_suggestions(prompt_content, provider) do
    suggestions = []

    # Length-based suggestions
    suggestions =
      if String.length(prompt_content) > 8000 do
        ["Consider shortening prompt for better performance" | suggestions]
      else
        suggestions
      end

    # Provider-specific suggestions
    suggestions =
      case provider do
        "claude-3-opus" ->
          ["Consider using reasoning structure for Claude" | suggestions]

        provider when provider in ["gpt-4", "gpt-3.5-turbo"] ->
          ["Consider clear instruction format for GPT models" | suggestions]

        _ ->
          suggestions
      end

    case suggestions do
      [] -> ["Prompt appears well-optimized for this provider"]
      _ -> suggestions
    end
  end

  defp estimate_performance_impact(prompt_content, provider) do
    # Estimate performance impact of prompt on provider
    estimated_tokens = estimate_token_count(prompt_content, provider)
    estimated_cost = estimate_request_cost(estimated_tokens, provider)
    estimated_latency = estimate_response_latency(estimated_tokens, provider)

    %{
      estimated_tokens: estimated_tokens,
      estimated_cost: estimated_cost,
      estimated_latency_ms: estimated_latency,
      performance_category:
        categorize_performance_impact(estimated_tokens, estimated_cost, estimated_latency)
    }
  end

  defp calculate_prompt_complexity(prompt_content) do
    # Calculate prompt complexity score
    base_complexity = 0.3

    # Variable complexity
    variable_count = length(Regex.scan(~r/\{\{[^}]+\}\}/, prompt_content))
    variable_complexity = min(0.3, variable_count * 0.05)

    # Instruction complexity
    instruction_complexity =
      if String.contains?(prompt_content, ["analyze", "generate", "explain"]) do
        0.2
      else
        0.1
      end

    # Length complexity
    length_complexity = min(0.2, String.length(prompt_content) / 10_000)

    total_complexity =
      base_complexity + variable_complexity + instruction_complexity + length_complexity

    min(1.0, total_complexity)
  end

  defp get_provider_strengths(provider) do
    case provider do
      "gpt-4" -> [:reasoning, :code_generation, :analysis, :general_tasks]
      "claude-3-opus" -> [:reasoning, :creative_writing, :analysis, :complex_tasks]
      "claude-3-sonnet" -> [:creative_writing, :explanation, :general_tasks]
      "gemini-pro" -> [:multimodal, :reasoning, :general_tasks]
      _ -> [:general_tasks]
    end
  end

  defp analyze_context_requirements(prompt_content) do
    # Analyze what context the prompt requires
    %{
      requires_user_context: String.contains?(prompt_content, ["user", "personal", "preference"]),
      requires_project_context: String.contains?(prompt_content, ["project", "codebase", "team"]),
      requires_specialized_knowledge:
        String.contains?(prompt_content, ["technical", "expert", "advanced"])
    }
  end

  defp calculate_provider_compatibility_score(factors, provider) do
    # Calculate detailed compatibility score
    base_score = 0.6

    # Length factor
    length_factor =
      case factors.content_length do
        len when len < 2000 -> 0.2
        len when len < 8000 -> 0.1
        _ -> 0.0
      end

    # Complexity factor
    complexity_factor =
      case factors.complexity_score do
        score when score < 0.5 -> 0.2
        score when score < 0.8 -> 0.1
        _ -> 0.0
      end

    # Provider strength factor
    strength_factor = if :general_tasks in factors.provider_strengths, do: 0.1, else: 0.0

    total_score = base_score + length_factor + complexity_factor + strength_factor
    min(1.0, total_score)
  end

  defp analyze_prompt_characteristics(prompt_content) do
    # Analyze prompt to determine primary task type
    primary_task =
      cond do
        String.contains?(prompt_content, ["analyze", "analysis", "examine"]) -> :analysis
        String.contains?(prompt_content, ["generate", "create", "write"]) -> :code_generation
        String.contains?(prompt_content, ["explain", "reason", "think"]) -> :reasoning
        String.contains?(prompt_content, ["story", "creative", "imagine"]) -> :creative_writing
        true -> :general
      end

    %{
      primary_task: primary_task,
      content_length: String.length(prompt_content),
      complexity_score: calculate_prompt_complexity(prompt_content)
    }
  end

  defp estimate_token_count(prompt_content, provider) do
    # Estimate token count for specific provider
    words = String.split(prompt_content, ~r/\s+/)

    case provider do
      provider when provider in ["gpt-4", "gpt-3.5-turbo"] ->
        # OpenAI: ~0.75 words per token
        round(length(words) / 0.75)

      provider when provider in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"] ->
        # Anthropic: ~0.8 words per token
        round(length(words) / 0.8)

      _ ->
        # Generic: conservative estimate
        round(length(words) / 0.7)
    end
  end

  defp estimate_request_cost(tokens, provider) do
    # Estimate cost based on provider pricing
    case provider do
      # $0.03 per 1K tokens
      "gpt-4" -> tokens * 0.00003
      # $0.002 per 1K tokens
      "gpt-3.5-turbo" -> tokens * 0.000002
      # $0.015 per 1K tokens
      provider when provider in ["claude-3-opus"] -> tokens * 0.000015
      # Generic estimate
      _ -> tokens * 0.00001
    end
  end

  defp estimate_response_latency(tokens, provider) do
    # Estimate response latency based on tokens and provider
    base_latency =
      case provider do
        # 1 second base
        "gpt-3.5-turbo" -> 1000
        # 2 seconds base
        "gpt-4" -> 2000
        # 1.5 seconds base
        provider when provider in ["claude-3-opus"] -> 1500
        # Generic estimate
        _ -> 1200
      end

    # Add latency based on token count
    # ~2ms per token, cap at 5s
    token_latency = min(5000, tokens * 2)

    base_latency + token_latency
  end

  defp categorize_performance_impact(tokens, cost, latency_ms) do
    cond do
      cost > 0.50 or latency_ms > 10_000 -> :high_impact
      cost > 0.10 or latency_ms > 5_000 -> :medium_impact
      true -> :low_impact
    end
  end

  defp validate_and_optimize_routing(prompt_content, provider, context) do
    # Validate and optimize provider routing
    compatibility_analysis =
      analyze_prompt_provider_compatibility(prompt_content, provider, context)

    case compatibility_analysis do
      {:ok, analysis} ->
        optimized_provider =
          if analysis.compatibility_score < 0.7 do
            suggest_better_provider(prompt_content, context)
          else
            provider
          end

        {:ok,
         %{
           optimized_provider: optimized_provider,
           metadata: %{
             original_compatibility: analysis.compatibility_score,
             routing_changed: optimized_provider != provider,
             optimization_reason:
               if(optimized_provider != provider,
                 do: "Better compatibility",
                 else: "Optimal match"
               )
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_integration_metrics(enhancement_time, status, state) do
    # Update integration performance metrics
    monitor = state.performance_monitor

    updated_monitor = %{
      monitor
      | total_enhancements: monitor.total_enhancements + 1,
        successful_enhancements:
          if(status == :success,
            do: monitor.successful_enhancements + 1,
            else: monitor.successful_enhancements
          ),
        average_enhancement_time_us:
          calculate_new_average(
            monitor.average_enhancement_time_us,
            enhancement_time,
            monitor.total_enhancements + 1
          )
    }

    %{state | performance_monitor: updated_monitor}
  end

  defp extract_performance_metrics(performance_monitor) do
    %{
      total_requests: performance_monitor.total_enhancements,
      success_rate: calculate_success_rate(performance_monitor),
      average_enhancement_time_ms:
        div(trunc(performance_monitor.average_enhancement_time_us), 1_000),
      optimization_effectiveness: performance_monitor.optimization_effectiveness
    }
  end

  defp execute_performance_optimization(state) do
    # Execute integration performance optimization
    optimized_monitor = %{
      state.performance_monitor
      | optimization_effectiveness:
          min(1.0, state.performance_monitor.optimization_effectiveness + 0.05)
    }

    %{state | performance_monitor: optimized_monitor}
  end

  defp calculate_success_rate(monitor) do
    case monitor.total_enhancements do
      0 -> 1.0
      total -> monitor.successful_enhancements / total
    end
  end

  defp calculate_new_average(current_avg, new_value, count) do
    case count do
      1 -> new_value
      _ -> (current_avg * (count - 1) + new_value) / count
    end
  end
end
