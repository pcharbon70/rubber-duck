defmodule RubberDuck.EventStore.Events.EntityUpdated do
  @moduledoc """
  Event representing an entity update in the system.
  
  This event is recorded whenever any entity (User, Project, CodeFile, AnalysisResult)
  is updated, capturing the changes made and their impact.
  """

  @derive Jason.Encoder
  @enforce_keys [:entity_id, :entity_type, :changes, :timestamp]
  defstruct [
    :entity_id,
    :entity_type,
    :changes,
    :impact,
    :timestamp
  ]

  @type t :: %__MODULE__{
    entity_id: String.t(),
    entity_type: atom(),
    changes: map(),
    impact: map() | nil,
    timestamp: DateTime.t()
  }

  @doc """
  Creates a new EntityUpdated event.
  
  ## Parameters
  
  - `entity_id` - The ID of the entity that was updated
  - `entity_type` - The type of entity (e.g., :user, :project, :code_file)
  - `changes` - Map of field changes that were applied
  - `impact` - Impact assessment data (optional)
  
  ## Example
  
      event = EntityUpdated.new(
        entity_id: "123",
        entity_type: :user,
        changes: %{email: "new@example.com"},
        impact: %{risk_level: :low}
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
         true <- is_map(event.changes) and map_size(event.changes) > 0,
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
  def describe(%__MODULE__{} = event) do
    changed_fields = Map.keys(event.changes) |> Enum.sort() |> Enum.join(", ")
    "Updated #{event.entity_type} #{event.entity_id}: changed #{changed_fields}"
  end

  @doc """
  Extracts the changed field names from the event.
  """
  @spec changed_fields(t()) :: list(String.t())
  def changed_fields(%__MODULE__{changes: changes}) do
    Map.keys(changes) |> Enum.sort()
  end

  @doc """
  Checks if a specific field was changed in this event.
  """
  @spec field_changed?(t(), String.t() | atom()) :: boolean()
  def field_changed?(%__MODULE__{changes: changes}, field) when is_atom(field) do
    Map.has_key?(changes, field)
  end

  def field_changed?(%__MODULE__{changes: changes}, field) when is_binary(field) do
    Map.has_key?(changes, field) or Map.has_key?(changes, String.to_atom(field))
  end

  @doc """
  Gets the new value for a changed field.
  """
  @spec get_new_value(t(), String.t() | atom()) :: any()
  def get_new_value(%__MODULE__{changes: changes}, field) when is_atom(field) do
    Map.get(changes, field)
  end

  def get_new_value(%__MODULE__{changes: changes}, field) when is_binary(field) do
    Map.get(changes, field) || Map.get(changes, String.to_atom(field))
  end
end