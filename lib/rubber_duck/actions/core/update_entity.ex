defmodule RubberDuck.Actions.Core.UpdateEntity do
  @moduledoc """
  Thin orchestrator action for updating entities with impact assessment and change propagation.

  This action coordinates specialized modules to provide:
  - Input validation and sanitization via Validator
  - Impact assessment via ImpactAnalyzer
  - Change execution with version tracking via Executor
  - Learning from outcomes via Learner
  - Change propagation to dependent entities via Propagator

  The action follows a pipeline pattern, delegating all business logic
  to specialized modules while maintaining a clean, readable flow.
  """

  use Jido.Action,
    name: "update_entity",
    description: "Updates entities with impact assessment and learning",
    schema: [
      entity_id: [type: :string, required: true],
      entity_type: [type: :atom, required: true, values: [:user, :project, :code_file, :analysis]],
      changes: [type: :map, required: true],
      impact_analysis: [type: :boolean, default: true],
      auto_propagate: [type: :boolean, default: false],
      learning_enabled: [type: :boolean, default: true],
      agent_goals: [type: {:list, :map}, default: []],
      rollback_on_failure: [type: :boolean, default: true],
      validation_config: [type: :map, default: %{}]
    ]

  alias RubberDuck.Actions.Core.Entity

  alias RubberDuck.Actions.Core.UpdateEntity.{
    Validator,
    ImpactAnalyzer,
    Executor,
    Learner,
    Propagator
  }

  require Logger

  @impl true
  def run(params, context) do
    prepared_params = prepare_params(params)
    result = execute_pipeline(prepared_params, context)

    case result do
      {:error, _} = error ->
        handle_error(error, prepared_params, context)

      data ->
        {:ok, build_success_response(data)}
    end
  end

  # Prepare parameters for the pipeline
  defp prepare_params(params) do
    %{
      entity_id: params.entity_id,
      entity_type: params.entity_type,
      changes: params.changes,
      validation_config: params.validation_config,
      agent_goals: params.agent_goals,
      options: %{
        impact_analysis: params.impact_analysis,
        auto_propagate: params.auto_propagate,
        learning_enabled: params.learning_enabled,
        rollback_on_failure: params.rollback_on_failure
      }
    }
  end

  # Execute the update pipeline
  defp execute_pipeline(params, _context) do
    # Simple pipeline without with_pipeline for now
    params
    |> fetch_entity()
    |> maybe_continue(&validate_and_prepare/1)
    |> maybe_continue(&assess_impact/1)
    |> maybe_continue(&check_goals/1)
    |> maybe_continue(&execute_changes/1)
    |> maybe_continue(&propagate_if_enabled/1)
    |> maybe_continue(&learn_if_enabled/1)
  end

  # Helper to continue pipeline or pass through errors
  defp maybe_continue({:error, _} = error, _fun), do: error
  defp maybe_continue(data, fun), do: fun.(data)

  # Fetch the entity to be updated
  defp fetch_entity(params) do
    case Entity.fetch(params.entity_type, params.entity_id) do
      {:ok, entity} ->
        Map.put(params, :entity, entity)

      {:error, _reason} = error ->
        {:error, %{step: :fetch_entity, error: error}}
    end
  end

  # Validate changes and prepare for execution
  defp validate_and_prepare(%{entity: entity} = params) do
    validation_params = %{
      # Validator expects entity as map
      current_entity: Entity.to_map(entity),
      changes: params.changes,
      validation_config: params.validation_config
    }

    case Validator.validate(validation_params, %{}) do
      {:ok, validation_result} ->
        params
        |> Map.put(:validated_changes, validation_result)
        |> Map.put(:validation_result, validation_result)

      {:error, _reason} = error ->
        {:error, %{step: :validation, error: error}}
    end
  end

  # Assess the impact of changes
  defp assess_impact(%{options: %{impact_analysis: false}} = params) do
    # Skip impact analysis if disabled
    Map.put(params, :impact_assessment, %{
      impact_score: 0.0,
      impact_details: %{},
      skipped: true
    })
  end

  defp assess_impact(%{entity: entity, validated_changes: validated_changes} = params) do
    analyzer_params = %{
      entity: Entity.to_map(entity),
      validated_changes: validated_changes
    }

    case ImpactAnalyzer.analyze(analyzer_params, %{}) do
      {:ok, impact_result} ->
        Map.put(params, :impact_assessment, impact_result)

      {:error, _reason} = error ->
        {:error, %{step: :impact_analysis, error: error}}
    end
  end

  # Check goal alignment
  defp check_goals(%{agent_goals: []} = params) do
    Map.put(params, :goal_approval, %{
      approved: true,
      alignment_score: 1.0,
      reason: :no_goals_specified
    })
  end

  defp check_goals(
         %{validated_changes: changes, impact_assessment: impact, agent_goals: goals} = params
       ) do
    case check_goal_alignment(changes, impact, goals) do
      {:ok, approval} ->
        Map.put(params, :goal_approval, approval)

      {:error, _reason} = error ->
        {:error, %{step: :goal_alignment, error: error}}
    end
  end

  # Execute the changes
  defp execute_changes(params) do
    executor_params = %{
      entity: Entity.to_map(params.entity),
      validated_changes: params.validated_changes,
      impact_assessment: params.impact_assessment,
      rollback_on_failure: params.options.rollback_on_failure
    }

    case Executor.execute(executor_params, %{}) do
      {:ok, execution_result} ->
        # The executor returns the updated entity as a map
        # We need to apply those changes to our Entity wrapper
        changes_map = Map.drop(execution_result.entity, [:id, :type])
        {:ok, updated_entity} = Entity.apply_changes(params.entity, changes_map)

        params
        |> Map.put(:execution_result, execution_result)
        |> Map.put(:updated_entity, updated_entity)

      {:error, _reason} = error ->
        {:error, %{step: :execution, error: error}}
    end
  end

  # Propagate changes if enabled
  defp propagate_if_enabled(%{options: %{auto_propagate: false}} = params) do
    Map.put(params, :propagation_result, %{
      propagated: false,
      reason: :auto_propagate_disabled
    })
  end

  defp propagate_if_enabled(params) do
    propagator_params = %{
      entity: Entity.to_map(params.updated_entity),
      impact_assessment: params.impact_assessment,
      propagation_options: extract_propagation_options(params)
    }

    case Propagator.propagate(propagator_params, %{}) do
      {:ok, propagation_result} ->
        Map.put(params, :propagation_result, propagation_result)

      {:error, _reason} = error ->
        # Propagation failures are non-fatal
        Logger.warning("Propagation failed: #{inspect(error)}")

        Map.put(params, :propagation_result, %{
          propagated: false,
          error: error
        })
    end
  end

  # Learn from the outcome if enabled
  defp learn_if_enabled(%{options: %{learning_enabled: false}} = params) do
    Map.put(params, :learning_result, %{
      learned: false,
      reason: :learning_disabled
    })
  end

  defp learn_if_enabled(params) do
    learner_params = %{
      entity: Entity.to_map(params.updated_entity),
      impact_assessment: params.impact_assessment,
      execution_result: params.execution_result
    }

    case Learner.learn(learner_params, %{}) do
      {:ok, learning_result} ->
        Map.put(params, :learning_result, learning_result)

      {:error, _reason} = error ->
        # Learning failures are non-fatal
        Logger.warning("Learning failed: #{inspect(error)}")

        Map.put(params, :learning_result, %{
          learned: false,
          error: error
        })
    end
  end

  # Handle errors from the pipeline
  defp handle_error({:error, %{step: step, error: reason}}, params, context) do
    # Track failure for learning
    if params.options.learning_enabled do
      Learner.track_failure(reason, params, context)
    end

    # Attempt rollback if configured
    if params.options.rollback_on_failure and step == :execution do
      attempt_rollback(params, context)
    end

    {:error,
     %{
       step: step,
       reason: reason,
       entity_id: params.entity_id,
       entity_type: params.entity_type
     }}
  end

  # Build the success response
  defp build_success_response(result) do
    %{
      entity: Entity.to_map(result.updated_entity),
      previous_state: result.execution_result.previous_state,
      changes_applied: result.validated_changes,
      impact_assessment: result.impact_assessment,
      propagation_results: result.propagation_result,
      learning_data: result.learning_result,
      goal_alignment_score: result.goal_approval.alignment_score,
      metadata: build_metadata(result)
    }
  end

  # Build metadata for the response
  defp build_metadata(result) do
    %{
      action: "update_entity",
      entity_id: result.updated_entity.id,
      entity_type: result.updated_entity.type,
      timestamp: DateTime.utc_now(),
      validation_passed: true,
      impact_score: result.impact_assessment[:impact_score] || 0.0,
      changes_propagated: result.propagation_result.propagated,
      learning_captured: Map.get(result.learning_result, :learned, false)
    }
  end

  # Extract propagation options
  defp extract_propagation_options(params) do
    %{
      force_sequential: false,
      max_parallelism: 5,
      enable_rollback: params.options.rollback_on_failure
    }
  end

  # Goal alignment check (simple version - can be extracted to separate module)
  defp check_goal_alignment(changes, impact_assessment, agent_goals) do
    alignment_scores =
      Enum.map(agent_goals, fn goal ->
        evaluate_goal_alignment(changes, impact_assessment, goal)
      end)

    avg_score =
      if length(alignment_scores) > 0 do
        Enum.sum(alignment_scores) / length(alignment_scores)
      else
        1.0
      end

    if avg_score >= 0.6 do
      {:ok,
       %{
         approved: true,
         alignment_score: avg_score,
         aligned_goals: Enum.count(alignment_scores, &(&1 >= 0.6)),
         total_goals: length(agent_goals)
       }}
    else
      {:error,
       %{
         reason: :goal_misalignment,
         alignment_score: avg_score,
         recommendation: "Changes do not align with agent goals"
       }}
    end
  end

  defp evaluate_goal_alignment(_changes, impact_assessment, goal) do
    case goal.type do
      :quality ->
        if impact_assessment[:impact_score] < 0.3, do: 0.9, else: 0.6

      :performance ->
        case impact_assessment[:impact_details][:performance_impact][:throughput_impact] do
          :negligible -> 1.0
          :moderate -> 0.5
          _ -> 0.3
        end

      :stability ->
        case impact_assessment[:impact_details][:risk_assessment][:risk_level] do
          :minimal -> 1.0
          :low -> 0.8
          :medium -> 0.5
          :high -> 0.2
          _ -> 0.5
        end

      _ ->
        0.5
    end
  end

  # Attempt rollback on failure
  defp attempt_rollback(params, _context) do
    Logger.warning("Attempting rollback for entity #{params.entity_id}")
    # In production, would restore from snapshot
    :ok
  end
end
