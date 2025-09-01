defmodule RubberDuck.Prompts.Composition.CompositionEngine do
  @moduledoc """
  Core prompt composition engine with hierarchical resolution and deterministic ordering.

  Orchestrates three-tier prompt composition (System → Project → User) with inheritance
  patterns, variable interpolation, and template-based composition strategies.
  Provides the foundation for sophisticated prompt management with security and performance.

  Features:
  - Three-tier hierarchical prompt resolution with deterministic System → Project → User composition order
  - Variable interpolation with comprehensive security validation and prompt injection prevention  
  - Template-based composition strategies with pattern recognition and inheritance support
  - Performance optimization with intelligent caching and sub-50ms resolution targets
  - Integration with existing LLM orchestration and RAG systems for seamless prompt enhancement
  - Comprehensive error handling with fallback strategies and graceful degradation

  Composition Process:
  1. **Resolution**: Hierarchical lookup of System, Project, and User prompts with caching optimization
  2. **Composition**: Deterministic composition with inheritance patterns and override capabilities
  3. **Interpolation**: Secure variable substitution with context awareness and validation
  4. **Optimization**: Token optimization and compression with model-specific strategies
  5. **Validation**: Security validation with prompt injection prevention and content sanitization
  """

  require Logger

  alias RubberDuck.Prompts.{
    Composition.PromptResolver,
    Composition.TokenOptimizer,
    Composition.VariableInterpolator,
    Resources.Prompt
  }

  @composition_strategies [
    :hierarchical_merge,
    :priority_override,
    :template_inheritance,
    :adaptive_composition
  ]

  @default_composition_options %{
    strategy: :hierarchical_merge,
    include_metadata: false,
    enable_caching: true,
    validate_security: true,
    optimize_tokens: false,
    fallback_to_system: true,
    performance_tracking: true
  }

  def compose_prompt(prompt_name, context, options \\ %{}) do
    merged_options = Map.merge(@default_composition_options, options)

    Logger.debug("CompositionEngine: Starting prompt composition",
      prompt_name: prompt_name,
      strategy: merged_options.strategy,
      tenant_id: Map.get(context, :tenant_id),
      user_id: Map.get(context, :user_id)
    )

    composition_start_time = System.monotonic_time(:microsecond)

    with {:ok, resolved_prompts} <-
           resolve_hierarchical_prompts(prompt_name, context, merged_options),
         {:ok, composed_content} <-
           execute_composition_strategy(resolved_prompts, merged_options),
         {:ok, interpolated_content} <-
           interpolate_variables(composed_content, context, merged_options),
         {:ok, optimized_content} <- optimize_composition(interpolated_content, merged_options),
         {:ok, validated_content} <-
           validate_composition_security(optimized_content, merged_options) do
      composition_time = System.monotonic_time(:microsecond) - composition_start_time

      Logger.info("CompositionEngine: Prompt composition completed successfully",
        prompt_name: prompt_name,
        composition_time_us: composition_time,
        final_length: String.length(validated_content),
        strategy: merged_options.strategy
      )

      {:ok,
       %{
         content: validated_content,
         composition_metadata: %{
           composition_time_microseconds: composition_time,
           resolved_prompts: length(resolved_prompts),
           strategy_used: merged_options.strategy,
           interpolated_variables: count_interpolated_variables(interpolated_content),
           final_token_count: estimate_token_count(validated_content),
           security_validated: merged_options.validate_security
         }
       }}
    else
      {:error, reason} ->
        Logger.error("CompositionEngine: Prompt composition failed",
          prompt_name: prompt_name,
          error: reason
        )

        case attempt_fallback_composition(prompt_name, context, merged_options, reason) do
          {:ok, fallback_result} ->
            {:ok, Map.put(fallback_result, :fallback_used, true)}

          {:error, fallback_error} ->
            {:error, {:composition_failed, reason, fallback_error}}
        end
    end
  end

  def compose_prompts_batch(prompt_requests, context, options \\ %{}) do
    merged_options = Map.merge(@default_composition_options, options)

    Logger.info("CompositionEngine: Starting batch prompt composition",
      batch_size: length(prompt_requests),
      strategy: merged_options.strategy
    )

    batch_start_time = System.monotonic_time(:microsecond)

    results =
      Enum.map(prompt_requests, fn %{name: name, variables: variables} ->
        request_context = Map.merge(context, %{variables: variables})

        case compose_prompt(name, request_context, merged_options) do
          {:ok, result} -> {:ok, {name, result}}
          {:error, reason} -> {:error, {name, reason}}
        end
      end)

    batch_time = System.monotonic_time(:microsecond) - batch_start_time

    {successes, failures} = separate_results(results)

    Logger.info("CompositionEngine: Batch composition completed",
      total_requests: length(prompt_requests),
      successful: length(successes),
      failed: length(failures),
      batch_time_us: batch_time
    )

    {:ok,
     %{
       successes: successes,
       failures: failures,
       batch_metadata: %{
         batch_time_microseconds: batch_time,
         success_rate: length(successes) / length(prompt_requests),
         average_composition_time: calculate_average_composition_time(successes)
       }
     }}
  end

  # Private implementation functions

  defp resolve_hierarchical_prompts(prompt_name, context, options) do
    case PromptResolver.resolve_hierarchy(prompt_name, context, options) do
      {:ok, prompts} -> {:ok, prompts}
      {:error, reason} -> {:error, {:resolution_failed, reason}}
    end
  end

  defp execute_composition_strategy(resolved_prompts, options) do
    case options.strategy do
      :hierarchical_merge ->
        execute_hierarchical_merge(resolved_prompts)

      :priority_override ->
        execute_priority_override(resolved_prompts)

      :template_inheritance ->
        execute_template_inheritance(resolved_prompts)

      :adaptive_composition ->
        execute_adaptive_composition(resolved_prompts, options)
    end
  end

  defp execute_hierarchical_merge(resolved_prompts) do
    # Compose prompts by merging in hierarchical order: System → Project → User
    base_content = ""

    composed_content =
      resolved_prompts
      |> Enum.sort_by(fn prompt -> prompt.priority end, :desc)
      |> Enum.reduce(base_content, fn prompt, acc_content ->
        merge_prompt_content(acc_content, prompt.content, :append)
      end)

    {:ok, composed_content}
  end

  defp execute_priority_override(resolved_prompts) do
    # Use highest priority prompt as base, override with lower priority specific sections
    case Enum.sort_by(resolved_prompts, fn prompt -> prompt.priority end, :desc) do
      [] ->
        {:error, :no_prompts_to_compose}

      [highest_priority | rest] ->
        base_content = highest_priority.content

        overridden_content =
          Enum.reduce(rest, base_content, fn prompt, acc_content ->
            apply_priority_overrides(acc_content, prompt.content)
          end)

        {:ok, overridden_content}
    end
  end

  defp execute_template_inheritance(resolved_prompts) do
    # Use template inheritance patterns with parent-child relationships
    case build_inheritance_chain(resolved_prompts) do
      {:ok, inheritance_chain} ->
        composed_content = apply_template_inheritance(inheritance_chain)
        {:ok, composed_content}

      {:error, reason} ->
        {:error, {:inheritance_failed, reason}}
    end
  end

  defp execute_adaptive_composition(resolved_prompts, options) do
    # Adaptively choose composition strategy based on prompt characteristics
    strategy = determine_optimal_strategy(resolved_prompts, options)

    case strategy do
      :hierarchical_merge -> execute_hierarchical_merge(resolved_prompts)
      :priority_override -> execute_priority_override(resolved_prompts)
      :template_inheritance -> execute_template_inheritance(resolved_prompts)
    end
  end

  defp interpolate_variables(content, context, options) do
    if Map.get(context, :variables) do
      case VariableInterpolator.interpolate(content, context.variables, context, options) do
        {:ok, interpolated} -> {:ok, interpolated}
        {:error, reason} -> {:error, {:interpolation_failed, reason}}
      end
    else
      {:ok, content}
    end
  end

  defp optimize_composition(content, options) do
    if options.optimize_tokens do
      case TokenOptimizer.optimize(content, options) do
        {:ok, optimized} -> {:ok, optimized}
        {:error, reason} -> {:error, {:optimization_failed, reason}}
      end
    else
      {:ok, content}
    end
  end

  defp validate_composition_security(content, options) do
    if options.validate_security do
      case validate_composed_content_security(content) do
        :ok -> {:ok, content}
        {:error, reason} -> {:error, {:security_validation_failed, reason}}
      end
    else
      {:ok, content}
    end
  end

  defp attempt_fallback_composition(prompt_name, context, options, _original_error) do
    if options.fallback_to_system do
      Logger.info("CompositionEngine: Attempting system prompt fallback",
        prompt_name: prompt_name
      )

      # Try to get system prompt as fallback
      system_context = Map.merge(context, %{prompt_type: :system})

      case PromptResolver.resolve_system_prompt(prompt_name, system_context) do
        {:ok, system_prompt} ->
          process_system_fallback(system_prompt, context, options)

        {:error, reason} ->
          {:error, {:system_fallback_failed, reason}}
      end
    else
      {:error, :fallback_disabled}
    end
  end

  # Composition strategy implementations

  defp merge_prompt_content(base_content, new_content, merge_type) do
    case merge_type do
      :append -> base_content <> "\n\n" <> new_content
      :prepend -> new_content <> "\n\n" <> base_content
      :replace -> new_content
    end
  end

  defp apply_priority_overrides(base_content, override_content) do
    # Simple override strategy - would implement sophisticated override logic
    case String.contains?(override_content, "{{override}}") do
      true -> String.replace(base_content, "{{instruction}}", override_content)
      false -> base_content <> "\n\nAdditional context: " <> override_content
    end
  end

  defp build_inheritance_chain(resolved_prompts) do
    # Build inheritance chain based on parent-child relationships
    prompts_by_id = Map.new(resolved_prompts, fn prompt -> {prompt.id, prompt} end)

    inheritance_chain =
      resolved_prompts
      |> Enum.filter(fn prompt -> is_nil(prompt.parent_id) end)
      |> Enum.map(fn root_prompt -> build_chain_from_root(root_prompt, prompts_by_id) end)
      |> List.flatten()

    {:ok, inheritance_chain}
  end

  defp build_chain_from_root(prompt, prompts_by_id) do
    children =
      prompts_by_id
      |> Map.values()
      |> Enum.filter(fn p -> p.parent_id == prompt.id end)

    case children do
      [] ->
        [prompt]

      _ ->
        [
          prompt
          | Enum.flat_map(children, fn child -> build_chain_from_root(child, prompts_by_id) end)
        ]
    end
  end

  defp apply_template_inheritance(inheritance_chain) do
    # Apply template inheritance with proper override handling
    inheritance_chain
    |> Enum.reduce("", fn prompt, acc_content ->
      merge_with_inheritance(acc_content, prompt.content)
    end)
  end

  defp merge_with_inheritance(base_content, child_content) do
    # Merge content with template inheritance patterns
    case base_content do
      "" -> child_content
      _ -> base_content <> "\n\n" <> child_content
    end
  end

  defp determine_optimal_strategy(resolved_prompts, _options) do
    # Determine optimal composition strategy based on prompt characteristics
    prompt_types = Enum.map(resolved_prompts, fn p -> p.prompt_type end)

    cond do
      :template in Enum.map(resolved_prompts, fn p -> Map.get(p, :is_template, false) end) ->
        :template_inheritance

      length(Enum.uniq(prompt_types)) > 2 ->
        :hierarchical_merge

      true ->
        :priority_override
    end
  end

  # Security and validation functions

  defp validate_composed_content_security(content) do
    # Basic security validation - would integrate with comprehensive security system
    dangerous_patterns = [
      ~r/\{\{.*system.*\}\}/i,
      ~r/\{\{.*exec.*\}\}/i,
      ~r/\{\{.*eval.*\}\}/i,
      ~r/<script/i,
      ~r/javascript:/i,
      ~r/data:.*base64/i
    ]

    dangerous_found =
      Enum.any?(dangerous_patterns, fn pattern ->
        Regex.match?(pattern, content)
      end)

    if dangerous_found do
      {:error, :dangerous_content_detected}
    else
      :ok
    end
  end

  defp process_system_fallback(system_prompt, context, options) do
    case interpolate_variables(system_prompt.content, context, options) do
      {:ok, interpolated} ->
        {:ok,
         %{
           content: interpolated,
           composition_metadata: %{
             fallback_used: true,
             fallback_type: :system_prompt,
             original_strategy: options.strategy
           }
         }}

      {:error, reason} ->
        {:error, {:fallback_interpolation_failed, reason}}
    end
  end

  # Utility functions

  defp separate_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, success}, {successes, failures} -> {[success | successes], failures}
      {:error, error}, {successes, failures} -> {successes, [error | failures]}
    end)
  end

  defp calculate_average_composition_time(successes) do
    case successes do
      [] ->
        0.0

      _ ->
        total_time =
          successes
          |> Enum.map(fn {_name, result} ->
            result.composition_metadata.composition_time_microseconds
          end)
          |> Enum.sum()

        Float.round(total_time / length(successes), 2)
    end
  end

  defp count_interpolated_variables(content) do
    # Count successfully interpolated variables (no {{ }} remaining)
    original_variables = Regex.scan(~r/\{\{([^}]+)\}\}/, content)
    length(original_variables)
  end

  defp estimate_token_count(content) do
    # Rough token estimation - would integrate with proper tokenization
    words = String.split(content, ~r/\s+/)
    # Rough estimate: 1 token per 0.75 words for English text
    round(length(words) / 0.75)
  end
end
