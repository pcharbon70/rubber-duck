defmodule RubberDuck.EventStore.Events.EntityCreated do
  @moduledoc """
  Event representing an entity creation in the system.
  
  This event is recorded whenever any entity (User, Project, CodeFile, AnalysisResult)
  is created, capturing the initial state of the entity.
  """

  @derive Jason.Encoder
  @enforce_keys [:entity_id, :entity_type, :entity_data, :timestamp]
  defstruct [
    :entity_id,
    :entity_type,
    :entity_data,
    :timestamp
  ]

  @type t :: %__MODULE__{
    entity_id: String.t(),
    entity_type: atom(),
    entity_data: map(),
    timestamp: DateTime.t()
  }

  @doc """
  Creates a new EntityCreated event.
  
  ## Parameters
  
  - `entity_id` - The ID of the entity that was created
  - `entity_type` - The type of entity (e.g., :user, :project, :code_file)
  - `entity_data` - Complete data of the created entity
  
  ## Example
  
      event = EntityCreated.new(
        entity_id: "123",
        entity_type: :user,
        entity_data: %{id: "123", email: "user@example.com", username: "user"}
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
         true <- is_map(event.entity_data) and map_size(event.entity_data) > 0,
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
    "Created #{event.entity_type} #{event.entity_id}"
  end

  @doc """
  Gets the initial value of a field from the created entity.
  """
  @spec get_initial_value(t(), String.t() | atom()) :: any()
  def get_initial_value(%__MODULE__{entity_data: data}, field) when is_atom(field) do
    Map.get(data, field)
  end

  def get_initial_value(%__MODULE__{entity_data: data}, field) when is_binary(field) do
    Map.get(data, field) || Map.get(data, String.to_atom(field))
  end

  @doc """
  Gets all field names from the created entity.
  """
  @spec get_field_names(t()) :: list(String.t())
  def get_field_names(%__MODULE__{entity_data: data}) do
    Map.keys(data)
  end
end