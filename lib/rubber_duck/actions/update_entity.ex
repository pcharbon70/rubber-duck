defmodule RubberDuck.Actions.UpdateEntity do
  @moduledoc """
  Intelligent entity updates with change tracking and rollback capability.

  This action provides sophisticated entity updates with learning integration,
  change impact analysis, and rollback capabilities.
  """

  use Jido.Action,
    name: "update_entity",
    schema: [
      entity_id: [type: :string, required: true],
      entity_type: [type: :atom, required: true],
      updates: [type: :map, required: true],
      options: [type: :map, default: %{}]
    ]

  alias RubberDuck.Skills.LearningSkill

  @doc """
  Update an entity with intelligent change tracking.
  """
  def run(
        %{entity_id: entity_id, entity_type: entity_type, updates: updates, options: options} =
          _params,
        context
      ) do
    with :ok <- validate_update_data(updates),
         {:ok, current_entity} <- fetch_current_entity(entity_type, entity_id),
         {:ok, change_analysis} <- analyze_update_impact(current_entity, updates),
         {:ok, updated_entity} <- apply_updates(current_entity, updates, options) do
      # Track successful update for learning
      learning_context = %{
        entity_type: entity_type,
        action: :update,
        changes_count: map_size(updates),
        impact_level: change_analysis.impact_level
      }

      LearningSkill.track_experience(
        %{
          experience: %{
            action: :update_entity,
            entity_type: entity_type,
            impact: change_analysis.impact_level
          },
          outcome: :success,
          context: learning_context
        },
        context
      )

      {:ok, %{entity: updated_entity, change_analysis: change_analysis}}
    else
      {:error, reason} ->
        # Track failed update for learning
        learning_context = %{
          entity_type: entity_type,
          action: :update,
          error_reason: reason
        }

        LearningSkill.track_experience(
          %{
            experience: %{action: :update_entity, entity_type: entity_type},
            outcome: :failure,
            context: learning_context
          },
          context
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_update_data(updates) when is_map(updates) do
    if map_size(updates) > 0 do
      :ok
    else
      {:error, :no_updates_provided}
    end
  end

  defp validate_update_data(_), do: {:error, :updates_must_be_map}

  defp fetch_current_entity(:user, entity_id) do
    # TODO: Integrate with actual Ash User resource
    {:ok,
     %{
       id: entity_id,
       type: :user,
       email: "test@example.com",
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_current_entity(:project, entity_id) do
    # TODO: Integrate with actual Project Ash resource
    {:ok,
     %{
       id: entity_id,
       type: :project,
       name: "Sample Project",
       path: "/path/to/project",
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_current_entity(:code_file, entity_id) do
    # TODO: Integrate with actual CodeFile Ash resource
    {:ok,
     %{
       id: entity_id,
       type: :code_file,
       path: "/path/to/file.ex",
       size: 1024,
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_current_entity(:ai_analysis, entity_id) do
    # TODO: Integrate with actual AIAnalysis Ash resource
    {:ok,
     %{
       id: entity_id,
       type: :ai_analysis,
       status: :completed,
       results: %{},
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_current_entity(entity_type, _entity_id) do
    {:error, {:unsupported_entity_type, entity_type}}
  end

  defp analyze_update_impact(current_entity, updates) do
    changed_fields = Map.keys(updates)
    critical_fields = get_critical_fields(current_entity.type)

    impact_level =
      cond do
        Enum.any?(changed_fields, &(&1 in critical_fields)) -> :high
        length(changed_fields) > 5 -> :medium
        true -> :low
      end

    analysis = %{
      changed_fields: changed_fields,
      critical_changes: Enum.filter(changed_fields, &(&1 in critical_fields)),
      impact_level: impact_level,
      rollback_complexity: calculate_rollback_complexity(current_entity, updates),
      downstream_effects: predict_downstream_effects(current_entity, updates)
    }

    {:ok, analysis}
  end

  defp apply_updates(current_entity, updates, options) do
    # Merge updates with current entity
    updated_entity =
      Map.merge(current_entity, updates)
      |> Map.put(:updated_at, DateTime.utc_now())
      |> Map.put(:version, Map.get(current_entity, :version, 0) + 1)

    # Store rollback data if requested
    final_entity =
      if Map.get(options, :enable_rollback, false) do
        rollback_data = create_rollback_data(current_entity, updates)
        Map.put(updated_entity, :rollback_data, rollback_data)
      else
        updated_entity
      end

    {:ok, final_entity}
  end

  defp get_critical_fields(:user), do: [:email, :password_hash, :role]
  defp get_critical_fields(:project), do: [:name, :path, :status]
  defp get_critical_fields(:code_file), do: [:path, :content, :status]
  defp get_critical_fields(:ai_analysis), do: [:status, :results, :confidence]
  defp get_critical_fields(_), do: []

  defp calculate_rollback_complexity(current_entity, updates) do
    changed_count = map_size(updates)
    entity_size = map_size(current_entity)

    complexity_ratio = changed_count / max(entity_size, 1)

    cond do
      complexity_ratio > 0.5 -> :high
      complexity_ratio > 0.2 -> :medium
      true -> :low
    end
  end

  defp predict_downstream_effects(_current_entity, _updates) do
    # TODO: Implement sophisticated downstream effect prediction
    %{
      affected_relations: [],
      cascading_updates: [],
      potential_conflicts: []
    }
  end

  defp create_rollback_data(current_entity, updates) do
    changed_fields = Map.keys(updates)

    rollback_values =
      changed_fields
      |> Enum.map(fn field -> {field, Map.get(current_entity, field)} end)
      |> Enum.into(%{})

    %{
      original_values: rollback_values,
      rollback_timestamp: DateTime.utc_now(),
      rollback_version: Map.get(current_entity, :version, 0)
    }
  end
end
