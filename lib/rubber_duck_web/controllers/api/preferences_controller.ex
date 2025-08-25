defmodule RubberDuckWeb.API.PreferencesController do
  @moduledoc """
  REST API controller for preference management.

  Provides CRUD operations for preferences with authentication, authorization,
  rate limiting, and comprehensive error handling.
  """

  use RubberDuckWeb, :controller

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Resources.{SystemDefault, UserPreference}

  action_fallback(RubberDuckWeb.API.FallbackController)

  @doc """
  List preferences with filtering and pagination.

  Query parameters:
  - category: Filter by preference category
  - user_id: Get preferences for specific user (defaults to current user)
  - project_id: Include project-specific overrides
  - page: Page number for pagination
  - per_page: Items per page (default 50, max 100)
  - search: Search term for preference keys/descriptions
  """
  def index(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, filters} <- parse_list_filters(params),
         {:ok, preferences} <- get_preferences_list(user, filters),
         {:ok, paginated} <- paginate_preferences(preferences, filters) do
      conn
      |> put_resp_header("x-total-count", to_string(length(preferences)))
      |> put_resp_header("x-page", to_string(filters.page))
      |> put_resp_header("x-per-page", to_string(filters.per_page))
      |> render(:index, preferences: paginated)
    end
  end

  @doc """
  Create a new preference (user or project override).

  Body parameters:
  - preference_key: The preference key to set
  - value: The preference value
  - project_id: Optional project ID for project-specific preference
  - reason: Optional reason for the change
  - category: Optional category override
  """
  def create(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, validated_params} <- validate_preference_params(params),
         {:ok, preference} <- create_preference(user, validated_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/preferences/#{preference.id}")
      |> render(:show, preference: preference)
    end
  end

  @doc """
  Show a specific preference with resolved value and inheritance info.
  """
  def show(conn, %{"id" => preference_key}) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, preference} <-
           get_preference_details(user, preference_key, conn.params["project_id"]) do
      render(conn, :show, preference: preference)
    end
  end

  @doc """
  Update a preference value.

  Body parameters:
  - value: New preference value
  - reason: Optional reason for the change
  """
  def update(conn, %{"id" => preference_key} = params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, validated_params} <- validate_update_params(params),
         {:ok, preference} <- update_preference(user, preference_key, validated_params) do
      render(conn, :show, preference: preference)
    end
  end

  @doc """
  Delete a preference (reset to default/inherited value).
  """
  def delete(conn, %{"id" => preference_key}) do
    with {:ok, user} <- get_current_user(conn),
         :ok <- delete_preference(user, preference_key, conn.params["project_id"]) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Batch operations on multiple preferences.

  Body parameters:
  - operations: Array of operations
    - action: "create", "update", or "delete"  
    - preference_key: The preference key
    - value: The preference value (for create/update)
    - project_id: Optional project ID
  """
  def batch(conn, %{"operations" => operations}) when is_list(operations) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, validated_operations} <- validate_batch_operations(operations),
         {:ok, results} <- execute_batch_operations(user, validated_operations) do
      conn
      |> put_status(:ok)
      |> render(:batch, results: results)
    end
  end

  def batch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "operations parameter is required and must be an array"})
  end

  # Private helper functions

  defp get_current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp parse_list_filters(params) do
    filters = %{
      category: params["category"],
      user_id: params["user_id"],
      project_id: params["project_id"],
      search: params["search"],
      page: parse_integer(params["page"], 1),
      per_page: min(parse_integer(params["per_page"], 50), 100)
    }

    {:ok, filters}
  end

  defp parse_integer(nil, default), do: default

  defp parse_integer(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(int, _default) when is_integer(int), do: int
  defp parse_integer(_, default), do: default

  defp get_preferences_list(user, filters) do
    case SystemDefault.read() do
      {:ok, system_defaults} ->
        preferences =
          system_defaults
          |> filter_by_category(filters.category)
          |> filter_by_search(filters.search)
          |> Enum.map(&build_preference_response(user, &1, filters))

        {:ok, preferences}

      error ->
        error
    end
  end

  defp filter_by_category(defaults, nil), do: defaults

  defp filter_by_category(defaults, category) do
    Enum.filter(defaults, &(&1.category == category))
  end

  defp filter_by_search(defaults, nil), do: defaults
  defp filter_by_search(defaults, ""), do: defaults

  defp filter_by_search(defaults, search) do
    search = String.downcase(search)

    Enum.filter(defaults, fn default ->
      String.contains?(String.downcase(default.preference_key), search) or
        String.contains?(String.downcase(default.description || ""), search)
    end)
  end

  defp build_preference_response(user, system_default, filters) do
    target_user_id = filters.user_id || user.id

    case PreferenceResolver.resolve(
           target_user_id,
           system_default.preference_key,
           filters.project_id
         ) do
      {:ok, resolved_value} ->
        %{
          id: system_default.preference_key,
          key: system_default.preference_key,
          value: resolved_value,
          category: system_default.category,
          description: system_default.description,
          data_type: system_default.data_type,
          default_value: system_default.default_value,
          source:
            determine_preference_source(
              target_user_id,
              system_default.preference_key,
              filters.project_id
            ),
          constraints: system_default.constraints,
          last_modified:
            get_preference_last_modified(
              target_user_id,
              system_default.preference_key,
              filters.project_id
            )
        }

      {:error, _} ->
        %{
          id: system_default.preference_key,
          key: system_default.preference_key,
          value: system_default.default_value,
          category: system_default.category,
          description: system_default.description,
          data_type: system_default.data_type,
          default_value: system_default.default_value,
          source: "system",
          constraints: system_default.constraints,
          last_modified: nil
        }
    end
  end

  defp paginate_preferences(preferences, filters) do
    _total = length(preferences)
    start_index = (filters.page - 1) * filters.per_page
    end_index = start_index + filters.per_page - 1

    paginated = preferences |> Enum.slice(start_index..end_index)
    {:ok, paginated}
  end

  defp validate_preference_params(params) do
    required_fields = ["preference_key", "value"]

    case check_required_fields(params, required_fields) do
      :ok ->
        validated = %{
          preference_key: params["preference_key"],
          value: params["value"],
          project_id: params["project_id"],
          reason: params["reason"],
          category: params["category"]
        }

        {:ok, validated}

      {:error, missing} ->
        {:error,
         %{
           field: :validation_error,
           message: "Missing required fields: #{Enum.join(missing, ", ")}"
         }}
    end
  end

  defp validate_update_params(params) do
    required_fields = ["value"]

    case check_required_fields(params, required_fields) do
      :ok ->
        validated = %{
          value: params["value"],
          reason: params["reason"]
        }

        {:ok, validated}

      {:error, missing} ->
        {:error,
         %{
           field: :validation_error,
           message: "Missing required fields: #{Enum.join(missing, ", ")}"
         }}
    end
  end

  defp check_required_fields(params, required_fields) do
    missing = Enum.filter(required_fields, &(is_nil(params[&1]) or params[&1] == ""))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, missing}
    end
  end

  defp create_preference(user, params) do
    if params.project_id do
      create_project_preference(user, params)
    else
      create_user_preference(user, params)
    end
  end

  defp create_user_preference(user, params) do
    attrs = %{
      user_id: user.id,
      preference_key: params.preference_key,
      value: params.value,
      category: params.category || get_preference_category(params.preference_key),
      source: :api
    }

    case UserPreference.create(attrs) do
      {:ok, preference} ->
        {:ok, build_preference_from_record(preference)}

      error ->
        error
    end
  end

  defp create_project_preference(_user, _params) do
    # TODO: Implement project preference creation
    {:error, %{field: :not_implemented, message: "Project preferences not yet implemented"}}
  end

  defp update_preference(user, preference_key, params) do
    case UserPreference.by_user_and_key(user.id, preference_key) do
      {:ok, [existing]} ->
        case UserPreference.update(existing, %{value: params.value}) do
          {:ok, updated} ->
            {:ok, build_preference_from_record(updated)}

          error ->
            error
        end

      {:ok, []} ->
        # Create new user preference
        attrs = %{
          user_id: user.id,
          preference_key: preference_key,
          value: params.value,
          category: get_preference_category(preference_key),
          source: :api
        }

        case UserPreference.create(attrs) do
          {:ok, preference} ->
            {:ok, build_preference_from_record(preference)}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp delete_preference(user, preference_key, project_id) do
    if project_id do
      delete_project_preference(user, preference_key, project_id)
    else
      delete_user_preference(user, preference_key)
    end
  end

  defp delete_user_preference(user, preference_key) do
    case UserPreference.by_user_and_key(user.id, preference_key) do
      {:ok, [preference]} ->
        UserPreference.destroy(preference)

      {:ok, []} ->
        # Already at default
        :ok

      error ->
        error
    end
  end

  defp delete_project_preference(_user, _preference_key, _project_id) do
    # TODO: Implement project preference deletion
    {:error, %{field: :not_implemented, message: "Project preferences not yet implemented"}}
  end

  defp get_preference_details(user, preference_key, project_id) do
    case SystemDefault.by_preference_key(preference_key) do
      {:ok, [system_default]} ->
        case PreferenceResolver.resolve(user.id, preference_key, project_id) do
          {:ok, resolved_value} ->
            preference = %{
              id: preference_key,
              key: preference_key,
              value: resolved_value,
              category: system_default.category,
              description: system_default.description,
              data_type: system_default.data_type,
              default_value: system_default.default_value,
              source: determine_preference_source(user.id, preference_key, project_id),
              constraints: system_default.constraints,
              last_modified: get_preference_last_modified(user.id, preference_key, project_id),
              inheritance: build_inheritance_info(user.id, preference_key, project_id)
            }

            {:ok, preference}

          error ->
            error
        end

      {:ok, []} ->
        {:error, %{field: :not_found, message: "Preference not found"}}

      error ->
        error
    end
  end

  defp validate_batch_operations(operations) do
    validated = Enum.map(operations, &validate_batch_operation/1)

    errors = Enum.filter(validated, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(validated, &elem(&1, 1))}
    else
      {:error, %{field: :validation_error, message: "Invalid operations", details: errors}}
    end
  end

  defp validate_batch_operation(operation) when is_map(operation) do
    case operation do
      %{"action" => action, "preference_key" => key}
      when action in ["create", "update", "delete"] ->
        {:ok,
         %{
           action: action,
           preference_key: key,
           value: operation["value"],
           project_id: operation["project_id"]
         }}

      _ ->
        {:error, "Invalid operation format"}
    end
  end

  defp validate_batch_operation(_), do: {:error, "Operation must be a map"}

  defp execute_batch_operations(user, operations) do
    results = Enum.map(operations, &execute_single_operation(user, &1))

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    batch_results = %{
      total: length(operations),
      successful: successful,
      failed: failed,
      results: results
    }

    {:ok, batch_results}
  end

  defp execute_single_operation(user, %{action: "create"} = operation) do
    case create_preference(user, operation) do
      {:ok, preference} ->
        {:ok, %{action: "create", key: operation.preference_key, result: preference}}

      error ->
        {:error, %{action: "create", key: operation.preference_key, error: error}}
    end
  end

  defp execute_single_operation(user, %{action: "update"} = operation) do
    case update_preference(user, operation.preference_key, operation) do
      {:ok, preference} ->
        {:ok, %{action: "update", key: operation.preference_key, result: preference}}

      error ->
        {:error, %{action: "update", key: operation.preference_key, error: error}}
    end
  end

  defp execute_single_operation(user, %{action: "delete"} = operation) do
    case delete_preference(user, operation.preference_key, operation.project_id) do
      :ok -> {:ok, %{action: "delete", key: operation.preference_key, result: "deleted"}}
      error -> {:error, %{action: "delete", key: operation.preference_key, error: error}}
    end
  end

  # Helper functions

  defp determine_preference_source(user_id, preference_key, project_id) do
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [_user_pref]} -> resolve_preference_source_type(project_id, preference_key)
      {:ok, []} -> "system"
      _ -> "unknown"
    end
  end

  defp resolve_preference_source_type(nil, _preference_key), do: "user"

  defp resolve_preference_source_type(project_id, preference_key) do
    case check_project_override(project_id, preference_key) do
      true -> "project"
      false -> "user"
    end
  end

  defp check_project_override(_project_id, _preference_key) do
    # TODO: Implement project override checking
    false
  end

  defp get_preference_last_modified(user_id, preference_key, _project_id) do
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [user_pref]} -> user_pref.updated_at
      _ -> nil
    end
  end

  defp build_inheritance_info(user_id, preference_key, project_id) do
    system_value = get_system_value(preference_key)
    user_value = get_user_value(user_id, preference_key)
    project_value = get_project_value(project_id)
    effective_value = get_effective_value(user_id, preference_key, project_id, system_value)

    %{
      system: system_value,
      user: user_value,
      project: project_value,
      effective: effective_value
    }
  end

  defp get_system_value(preference_key) do
    case SystemDefault.by_preference_key(preference_key) do
      {:ok, [default]} -> default.default_value
      _ -> nil
    end
  end

  defp get_user_value(user_id, preference_key) do
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [user_pref]} -> user_pref.value
      _ -> nil
    end
  end

  defp get_project_value(nil), do: nil

  defp get_project_value(_project_id) do
    # TODO: Implement project preference lookup
    nil
  end

  defp get_effective_value(user_id, preference_key, project_id, fallback_value) do
    case PreferenceResolver.resolve(user_id, preference_key, project_id) do
      {:ok, value} -> value
      _ -> fallback_value
    end
  end

  defp build_preference_from_record(record) do
    %{
      id: record.preference_key,
      key: record.preference_key,
      value: record.value,
      category: record.category,
      # Since we're building from a UserPreference record
      source: "user",
      last_modified: record.updated_at
    }
  end

  defp get_preference_category(key) do
    key |> String.split(".") |> hd()
  end
end
