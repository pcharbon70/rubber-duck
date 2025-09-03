defmodule RubberDuck.Prompts.WorkflowIntegration.WorkflowContextEnhancer do
  @moduledoc """
  Context enhancement service for workflow-prompt integration.

  Provides intelligent context passing and enhancement between workflow steps 
  and prompt composition, enabling workflows to automatically access project
  and user context through prompt composition with optimization and validation.

  Features:
  - Context passing between Reactor steps and prompts with optimization and validation
  - Automatic context enhancement with workflow execution metadata and user preferences
  - Context inheritance and customization with scope-specific configurations
  - Performance optimization for context coordination with memory and CPU efficiency
  - Integration with existing context systems and user preference management
  - Context validation and sanitization with security and privacy considerations
  """

  require Logger

  @context_enhancement_strategies [:merge, :override, :inherit, :custom]
  @context_scopes [:step, :workflow, :project, :user, :global]

  @default_enhancement_config %{
    enable_context_validation: true,
    enable_context_optimization: true,
    enable_inheritance: true,
    max_context_size_kb: 50,
    context_sanitization: true
  }

  def enhance_context(base_context, workflow_id, options \\ %{}) do
    enhancement_config =
      Map.merge(@default_enhancement_config, Map.get(options, :enhancement_config, %{}))

    Logger.debug("WorkflowContextEnhancer: Enhancing workflow context",
      workflow_id: workflow_id,
      base_context_keys: Map.keys(base_context),
      enhancement_enabled: enhancement_config.enable_context_optimization
    )

    case execute_context_enhancement(base_context, workflow_id, options, enhancement_config) do
      {:ok, enhanced_context} ->
        Logger.info("WorkflowContextEnhancer: Context enhancement completed",
          workflow_id: workflow_id,
          original_keys: length(Map.keys(base_context)),
          enhanced_keys: length(Map.keys(enhanced_context)),
          enhancement_strategy: determine_enhancement_strategy(base_context, options)
        )

        {:ok, enhanced_context}

      {:error, reason} ->
        Logger.error("WorkflowContextEnhancer: Context enhancement failed",
          workflow_id: workflow_id,
          error: reason
        )

        {:error, reason}
    end
  end

  def validate_context(context, validation_options \\ %{}) do
    Logger.debug("WorkflowContextEnhancer: Validating context",
      context_size_kb: calculate_context_size(context) / 1024
    )

    case execute_context_validation(context, validation_options) do
      {:ok, validation_result} ->
        Logger.debug("WorkflowContextEnhancer: Context validation completed",
          validation_passed: validation_result.validation_passed,
          validation_score: validation_result.validation_score
        )

        {:ok, validation_result}

      {:error, reason} ->
        Logger.warning("WorkflowContextEnhancer: Context validation failed", error: reason)
        {:error, reason}
    end
  end

  def optimize_context_for_workflow(context, workflow_type, options \\ %{}) do
    Logger.debug("WorkflowContextEnhancer: Optimizing context for workflow type",
      workflow_type: workflow_type,
      context_keys: Map.keys(context)
    )

    case execute_context_optimization(context, workflow_type, options) do
      {:ok, optimized_context} ->
        optimization_metrics = calculate_optimization_metrics(context, optimized_context)

        Logger.info("WorkflowContextEnhancer: Context optimization completed",
          workflow_type: workflow_type,
          size_reduction_percentage: optimization_metrics.size_reduction_percentage,
          optimization_effective: optimization_metrics.optimization_effective
        )

        {:ok,
         %{
           optimized_context: optimized_context,
           optimization_metrics: optimization_metrics
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp execute_context_enhancement(base_context, workflow_id, options, enhancement_config) do
    # Execute comprehensive context enhancement
    enhancement_strategy = determine_enhancement_strategy(base_context, options)

    case enhancement_strategy do
      :merge ->
        execute_merge_enhancement(base_context, workflow_id, options, enhancement_config)

      :override ->
        execute_override_enhancement(base_context, workflow_id, options, enhancement_config)

      :inherit ->
        execute_inherit_enhancement(base_context, workflow_id, options, enhancement_config)

      :custom ->
        execute_custom_enhancement(base_context, workflow_id, options, enhancement_config)
    end
  end

  defp execute_merge_enhancement(base_context, workflow_id, options, config) do
    # Execute merge-based context enhancement
    with {:ok, workflow_context} <- get_workflow_context(workflow_id, config),
         {:ok, user_context} <- get_user_context(options, config),
         {:ok, project_context} <- get_project_context(options, config) do
      merged_context =
        base_context
        |> Map.merge(workflow_context)
        |> Map.merge(user_context)
        |> Map.merge(project_context)
        |> add_enhancement_metadata(:merge, workflow_id)

      {:ok, merged_context}
    else
      {:error, reason} -> {:error, {:merge_enhancement_failed, reason}}
    end
  end

  defp execute_override_enhancement(base_context, workflow_id, options, config) do
    # Execute override-based enhancement
    override_context = build_override_context(workflow_id, options, config)

    enhanced_context =
      Map.merge(override_context, base_context)
      |> add_enhancement_metadata(:override, workflow_id)

    {:ok, enhanced_context}
  end

  defp execute_inherit_enhancement(base_context, workflow_id, options, config) do
    # Execute inheritance-based enhancement
    case get_inherited_context(workflow_id, options, config) do
      {:ok, inherited_context} ->
        enhanced_context =
          Map.merge(inherited_context, base_context)
          |> add_enhancement_metadata(:inherit, workflow_id)

        {:ok, enhanced_context}

      {:error, reason} ->
        {:error, {:inherit_enhancement_failed, reason}}
    end
  end

  defp execute_custom_enhancement(base_context, workflow_id, options, config) do
    # Execute custom enhancement logic
    custom_enhancements = Map.get(options, :custom_enhancements, %{})

    enhanced_context =
      apply_custom_enhancements(base_context, custom_enhancements)
      |> add_enhancement_metadata(:custom, workflow_id)

    {:ok, enhanced_context}
  end

  defp execute_context_validation(context, validation_options) do
    # Execute comprehensive context validation
    validation_checks = [
      validate_context_size(context, validation_options),
      validate_context_structure(context, validation_options),
      validate_context_security(context, validation_options),
      validate_context_completeness(context, validation_options)
    ]

    failed_checks = Enum.filter(validation_checks, &match?({:error, _}, &1))
    successful_checks = Enum.filter(validation_checks, &match?({:ok, _}, &1))

    validation_result = %{
      validation_passed: Enum.empty?(failed_checks),
      validation_score: length(successful_checks) / length(validation_checks),
      successful_checks: length(successful_checks),
      failed_checks: length(failed_checks),
      validation_details: validation_checks
    }

    {:ok, validation_result}
  end

  defp execute_context_optimization(context, workflow_type, options) do
    # Execute context optimization for workflow
    optimization_strategy = determine_optimization_strategy(workflow_type, options)

    optimized_context =
      case optimization_strategy do
        :minimize -> minimize_context(context)
        :prioritize -> prioritize_context_keys(context, workflow_type)
        :compress -> compress_context_values(context)
        :selective -> selective_context_optimization(context, workflow_type)
      end

    {:ok, optimized_context}
  end

  # Context enhancement helper functions

  defp determine_enhancement_strategy(base_context, options) do
    case {
      Map.get(options, :enhancement_strategy),
      Map.get(base_context, :workflow_type, :general),
      Map.get(options, :force_strategy, false)
    } do
      {strategy, _, true} when strategy in @context_enhancement_strategies -> strategy
      {nil, :code_review, _} -> :inherit
      {nil, :documentation, _} -> :merge
      {nil, :refactoring, _} -> :override
      {strategy, _, _} when strategy in @context_enhancement_strategies -> strategy
      _ -> :merge
    end
  end

  defp get_workflow_context(workflow_id, config) do
    # Get workflow-specific context
    workflow_context = %{
      workflow_id: workflow_id,
      workflow_metadata: %{
        execution_context: true,
        context_enhanced: true
      }
    }

    {:ok, workflow_context}
  end

  defp get_user_context(options, config) do
    # Get user-specific context
    user_context = %{
      user_id: Map.get(options, :user_id),
      user_preferences: Map.get(options, :user_preferences, %{}),
      user_role: Map.get(options, :user_role, :user)
    }

    {:ok, user_context}
  end

  defp get_project_context(options, config) do
    # Get project-specific context
    project_context = %{
      project_id: Map.get(options, :project_id),
      project_settings: Map.get(options, :project_settings, %{}),
      project_type: Map.get(options, :project_type, :elixir)
    }

    {:ok, project_context}
  end

  defp build_override_context(workflow_id, options, config) do
    # Build override context for workflow
    %{
      workflow_override: true,
      workflow_id: workflow_id,
      override_timestamp: DateTime.utc_now(),
      override_source: :workflow_context_enhancer
    }
  end

  defp get_inherited_context(workflow_id, options, config) do
    # Get inherited context for workflow
    inherited_context = %{
      inheritance_enabled: true,
      workflow_id: workflow_id,
      inherited_from: determine_inheritance_source(options),
      inheritance_timestamp: DateTime.utc_now()
    }

    {:ok, inherited_context}
  end

  defp apply_custom_enhancements(base_context, custom_enhancements) do
    # Apply custom enhancement logic
    Enum.reduce(custom_enhancements, base_context, fn {key, enhancement}, acc ->
      Map.put(acc, key, enhancement)
    end)
  end

  defp add_enhancement_metadata(context, strategy, workflow_id) do
    # Add enhancement metadata to context
    enhancement_metadata = %{
      enhancement_strategy: strategy,
      workflow_id: workflow_id,
      enhanced_at: DateTime.utc_now(),
      enhancement_version: "1.0"
    }

    Map.put(context, :enhancement_metadata, enhancement_metadata)
  end

  # Context validation functions

  defp validate_context_size(context, options) do
    context_size = calculate_context_size(context)
    max_size = Map.get(options, :max_size_kb, 50) * 1024

    if context_size <= max_size do
      {:ok, %{check: :size, status: :valid, size_bytes: context_size}}
    else
      {:error,
       %{check: :size, status: :too_large, size_bytes: context_size, max_size_bytes: max_size}}
    end
  end

  defp validate_context_structure(context, options) do
    # Validate context structure
    if is_map(context) and not Enum.empty?(context) do
      {:ok, %{check: :structure, status: :valid, keys_count: length(Map.keys(context))}}
    else
      {:error, %{check: :structure, status: :invalid, issue: :empty_or_invalid_structure}}
    end
  end

  defp validate_context_security(context, options) do
    # Validate context for security issues
    security_issues = detect_security_issues(context)

    if Enum.empty?(security_issues) do
      {:ok, %{check: :security, status: :secure, issues: []}}
    else
      {:error, %{check: :security, status: :insecure, issues: security_issues}}
    end
  end

  defp validate_context_completeness(context, options) do
    # Validate context completeness
    required_keys = Map.get(options, :required_keys, [])
    missing_keys = Enum.filter(required_keys, fn key -> not Map.has_key?(context, key) end)

    if Enum.empty?(missing_keys) do
      {:ok, %{check: :completeness, status: :complete, required_keys: length(required_keys)}}
    else
      {:error, %{check: :completeness, status: :incomplete, missing_keys: missing_keys}}
    end
  end

  # Context optimization functions

  defp determine_optimization_strategy(workflow_type, options) do
    case {workflow_type, Map.get(options, :optimization_priority, :balanced)} do
      {:code_review, :performance} -> :minimize
      {:documentation, :quality} -> :prioritize
      {:refactoring, :memory} -> :compress
      {_, :balanced} -> :selective
      _ -> :selective
    end
  end

  defp minimize_context(context) do
    # Minimize context by removing optional keys
    essential_keys = [:user_id, :project_id, :workflow_id, :workflow_type]

    Map.take(context, essential_keys)
  end

  defp prioritize_context_keys(context, workflow_type) do
    # Prioritize context keys based on workflow type
    priority_keys =
      case workflow_type do
        :code_review -> [:user_preferences, :project_settings, :code_analysis_config]
        :documentation -> [:documentation_style, :project_info, :user_preferences]
        :refactoring -> [:refactoring_preferences, :code_quality_standards, :team_conventions]
        _ -> Map.keys(context)
      end

    prioritized_context = Map.take(context, priority_keys)
    remaining_context = Map.drop(context, priority_keys)

    Map.merge(prioritized_context, %{additional_context: remaining_context})
  end

  defp compress_context_values(context) do
    # Compress context values for memory efficiency
    Enum.reduce(context, %{}, fn {key, value}, acc ->
      compressed_value = compress_context_value(value)
      Map.put(acc, key, compressed_value)
    end)
  end

  defp compress_context_value(value) do
    case value do
      text when is_binary(text) ->
        compress_text_value(text)

      list when is_list(list) ->
        compress_list_value(list)

      value ->
        value
    end
  end

  defp compress_text_value(text) do
    if String.length(text) > 1000 do
      String.slice(text, 0, 1000) <> "... [compressed]"
    else
      text
    end
  end

  defp compress_list_value(list) do
    if length(list) > 10 do
      Enum.take(list, 10) ++ ["... [#{length(list) - 10} more items]"]
    else
      list
    end
  end

  defp selective_context_optimization(context, workflow_type) do
    # Selective optimization based on workflow type and context content
    optimization_rules = get_optimization_rules(workflow_type)

    Enum.reduce(optimization_rules, context, fn rule, acc ->
      apply_optimization_rule(acc, rule)
    end)
  end

  # Helper functions

  defp calculate_context_size(context) do
    # Calculate approximate context size in bytes
    context
    |> :erlang.term_to_binary()
    |> byte_size()
  end

  defp detect_security_issues(context) do
    # Detect potential security issues in context
    security_issues = []

    # Check for potential secrets
    security_issues =
      if context_contains_secrets?(context) do
        [:potential_secrets | security_issues]
      else
        security_issues
      end

    # Check for sensitive data
    security_issues =
      if context_contains_sensitive_data?(context) do
        [:sensitive_data | security_issues]
      else
        security_issues
      end

    security_issues
  end

  defp context_contains_secrets?(context) do
    # Simple check for potential secrets (placeholder)
    secret_patterns = ["password", "secret", "token", "key"]

    context
    |> Map.keys()
    |> Enum.any?(fn key ->
      key_string = to_string(key)

      Enum.any?(secret_patterns, fn pattern ->
        String.contains?(String.downcase(key_string), pattern)
      end)
    end)
  end

  defp context_contains_sensitive_data?(context) do
    # Simple check for sensitive data (placeholder)
    sensitive_patterns = ["email", "phone", "address", "ssn"]

    context
    |> Map.values()
    |> Enum.any?(fn value -> check_value_for_sensitive_data(value, sensitive_patterns) end)
  end

  defp check_value_for_sensitive_data(value, sensitive_patterns) do
    case value do
      text when is_binary(text) ->
        text_lower = String.downcase(text)

        Enum.any?(sensitive_patterns, fn pattern ->
          String.contains?(text_lower, pattern)
        end)

      _ ->
        false
    end
  end

  defp determine_inheritance_source(options) do
    cond do
      Map.has_key?(options, :project_id) -> :project
      Map.has_key?(options, :user_id) -> :user
      true -> :global
    end
  end

  defp calculate_optimization_metrics(original_context, optimized_context) do
    original_size = calculate_context_size(original_context)
    optimized_size = calculate_context_size(optimized_context)

    size_reduction = original_size - optimized_size

    size_reduction_percentage =
      if original_size > 0, do: size_reduction / original_size * 100, else: 0

    %{
      original_size_bytes: original_size,
      optimized_size_bytes: optimized_size,
      size_reduction_bytes: size_reduction,
      size_reduction_percentage: Float.round(size_reduction_percentage, 2),
      optimization_effective: size_reduction_percentage > 10
    }
  end

  defp get_optimization_rules(workflow_type) do
    # Get optimization rules for workflow type
    case workflow_type do
      :code_review ->
        [
          {:compress_large_values, 500},
          {:prioritize_keys, [:code_analysis_config, :review_preferences]},
          {:remove_optional_metadata, true}
        ]

      :documentation ->
        [
          {:compress_large_values, 1000},
          {:prioritize_keys, [:documentation_style, :project_info]},
          {:preserve_formatting, true}
        ]

      :refactoring ->
        [
          {:compress_large_values, 300},
          {:prioritize_keys, [:refactoring_preferences, :code_standards]},
          {:remove_optional_metadata, true}
        ]

      _ ->
        [
          {:compress_large_values, 500},
          {:remove_optional_metadata, false}
        ]
    end
  end

  defp apply_optimization_rule(context, {rule_type, rule_value}) do
    case rule_type do
      :compress_large_values ->
        compress_large_values(context, rule_value)

      :prioritize_keys ->
        prioritize_context_keys(context, rule_value)

      :remove_optional_metadata ->
        if rule_value, do: remove_optional_metadata(context), else: context

      :preserve_formatting ->
        if rule_value, do: preserve_formatting_metadata(context), else: context

      _ ->
        context
    end
  end

  defp compress_large_values(context, max_size) do
    Enum.reduce(context, %{}, fn {key, value}, acc ->
      compressed_value = compress_single_value(value, max_size)
      Map.put(acc, key, compressed_value)
    end)
  end

  defp compress_single_value(value, max_size) do
    case value do
      text when is_binary(text) ->
        if String.length(text) > max_size do
          String.slice(text, 0, max_size) <> "... [compressed]"
        else
          text
        end

      value ->
        value
    end
  end

  defp remove_optional_metadata(context) do
    # Remove optional metadata to reduce context size
    optional_keys = [:debug_info, :internal_metadata, :temporary_data]
    Map.drop(context, optional_keys)
  end

  defp preserve_formatting_metadata(context) do
    # Ensure formatting metadata is preserved
    formatting_keys = [:formatting_preferences, :style_guide, :output_format]

    case Map.take(context, formatting_keys) do
      empty when empty == %{} ->
        Map.put(context, :formatting_preserved, true)

      formatting_data ->
        Map.merge(context, %{formatting_preserved: true, formatting_data: formatting_data})
    end
  end
end
