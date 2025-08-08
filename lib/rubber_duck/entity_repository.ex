defmodule RubberDuck.EntityRepository do
  @moduledoc """
  Unified repository for fetching entities from the database using Ash.

  This module replaces all mock fetch_*_entity functions with real database
  queries, providing a consistent interface for entity retrieval across the
  application.

  ## Features

  - Type-safe entity fetching with proper error handling
  - Unified interface for all entity types (User, Project, CodeFile, AnalysisResult)
  - Automatic resource resolution based on entity type
  - Support for preloading associations
  - Query customization through options

  ## Usage

      # Fetch a user by ID
      {:ok, user} = EntityRepository.fetch("user_123", :user)
      
      # Fetch with preloaded associations
      {:ok, project} = EntityRepository.fetch("proj_456", :project, 
        preload: [:code_files, :owner])
      
      # Fetch by type with automatic resource resolution
      {:ok, entity} = EntityRepository.fetch_entity("file_789", :code_file)
  """

  alias RubberDuck.Accounts.User
  alias RubberDuck.Projects.{Project, CodeFile}
  alias RubberDuck.AI.AnalysisResult

  require Ash.Query
  require Logger

  @type entity_type :: :user | :project | :code_file | :analysis | :analysis_result
  @type fetch_options :: [
          preload: list(atom()),
          tenant: String.t() | nil,
          authorize?: boolean()
        ]

  @doc """
  Fetches an entity by ID and type from the database.

  ## Parameters

  - `entity_id` - The ID of the entity to fetch
  - `entity_type` - The type of entity (:user, :project, :code_file, :analysis_result)
  - `opts` - Options for the query:
    - `:preload` - List of associations to preload
    - `:tenant` - Tenant ID for multi-tenancy
    - `:authorize?` - Whether to apply authorization (default: false)

  ## Returns

  - `{:ok, entity}` - Successfully fetched entity
  - `{:error, :not_found}` - Entity not found
  - `{:error, reason}` - Other errors
  """
  @spec fetch(String.t() | binary(), entity_type(), fetch_options()) ::
          {:ok, struct()} | {:error, :not_found | term()}
  def fetch(entity_id, entity_type, opts \\ []) do
    resource = resource_for_type(entity_type)

    case do_fetch(resource, entity_id, opts) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, entity} -> {:ok, entity}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches an entity with automatic type detection.

  This is a convenience function that maintains backward compatibility
  with the old fetch_*_entity functions.
  """
  @spec fetch_entity(String.t() | binary(), entity_type(), fetch_options()) ::
          {:ok, struct()} | {:error, :not_found | term()}
  def fetch_entity(entity_id, entity_type, opts \\ []) do
    fetch(entity_id, entity_type, opts)
  end

  @doc """
  Fetches multiple entities by IDs.

  ## Parameters

  - `entity_ids` - List of entity IDs to fetch
  - `entity_type` - The type of entities
  - `opts` - Query options

  ## Returns

  - `{:ok, entities}` - List of found entities (may be less than requested if some not found)
  - `{:error, reason}` - Query error
  """
  @spec fetch_many(list(String.t() | binary()), entity_type(), fetch_options()) ::
          {:ok, list(struct())} | {:error, term()}
  def fetch_many(entity_ids, entity_type, opts \\ []) do
    resource = resource_for_type(entity_type)

    resource
    |> Ash.Query.filter(id in ^entity_ids)
    |> maybe_preload(opts[:preload])
    |> Ash.read(Keyword.take(opts, [:tenant, :authorize?]))
  end

  @doc """
  Checks if an entity exists without fetching it.

  ## Parameters

  - `entity_id` - The ID to check
  - `entity_type` - The type of entity

  ## Returns

  - `true` if entity exists
  - `false` if entity does not exist
  """
  @spec exists?(String.t() | binary(), entity_type()) :: boolean()
  def exists?(entity_id, entity_type) do
    resource = resource_for_type(entity_type)

    case resource
         |> Ash.Query.filter(id == ^entity_id)
         |> Ash.Query.limit(1)
         |> Ash.read_one() do
      {:ok, nil} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Queries entities with custom filters.

  ## Parameters

  - `entity_type` - The type of entities to query
  - `filters` - Keyword list of filters to apply
  - `opts` - Query options

  ## Returns

  - `{:ok, entities}` - List of matching entities
  - `{:error, reason}` - Query error

  ## Examples

      # Find all projects owned by a user
      {:ok, projects} = EntityRepository.query(:project, [owner_id: "user_123"])
      
      # Find code files in a project with specific extension
      {:ok, files} = EntityRepository.query(:code_file, 
        [project_id: "proj_456", extension: ".ex"])
  """
  @spec query(entity_type(), keyword(), fetch_options()) ::
          {:ok, list(struct())} | {:error, term()}
  def query(entity_type, filters \\ [], opts \\ []) do
    resource = resource_for_type(entity_type)

    query = Ash.Query.new(resource)

    query =
      Enum.reduce(filters, query, fn {key, value}, q ->
        Ash.Query.filter(q, ^[{key, value}])
      end)

    query
    |> maybe_preload(opts[:preload])
    |> Ash.read(Keyword.take(opts, [:tenant, :authorize?]))
  end

  @doc """
  Creates or updates an entity in the database.

  ## Parameters

  - `entity_type` - The type of entity to create/update
  - `params` - Parameters for the entity
  - `opts` - Options for creation

  ## Returns

  - `{:ok, entity}` - Successfully created/updated entity
  - `{:error, changeset}` - Validation or other errors
  """
  @spec upsert(entity_type(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def upsert(entity_type, params, opts \\ []) do
    resource = resource_for_type(entity_type)

    # For now, just create. Upsert logic would depend on resource configuration
    changeset = Ash.Changeset.for_create(resource, :create, params)
    Ash.create(changeset, opts)
  end

  @doc """
  Deletes an entity from the database.

  ## Parameters

  - `entity_id` - The ID of the entity to delete
  - `entity_type` - The type of entity

  ## Returns

  - `:ok` - Successfully deleted
  - `{:error, :not_found}` - Entity not found
  - `{:error, reason}` - Other errors
  """
  @spec delete(String.t() | binary(), entity_type()) ::
          :ok | {:error, :not_found | term()}
  def delete(entity_id, entity_type) do
    case fetch(entity_id, entity_type) do
      {:ok, entity} ->
        case Ash.destroy(entity) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp resource_for_type(:user), do: User
  defp resource_for_type(:project), do: Project
  defp resource_for_type(:code_file), do: CodeFile
  defp resource_for_type(:analysis), do: AnalysisResult
  defp resource_for_type(:analysis_result), do: AnalysisResult

  defp resource_for_type(unknown) do
    Logger.warning("Unknown entity type: #{inspect(unknown)}")
    raise ArgumentError, "Unknown entity type: #{inspect(unknown)}"
  end

  defp do_fetch(resource, entity_id, opts) do
    resource
    |> Ash.Query.filter(id == ^entity_id)
    |> maybe_preload(opts[:preload])
    |> Ash.Query.limit(1)
    |> Ash.read_one(Keyword.take(opts, [:tenant, :authorize?]))
  end

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, []), do: query

  defp maybe_preload(query, preloads) when is_list(preloads) do
    Ash.Query.load(query, preloads)
  end

  @doc """
  Legacy compatibility functions to ease migration.
  These will be removed in a future version.
  """
  @deprecated "Use EntityRepository.fetch/3 instead"
  def fetch_user_entity(id), do: fetch(id, :user)

  @deprecated "Use EntityRepository.fetch/3 instead"
  def fetch_project_entity(id), do: fetch(id, :project)

  @deprecated "Use EntityRepository.fetch/3 instead"
  def fetch_code_file_entity(id), do: fetch(id, :code_file)

  @deprecated "Use EntityRepository.fetch/3 instead"
  def fetch_analysis_entity(id), do: fetch(id, :analysis_result)
end
