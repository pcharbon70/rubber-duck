defmodule RubberDuck.Actions.Core.Entity do
  @moduledoc """
  Thin entity wrapper for cross-domain coordination in actions.

  This module provides a lightweight abstraction over Ash resources
  to enable:
  - Cross-domain impact analysis
  - Runtime metadata attachment
  - Unified interface for heterogeneous sources
  - Temporary state during complex operations

  Entities are NOT meant to replace Ash resources but to coordinate
  them during complex multi-step actions.
  """
  
  alias RubberDuck.EntityRepository

  defstruct [
    :id,
    :type,
    # Original Ash resource or external data
    :resource,
    :version,
    # Runtime metadata
    :metadata,
    # Cached impact calculations
    :impact_cache,
    # Loaded dependencies
    :dependencies,
    # Pre-change snapshot for rollback
    :snapshot,
    # Where this came from (:ash, :external, :cache)
    :source
  ]

  @type entity_type :: :user | :project | :code_file | :analysis

  @type t :: %__MODULE__{
          id: String.t(),
          type: entity_type(),
          resource: any(),
          version: integer(),
          metadata: map(),
          impact_cache: map(),
          dependencies: map(),
          snapshot: map() | nil,
          source: :ash | :external | :cache
        }

  @doc """
  Wraps an Ash resource as an entity for action coordination.
  """
  def from_ash_resource(resource, type) do
    %__MODULE__{
      id: get_resource_id(resource),
      type: type,
      resource: resource,
      version: get_resource_version(resource),
      metadata: %{
        wrapped_at: DateTime.utc_now(),
        ash_domain: detect_ash_domain(type)
      },
      impact_cache: %{},
      dependencies: %{},
      snapshot: nil,
      source: :ash
    }
  end

  @doc """
  Wraps external data (non-Ash) as an entity.
  """
  def from_external(data, type, id) do
    %__MODULE__{
      id: id,
      type: type,
      resource: data,
      version: Map.get(data, :version, 1),
      metadata: %{
        wrapped_at: DateTime.utc_now(),
        external_source: true
      },
      impact_cache: %{},
      dependencies: %{},
      snapshot: nil,
      source: :external
    }
  end

  @doc """
  Fetches an entity by type and ID, wrapping the appropriate resource.
  """
  def fetch(type, id) do
    case fetch_resource(type, id) do
      {:ok, resource} ->
        {:ok, from_ash_resource(resource, type)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fetches an entity with its dependencies loaded.
  """
  def fetch_with_dependencies(type, id, depth \\ 1) do
    with {:ok, entity} <- fetch(type, id),
         {:ok, entity_with_deps} <- load_dependencies(entity, depth) do
      {:ok, entity_with_deps}
    end
  end

  @doc """
  Loads dependencies for an entity.
  """
  def load_dependencies(%__MODULE__{} = entity, depth) when depth > 0 do
    dependencies =
      case entity.type do
        :user -> load_user_dependencies(entity.resource)
        :project -> load_project_dependencies(entity.resource)
        :code_file -> load_code_file_dependencies(entity.resource)
        :analysis -> load_analysis_dependencies(entity.resource)
      end

    {:ok, %{entity | dependencies: dependencies}}
  end

  def load_dependencies(entity, _depth), do: {:ok, entity}

  @doc """
  Applies changes to an entity through Ash or appropriate mechanism.
  """
  def apply_changes(%__MODULE__{source: :ash} = entity, changes) do
    changeset = build_changeset(entity.resource, entity.type, changes)

    case apply_changeset(changeset, entity.type) do
      {:ok, updated_resource} ->
        {:ok,
         %{
           entity
           | resource: updated_resource,
             version: entity.version + 1,
             metadata: Map.put(entity.metadata, :last_updated, DateTime.utc_now())
         }}

      error ->
        error
    end
  end

  def apply_changes(%__MODULE__{source: :external} = entity, changes) do
    # For external entities, merge changes directly
    updated_resource = Map.merge(entity.resource, changes)

    {:ok,
     %{
       entity
       | resource: updated_resource,
         version: entity.version + 1,
         metadata: Map.put(entity.metadata, :last_updated, DateTime.utc_now())
     }}
  end

  @doc """
  Creates a snapshot of the entity for rollback purposes.
  """
  def create_snapshot(%__MODULE__{} = entity) do
    snapshot = %{
      resource: deep_copy(entity.resource),
      version: entity.version,
      metadata: entity.metadata,
      timestamp: DateTime.utc_now()
    }

    {:ok, %{entity | snapshot: snapshot}}
  end

  @doc """
  Restores entity from snapshot.
  """
  def restore_from_snapshot(%__MODULE__{snapshot: nil}), do: {:error, :no_snapshot}

  def restore_from_snapshot(%__MODULE__{source: :ash, snapshot: snapshot} = entity) do
    # For Ash resources, update through changeset
    changeset = build_restore_changeset(entity.resource, entity.type, snapshot.resource)

    case apply_changeset(changeset, entity.type) do
      {:ok, restored_resource} ->
        {:ok,
         %{
           entity
           | resource: restored_resource,
             version: snapshot.version,
             metadata: Map.put(snapshot.metadata, :restored_at, DateTime.utc_now()),
             snapshot: nil
         }}

      error ->
        error
    end
  end

  def restore_from_snapshot(%__MODULE__{source: :external, snapshot: snapshot} = entity) do
    {:ok,
     %{
       entity
       | resource: snapshot.resource,
         version: snapshot.version,
         metadata: Map.put(snapshot.metadata, :restored_at, DateTime.utc_now()),
         snapshot: nil
     }}
  end

  @doc """
  Gets a field value from the entity, checking both resource and metadata.
  """
  def get_field(%__MODULE__{} = entity, field) do
    # First check the resource
    case Map.get(entity.resource, field) do
      nil ->
        # Then check metadata
        Map.get(entity.metadata, field)

      value ->
        value
    end
  end

  @doc """
  Returns the raw data for the entity (for analysis modules).
  """
  def to_map(%__MODULE__{} = entity) do
    base_map =
      case entity.source do
        :ash -> ash_resource_to_map(entity.resource)
        _ -> entity.resource
      end

    Map.merge(base_map, %{
      id: entity.id,
      type: entity.type,
      version: entity.version
    })
  end

  # Private functions

  defp fetch_resource(type, id) when type in [:user, :project, :code_file, :analysis] do
    # Use EntityRepository for real database access
    EntityRepository.fetch(id, type)
  end

  defp fetch_resource(_unknown_type, _id) do
    {:error, :unknown_entity_type}
  end

  defp get_resource_id(resource) when is_map(resource) do
    Map.get(resource, :id) ||
      Map.get(resource, "id") ||
      to_string(:erlang.phash2(resource))
  end

  defp get_resource_id(_resource) do
    to_string(:erlang.phash2(:crypto.strong_rand_bytes(16)))
  end

  defp get_resource_version(resource) do
    Map.get(resource, :version) ||
      Map.get(resource, :lock_version) ||
      1
  end

  defp detect_ash_domain(:user), do: RubberDuck.Accounts
  defp detect_ash_domain(:project), do: RubberDuck.Projects
  defp detect_ash_domain(_), do: nil

  defp load_user_dependencies(user_resource) do
    %{
      # Would load actual sessions
      sessions: [],
      preferences: Map.get(user_resource, :preferences, %{}),
      # Would load user's projects
      projects: []
    }
  end

  defp load_project_dependencies(_project_resource) do
    %{
      # Would load project files
      code_files: [],
      # Would load project analyses
      analyses: [],
      # Would load collaborators
      collaborators: []
    }
  end

  defp load_code_file_dependencies(file_resource) do
    %{
      project: Map.get(file_resource, :project_id),
      # Would analyze imports
      imports: [],
      # Would find related tests
      tests: []
    }
  end

  defp load_analysis_dependencies(analysis_resource) do
    %{
      target: Map.get(analysis_resource, :target),
      related_analyses: []
    }
  end

  defp build_changeset(resource, :user, changes) do
    # Would build actual Ash changeset
    # RubberDuck.Accounts.User
    # |> Ash.Changeset.for_update(:update, changes)
    {:ok, Map.merge(resource, changes)}
  end

  defp build_changeset(resource, :project, changes) do
    # Would build actual Ash changeset
    {:ok, Map.merge(resource, changes)}
  end

  defp build_changeset(resource, _type, changes) do
    {:ok, Map.merge(resource, changes)}
  end

  defp apply_changeset({:ok, updated}, _type) do
    # Would apply through Ash
    # Ash.update(changeset)
    {:ok, updated}
  end

  defp build_restore_changeset(_resource, _type, snapshot_data) do
    {:ok, snapshot_data}
  end

  defp ash_resource_to_map(resource) when is_struct(resource) do
    resource
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__struct__])
  end

  defp ash_resource_to_map(resource), do: resource

  defp deep_copy(data) when is_struct(data, DateTime), do: data
  defp deep_copy(data) when is_struct(data, Date), do: data
  defp deep_copy(data) when is_struct(data, Time), do: data
  defp deep_copy(data) when is_struct(data, NaiveDateTime), do: data

  defp deep_copy(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> deep_copy()
  end

  defp deep_copy(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, deep_copy(v)} end)
  end

  defp deep_copy(data) when is_list(data) do
    Enum.map(data, &deep_copy/1)
  end

  defp deep_copy(data), do: data
end
