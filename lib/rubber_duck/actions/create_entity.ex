defmodule RubberDuck.Actions.CreateEntity do
  @moduledoc """
  Generic entity creation action with validation and error handling.

  This action provides a standardized approach to creating entities
  across different domains with proper validation and learning integration.
  """

  use Jido.Action,
    name: "create_entity",
    schema: [
      entity_type: [type: :atom, required: true],
      entity_data: [type: :map, required: true]
    ]

  alias RubberDuck.Skills.LearningSkill

  @doc """
  Create a new entity with validation and learning tracking.
  """
  def run(%{entity_type: entity_type, entity_data: entity_data} = _params, context) do
    # Validate required parameters
    with :ok <- validate_entity_type(entity_type),
         :ok <- validate_entity_data(entity_data),
         {:ok, created_entity} <- create_entity(entity_type, entity_data, context) do
      # Track successful creation for learning
      learning_context = %{
        entity_type: entity_type,
        action: :create,
        data_size: map_size(entity_data)
      }

      # Use learning skill to track this success
      LearningSkill.track_experience(
        %{
          experience: %{action: :create_entity, entity_type: entity_type},
          outcome: :success,
          context: learning_context
        },
        context
      )

      {:ok, created_entity}
    else
      {:error, reason} ->
        # Track failed creation for learning
        learning_context = %{
          entity_type: entity_type,
          action: :create,
          error_reason: reason
        }

        LearningSkill.track_experience(
          %{
            experience: %{action: :create_entity, entity_type: entity_type},
            outcome: :failure,
            context: learning_context
          },
          context
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_entity_type(entity_type) when is_atom(entity_type) do
    valid_types = [:user, :project, :code_file, :ai_analysis]

    if entity_type in valid_types do
      :ok
    else
      {:error, {:invalid_entity_type, entity_type}}
    end
  end

  defp validate_entity_type(_), do: {:error, :entity_type_must_be_atom}

  defp validate_entity_data(entity_data) when is_map(entity_data) do
    if map_size(entity_data) > 0 do
      :ok
    else
      {:error, :entity_data_cannot_be_empty}
    end
  end

  defp validate_entity_data(_), do: {:error, :entity_data_must_be_map}

  defp create_entity(:user, entity_data, _context) do
    # For now, return a mock user entity
    # TODO: Integrate with actual Ash User resource creation
    created_entity =
      Map.merge(
        %{
          id: generate_id(),
          type: :user,
          created_at: DateTime.utc_now()
        },
        entity_data
      )

    {:ok, created_entity}
  end

  defp create_entity(:project, entity_data, _context) do
    # TODO: Create actual Project Ash resource
    created_entity =
      Map.merge(
        %{
          id: generate_id(),
          type: :project,
          created_at: DateTime.utc_now(),
          status: :active
        },
        entity_data
      )

    {:ok, created_entity}
  end

  defp create_entity(:code_file, entity_data, _context) do
    # TODO: Create actual CodeFile Ash resource
    created_entity =
      Map.merge(
        %{
          id: generate_id(),
          type: :code_file,
          created_at: DateTime.utc_now(),
          analysis_status: :pending
        },
        entity_data
      )

    {:ok, created_entity}
  end

  defp create_entity(:ai_analysis, entity_data, _context) do
    # TODO: Create actual AIAnalysis Ash resource
    created_entity =
      Map.merge(
        %{
          id: generate_id(),
          type: :ai_analysis,
          created_at: DateTime.utc_now(),
          status: :queued
        },
        entity_data
      )

    {:ok, created_entity}
  end

  defp create_entity(entity_type, _entity_data, _context) do
    {:error, {:unsupported_entity_type, entity_type}}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
