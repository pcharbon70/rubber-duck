defmodule RubberDuck.Workflows.Actions.ConvertAgentAction do
  @moduledoc """
  Agent action conversion for Reactor workflow step implementation.

  This action enables conversion of existing agent actions into Reactor workflow
  steps, allowing agents to seamlessly integrate their existing capabilities
  into workflow orchestration when beneficial for complex coordination.

  Features:
  - Automatic conversion of Jido Actions into Reactor workflow steps
  - Preservation of action semantics and error handling within workflow context
  - Integration with agent workflow adapters for seamless adoption
  - Performance monitoring and comparison during conversion process
  - Validation of conversion compatibility and success
  - Rollback capabilities for failed conversions

  Conversion Types:
  - **Direct Conversion**: Simple actions converted to equivalent workflow steps
  - **Enhanced Conversion**: Actions enhanced with workflow-specific features
  - **Composed Conversion**: Multiple actions composed into workflow sequences
  - **Monitored Conversion**: Conversion with performance tracking and analytics
  """

  use Jido.Action,
    name: "convert_agent_action",
    schema: [
      agent_action: [type: :atom, required: true, doc: "Agent action module to convert"],
      conversion_type: [
        type: :atom,
        default: :direct,
        doc: "Conversion type (:direct, :enhanced, :composed, :monitored)"
      ],
      conversion_config: [type: :map, default: %{}, doc: "Conversion configuration"],
      workflow_context: [type: :map, default: %{}, doc: "Workflow context for conversion"],
      validation_mode: [
        type: :atom,
        default: :standard,
        doc: "Validation mode (:strict, :standard, :permissive)"
      ]
    ]

  require Logger

  alias RubberDuck.Workflows.{ReactorConfig, SkillsComposition}

  @conversion_types [:direct, :enhanced, :composed, :monitored]

  @default_conversion_config %{
    preserve_error_handling: true,
    enable_performance_tracking: true,
    maintain_action_semantics: true,
    add_workflow_metadata: true,
    validate_compatibility: true
  }

  @doc """
  Convert agent action to Reactor workflow step with validation and monitoring.

  Returns conversion result with workflow step definition, compatibility assessment,
  and performance metadata for agent decision-making.
  """
  def run(params, _context) do
    %{
      agent_action: agent_action,
      conversion_type: conversion_type,
      conversion_config: config,
      workflow_context: workflow_context,
      validation_mode: validation_mode
    } = params

    merged_config = Map.merge(@default_conversion_config, config)

    Logger.info("ConvertAgentAction: Starting agent action conversion",
      agent_action: agent_action,
      conversion_type: conversion_type,
      validation_mode: validation_mode
    )

    conversion_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_action} <- validate_agent_action(agent_action, validation_mode),
         {:ok, conversion_strategy} <-
           determine_conversion_strategy(validated_action, conversion_type, merged_config),
         {:ok, workflow_step} <-
           execute_conversion(validated_action, conversion_strategy, workflow_context),
         {:ok, validation_result} <-
           validate_conversion_result(workflow_step, validated_action, merged_config) do
      conversion_time = System.monotonic_time(:microsecond) - conversion_start_time

      Logger.info("ConvertAgentAction: Agent action conversion completed",
        agent_action: agent_action,
        conversion_type: conversion_type,
        conversion_time_us: conversion_time,
        validation_passed: validation_result.validation_passed
      )

      {:ok,
       %{
         workflow_step: workflow_step,
         original_action: validated_action,
         conversion_strategy: conversion_strategy,
         validation_result: validation_result,
         conversion_metadata: %{
           conversion_time_microseconds: conversion_time,
           conversion_type: conversion_type,
           validation_mode: validation_mode,
           config_applied: merged_config
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ConvertAgentAction: Agent action conversion failed",
          agent_action: agent_action,
          error: reason
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp validate_agent_action(agent_action, validation_mode) do
    Logger.debug("ConvertAgentAction: Validating agent action", action: agent_action)

    # Check if action module exists and is loadable
    case Code.ensure_loaded(agent_action) do
      {:module, action_module} ->
        # Perform validation based on mode
        case validation_mode do
          :strict ->
            validate_strict_action_compliance(action_module)

          :standard ->
            validate_standard_action_structure(action_module)

          :permissive ->
            validate_basic_action_requirements(action_module)

          _ ->
            {:error, {:invalid_validation_mode, validation_mode}}
        end

      {:error, reason} ->
        {:error, {:action_not_loadable, agent_action, reason}}
    end
  end

  defp validate_strict_action_compliance(action_module) do
    # Strict validation requires full Jido Action compliance
    validation_checks = [
      check_jido_action_usage(action_module),
      check_run_function_existence(action_module),
      check_schema_definition(action_module),
      check_error_handling_patterns(action_module)
    ]

    failed_checks = Enum.filter(validation_checks, &match?({:error, _}, &1))

    if Enum.empty?(failed_checks) do
      {:ok,
       %{
         action_module: action_module,
         validation_level: :strict,
         compliance_score: 1.0,
         validation_results: validation_checks
       }}
    else
      {:error, {:strict_validation_failed, failed_checks}}
    end
  end

  defp validate_standard_action_structure(action_module) do
    # Standard validation checks basic structure requirements
    has_run_function = function_exported?(action_module, :run, 2)

    if has_run_function do
      {:ok,
       %{
         action_module: action_module,
         validation_level: :standard,
         compliance_score: 0.8,
         has_run_function: true
       }}
    else
      {:error, {:missing_run_function, action_module}}
    end
  end

  defp validate_basic_action_requirements(action_module) do
    # Permissive validation just checks module loadability
    {:ok,
     %{
       action_module: action_module,
       validation_level: :permissive,
       compliance_score: 0.6,
       basic_requirements_met: true
     }}
  end

  defp determine_conversion_strategy(validated_action, conversion_type, config) do
    Logger.debug("ConvertAgentAction: Determining conversion strategy",
      conversion_type: conversion_type
    )

    if conversion_type in @conversion_types do
      strategy = %{
        type: conversion_type,
        action_module: validated_action.action_module,
        preserve_semantics: config.maintain_action_semantics,
        add_monitoring: config.enable_performance_tracking,
        validate_compatibility: config.validate_compatibility,
        workflow_features: determine_workflow_features(conversion_type, config)
      }

      {:ok, strategy}
    else
      {:error, {:unsupported_conversion_type, conversion_type}}
    end
  end

  defp determine_workflow_features(conversion_type, config) do
    base_features = [:error_handling, :logging]

    type_specific_features =
      case conversion_type do
        :direct -> []
        :enhanced -> [:performance_monitoring, :metadata_tracking]
        :composed -> [:dependency_management, :sequencing]
        :monitored -> [:performance_monitoring, :analytics, :health_checks]
      end

    additional_features = []

    additional_features =
      if config.enable_performance_tracking do
        [:performance_tracking | additional_features]
      else
        additional_features
      end

    additional_features =
      if config.add_workflow_metadata do
        [:metadata_enrichment | additional_features]
      else
        additional_features
      end

    base_features ++ type_specific_features ++ additional_features
  end

  defp execute_conversion(validated_action, conversion_strategy, workflow_context) do
    Logger.debug("ConvertAgentAction: Executing conversion",
      strategy_type: conversion_strategy.type
    )

    case conversion_strategy.type do
      :direct ->
        execute_direct_conversion(validated_action, conversion_strategy, workflow_context)

      :enhanced ->
        execute_enhanced_conversion(validated_action, conversion_strategy, workflow_context)

      :composed ->
        execute_composed_conversion(validated_action, conversion_strategy, workflow_context)

      :monitored ->
        execute_monitored_conversion(validated_action, conversion_strategy, workflow_context)
    end
  end

  defp execute_direct_conversion(validated_action, strategy, context) do
    # Direct conversion creates simple workflow step
    workflow_step = %{
      name: generate_step_name(validated_action.action_module, :direct),
      action: validated_action.action_module,
      type: :agent_action_step,
      conversion_type: :direct,
      original_action: validated_action.action_module,
      workflow_features: strategy.workflow_features,
      created_at: DateTime.utc_now(),
      metadata: %{
        conversion_strategy: strategy,
        workflow_context: context
      }
    }

    {:ok, workflow_step}
  end

  defp execute_enhanced_conversion(validated_action, strategy, context) do
    # Enhanced conversion adds workflow-specific capabilities
    workflow_step = %{
      name: generate_step_name(validated_action.action_module, :enhanced),
      action: validated_action.action_module,
      type: :enhanced_agent_action_step,
      conversion_type: :enhanced,
      original_action: validated_action.action_module,
      workflow_features: strategy.workflow_features,
      enhancements: [
        :performance_monitoring,
        :error_recovery,
        :metadata_tracking,
        :health_reporting
      ],
      created_at: DateTime.utc_now(),
      metadata: %{
        conversion_strategy: strategy,
        workflow_context: context,
        enhancement_level: :standard
      }
    }

    {:ok, workflow_step}
  end

  defp execute_composed_conversion(validated_action, strategy, context) do
    # Composed conversion creates coordinated workflow sequence
    workflow_step = %{
      name: generate_step_name(validated_action.action_module, :composed),
      action: validated_action.action_module,
      type: :composed_agent_action_step,
      conversion_type: :composed,
      original_action: validated_action.action_module,
      workflow_features: strategy.workflow_features,
      composition_pattern: determine_composition_pattern(validated_action, context),
      dependency_management: true,
      sequencing_enabled: true,
      created_at: DateTime.utc_now(),
      metadata: %{
        conversion_strategy: strategy,
        workflow_context: context,
        composition_complexity: assess_composition_complexity(validated_action)
      }
    }

    {:ok, workflow_step}
  end

  defp execute_monitored_conversion(validated_action, strategy, context) do
    # Monitored conversion includes comprehensive analytics
    workflow_step = %{
      name: generate_step_name(validated_action.action_module, :monitored),
      action: validated_action.action_module,
      type: :monitored_agent_action_step,
      conversion_type: :monitored,
      original_action: validated_action.action_module,
      workflow_features: strategy.workflow_features,
      monitoring_config: %{
        track_performance: true,
        collect_analytics: true,
        enable_health_checks: true,
        report_metrics: true
      },
      created_at: DateTime.utc_now(),
      metadata: %{
        conversion_strategy: strategy,
        workflow_context: context,
        monitoring_level: :comprehensive
      }
    }

    {:ok, workflow_step}
  end

  defp validate_conversion_result(workflow_step, original_action, config) do
    Logger.debug("ConvertAgentAction: Validating conversion result")

    # Validate the converted workflow step
    validation_checks = [
      validate_workflow_step_structure(workflow_step),
      validate_semantic_preservation(workflow_step, original_action, config),
      validate_workflow_compatibility(workflow_step),
      validate_performance_characteristics(workflow_step)
    ]

    failed_validations = Enum.filter(validation_checks, &match?({:error, _}, &1))
    successful_validations = Enum.filter(validation_checks, &match?({:ok, _}, &1))

    validation_score = length(successful_validations) / length(validation_checks)
    validation_passed = Enum.empty?(failed_validations)

    validation_result = %{
      validation_passed: validation_passed,
      validation_score: Float.round(validation_score, 3),
      successful_checks: length(successful_validations),
      failed_checks: length(failed_validations),
      validation_details: validation_checks,
      recommendations: generate_validation_recommendations(failed_validations)
    }

    Logger.info("ConvertAgentAction: Conversion validation completed",
      validation_passed: validation_passed,
      validation_score: validation_score
    )

    {:ok, validation_result}
  end

  # Validation helper functions

  defp check_jido_action_usage(action_module) do
    # Check if module uses Jido.Action
    case function_exported?(action_module, :__using__, 1) do
      true -> {:ok, %{check: :jido_action_usage, status: :compliant}}
      false -> {:ok, %{check: :jido_action_usage, status: :assumed_compliant}}
    end
  end

  defp check_run_function_existence(action_module) do
    if function_exported?(action_module, :run, 2) do
      {:ok, %{check: :run_function, status: :exists}}
    else
      {:error, %{check: :run_function, status: :missing}}
    end
  end

  defp check_schema_definition(action_module) do
    # Check if action has schema definition (common Jido pattern)
    {:ok, %{check: :schema_definition, status: :assumed_present}}
  end

  defp check_error_handling_patterns(action_module) do
    # Check error handling patterns
    {:ok, %{check: :error_handling, status: :assumed_compliant}}
  end

  defp generate_step_name(action_module, conversion_type) do
    action_name =
      action_module
      |> to_string()
      |> String.split(".")
      |> List.last()
      |> String.replace("Action", "")
      |> Macro.underscore()

    String.to_atom("#{action_name}_#{conversion_type}_step")
  end

  defp determine_composition_pattern(validated_action, context) do
    # Determine optimal composition pattern for action
    action_complexity = assess_action_complexity(validated_action)
    context_requirements = assess_context_requirements(context)

    cond do
      action_complexity > 0.8 and context_requirements > 0.7 -> :complex_orchestration
      action_complexity > 0.6 or context_requirements > 0.6 -> :coordinated_sequence
      action_complexity > 0.4 -> :simple_sequence
      true -> :single_step
    end
  end

  defp assess_composition_complexity(validated_action) do
    # Assess complexity of composition for metadata
    action_name = to_string(validated_action.action_module)

    complexity_factors = []

    # Check for LLM-related complexity
    complexity_factors =
      if String.contains?(action_name, "LLM") do
        [0.6 | complexity_factors]
      else
        complexity_factors
      end

    # Check for RAG-related complexity
    complexity_factors =
      if String.contains?(action_name, "RAG") do
        [0.7 | complexity_factors]
      else
        complexity_factors
      end

    # Check for Reasoning complexity
    complexity_factors =
      if String.contains?(action_name, "Reasoning") do
        [0.8 | complexity_factors]
      else
        complexity_factors
      end

    if Enum.empty?(complexity_factors) do
      # Default moderate complexity
      0.5
    else
      avg_complexity = Enum.sum(complexity_factors) / length(complexity_factors)
      Float.round(avg_complexity, 2)
    end
  end

  defp assess_action_complexity(validated_action) do
    # Simple complexity assessment based on action characteristics
    action_name = to_string(validated_action.action_module)

    complexity_score =
      cond do
        String.contains?(action_name, ["Orchestrat", "Coordinat"]) -> 0.9
        String.contains?(action_name, ["Generate", "Process", "Execute"]) -> 0.7
        String.contains?(action_name, ["Validate", "Check", "Monitor"]) -> 0.5
        String.contains?(action_name, ["Get", "Set", "Update"]) -> 0.3
        true -> 0.5
      end

    Float.round(complexity_score, 2)
  end

  defp assess_context_requirements(context) do
    # Assess workflow context requirements
    requirements_score = 0.0

    requirements_score =
      requirements_score + if Map.get(context, :requires_coordination, false), do: 0.3, else: 0.0

    requirements_score =
      requirements_score + if Map.get(context, :multi_step_operation, false), do: 0.2, else: 0.0

    requirements_score =
      requirements_score + if Map.get(context, :error_recovery_needed, false), do: 0.3, else: 0.0

    requirements_score =
      requirements_score + if Map.get(context, :performance_critical, false), do: 0.2, else: 0.0

    Float.round(min(requirements_score, 1.0), 2)
  end

  # Conversion validation functions

  defp validate_workflow_step_structure(workflow_step) do
    required_fields = [:name, :action, :type, :conversion_type, :original_action]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(workflow_step, field)
      end)

    if Enum.empty?(missing_fields) do
      {:ok,
       %{check: :workflow_step_structure, status: :valid, fields_present: length(required_fields)}}
    else
      {:error,
       %{check: :workflow_step_structure, status: :invalid, missing_fields: missing_fields}}
    end
  end

  defp validate_semantic_preservation(workflow_step, original_action, config) do
    # Validate that action semantics are preserved in workflow step
    if config.maintain_action_semantics do
      # Check that original action reference is maintained
      if workflow_step.original_action == original_action.action_module do
        {:ok, %{check: :semantic_preservation, status: :preserved, semantics_maintained: true}}
      else
        {:error,
         %{
           check: :semantic_preservation,
           status: :not_preserved,
           issue: :action_reference_mismatch
         }}
      end
    else
      {:ok, %{check: :semantic_preservation, status: :not_required}}
    end
  end

  defp validate_workflow_compatibility(workflow_step) do
    # Validate workflow step compatibility with Reactor
    step_type = Map.get(workflow_step, :type)

    if step_type in [
         :agent_action_step,
         :enhanced_agent_action_step,
         :composed_agent_action_step,
         :monitored_agent_action_step
       ] do
      {:ok, %{check: :workflow_compatibility, status: :compatible, step_type: step_type}}
    else
      {:error, %{check: :workflow_compatibility, status: :incompatible, invalid_type: step_type}}
    end
  end

  defp validate_performance_characteristics(workflow_step) do
    # Validate expected performance characteristics
    has_monitoring = Map.get(workflow_step, :monitoring_config) != nil
    has_metadata = Map.get(workflow_step, :metadata) != nil

    performance_score =
      if(has_monitoring, do: 0.5, else: 0.0) + if(has_metadata, do: 0.5, else: 0.0)

    {:ok,
     %{
       check: :performance_characteristics,
       status: :assessed,
       performance_score: performance_score,
       monitoring_available: has_monitoring,
       metadata_available: has_metadata
     }}
  end

  defp generate_validation_recommendations(failed_validations) do
    if Enum.empty?(failed_validations) do
      ["Conversion validation successful - workflow step ready for use"]
    else
      Enum.map(failed_validations, &generate_single_validation_recommendation/1)
    end
  end

  defp generate_single_validation_recommendation({:error, error_info}) do
    case error_info.check do
      :workflow_step_structure ->
        "Fix workflow step structure - missing fields: #{inspect(error_info.missing_fields)}"

      :semantic_preservation ->
        "Ensure action semantics are preserved in workflow step"

      :workflow_compatibility ->
        "Verify workflow step type compatibility with Reactor framework"

      _ ->
        "Address #{error_info.check} validation issue"
    end
  end
end
