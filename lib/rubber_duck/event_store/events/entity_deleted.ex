defmodule RubberDuck.EventStore.Events.EntityDeleted do
  @moduledoc """
  Event representing an entity deletion in the system.
  
  This event is recorded whenever any entity (User, Project, CodeFile, AnalysisResult)
  is deleted, capturing the reason for deletion and maintaining audit trail.
  """

  @derive Jason.Encoder
  @enforce_keys [:entity_id, :entity_type, :timestamp]
  defstruct [
    :entity_id,
    :entity_type,
    :reason,
    :timestamp
  ]

  @type t :: %__MODULE__{
    entity_id: String.t(),
    entity_type: atom(),
    reason: map() | nil,
    timestamp: DateTime.t()
  }

  @doc """
  Creates a new EntityDeleted event.
  
  ## Parameters
  
  - `entity_id` - The ID of the entity that was deleted
  - `entity_type` - The type of entity (e.g., :user, :project, :code_file)
  - `reason` - Reason for deletion (optional)
  
  ## Example
  
      event = EntityDeleted.new(
        entity_id: "123",
        entity_type: :user,
        reason: %{deleted_by: "admin", cause: "policy_violation"}
      )
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    attrs = Keyword.put_new(attrs, :timestamp, DateTime.utc_now())
    struct!(__MODULE__, attrs)
  end

  @doc """
  Validates that the event has all required fields and proper types.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = event) do
    with true <- is_binary(event.entity_id) and String.length(event.entity_id) > 0,
         true <- (is_atom(event.entity_type) or is_binary(event.entity_type)),
         true <- match?(%DateTime{}, event.timestamp) do
      true
    else
      _ -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Returns a human-readable description of the event.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{reason: nil} = event) do
    "Deleted #{event.entity_type} #{event.entity_id}"
  end

  def describe(%__MODULE__{reason: reason} = event) when is_map(reason) do
    reason_text = 
      case Map.get(reason, :cause) || Map.get(reason, "cause") do
        nil -> "no reason specified"
        cause -> "reason: #{cause}"
      end
    
    "Deleted #{event.entity_type} #{event.entity_id} (#{reason_text})"
  end

  @doc """
  Gets the deletion reason if provided.
  """
  @spec get_deletion_reason(t()) :: String.t() | nil
  def get_deletion_reason(%__MODULE__{reason: nil}), do: nil

  def get_deletion_reason(%__MODULE__{reason: reason}) when is_map(reason) do
    Map.get(reason, :cause) || Map.get(reason, "cause")
  end

  @doc """
  Gets who performed the deletion if recorded.
  """
  @spec get_deleted_by(t()) :: String.t() | nil
  def get_deleted_by(%__MODULE__{reason: nil}), do: nil

  def get_deleted_by(%__MODULE__{reason: reason}) when is_map(reason) do
    Map.get(reason, :deleted_by) || Map.get(reason, "deleted_by")
  end
end