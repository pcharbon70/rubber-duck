defmodule RubberDuckWeb.API.TemplatesController do
  @moduledoc """
  REST API controller for preference template management.

  Provides CRUD operations for templates and template application.
  """

  use RubberDuckWeb, :controller

  alias RubberDuck.Preferences.TemplateManager

  action_fallback(RubberDuckWeb.API.FallbackController)

  @doc """
  List available templates with filtering.

  Query parameters:
  - category: Filter by template category
  - type: Filter by template type (private, team, public)  
  - search: Search term for template names/descriptions
  - page: Page number for pagination
  - per_page: Items per page (default 20, max 50)
  """
  def index(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, filters} <- parse_template_filters(params),
         {:ok, templates} <- get_templates_list(user, filters),
         {:ok, paginated} <- paginate_templates(templates, filters) do
      conn
      |> put_resp_header("x-total-count", to_string(length(templates)))
      |> put_resp_header("x-page", to_string(filters.page))
      |> put_resp_header("x-per-page", to_string(filters.per_page))
      |> render(:index, templates: paginated)
    end
  end

  @doc """
  Create a new template from user or project preferences.

  Body parameters:
  - name: Template name (required)
  - description: Template description
  - category: Template category
  - type: Template type (private, team, public)
  - source_type: "user" or "project" (default: "user")
  - source_id: User ID or project ID (defaults to current user)
  - include_categories: Array of categories to include
  """
  def create(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, validated_params} <- validate_template_creation_params(params),
         {:ok, template} <- create_template(user, validated_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/templates/#{template.template_id}")
      |> render(:show, template: template)
    end
  end

  @doc """
  Show a specific template with its preferences.
  """
  def show(conn, %{"id" => template_id}) do
    with {:ok, _user} <- get_current_user(conn),
         {:ok, template} <- get_template_details(template_id) do
      render(conn, :show, template: template)
    end
  end

  @doc """
  Update template metadata (name, description, etc.).

  Body parameters:
  - name: New template name
  - description: New template description
  - category: New template category
  """
  def update(conn, %{"id" => template_id} = params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, template} <- get_template_for_update(template_id, user),
         {:ok, validated_params} <- validate_template_update_params(params),
         {:ok, updated_template} <- update_template(template, validated_params) do
      render(conn, :show, template: updated_template)
    end
  end

  @doc """
  Delete a template.
  """
  def delete(conn, %{"id" => template_id}) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, template} <- get_template_for_deletion(template_id, user),
         :ok <- delete_template(template) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Apply a template to user or project preferences.

  Body parameters:
  - target_type: "user" or "project" (default: "user")
  - target_id: User ID or project ID (defaults to current user)
  - selective_keys: Array of preference keys to apply (optional)
  - overwrite_existing: Boolean to overwrite existing preferences (default: false)
  - dry_run: Boolean to preview changes without applying (default: false)
  """
  def apply(conn, %{"id" => template_id} = params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, validated_params} <- validate_template_application_params(params),
         {:ok, result} <- apply_template(template_id, user, validated_params) do
      conn
      |> put_status(:ok)
      |> render(:apply_result, result: result)
    end
  end

  # Private helper functions

  defp get_current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp parse_template_filters(params) do
    filters = %{
      category: params["category"],
      type: params["type"],
      search: params["search"],
      page: parse_integer(params["page"], 1),
      per_page: min(parse_integer(params["per_page"], 20), 50)
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

  defp get_templates_list(_user, filters) do
    # Mock implementation - would integrate with actual TemplateManager
    templates = [
      %{
        template_id: "template_1",
        name: "Development Setup",
        description: "Optimized settings for software development",
        category: "development",
        template_type: :public,
        created_by: "System",
        preferences: %{
          "code_quality.global.enabled" => true,
          "ml.training.enabled" => true,
          "llm.providers.primary" => "anthropic"
        },
        rating: 4.5,
        usage_count: 127,
        created_at: DateTime.add(DateTime.utc_now(), -86_400, :second),
        updated_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      },
      %{
        template_id: "template_2",
        name: "Performance Optimized",
        description: "High-performance configuration with optimized settings",
        category: "performance",
        template_type: :public,
        created_by: "System",
        preferences: %{
          "llm.providers.primary" => "openai",
          "performance.cache.enabled" => true,
          "budgeting.enabled" => false
        },
        rating: 4.2,
        usage_count: 89,
        created_at: DateTime.add(DateTime.utc_now(), -172_800, :second),
        updated_at: DateTime.add(DateTime.utc_now(), -7200, :second)
      }
    ]

    filtered_templates =
      templates
      |> filter_templates_by_category(filters.category)
      |> filter_templates_by_type(filters.type)
      |> filter_templates_by_search(filters.search)

    {:ok, filtered_templates}
  end

  defp filter_templates_by_category(templates, nil), do: templates

  defp filter_templates_by_category(templates, category) do
    Enum.filter(templates, &(&1.category == category))
  end

  defp filter_templates_by_type(templates, nil), do: templates

  defp filter_templates_by_type(templates, type) do
    Enum.filter(templates, &(to_string(&1.template_type) == type))
  end

  defp filter_templates_by_search(templates, nil), do: templates
  defp filter_templates_by_search(templates, ""), do: templates

  defp filter_templates_by_search(templates, search) do
    search = String.downcase(search)

    Enum.filter(templates, fn template ->
      String.contains?(String.downcase(template.name), search) or
        String.contains?(String.downcase(template.description), search)
    end)
  end

  defp paginate_templates(templates, filters) do
    start_index = (filters.page - 1) * filters.per_page
    end_index = start_index + filters.per_page - 1

    paginated = templates |> Enum.slice(start_index..end_index)
    {:ok, paginated}
  end

  defp validate_template_creation_params(params) do
    required_fields = ["name"]

    case check_required_fields(params, required_fields) do
      :ok ->
        validated = %{
          name: params["name"],
          description: params["description"] || "",
          category: params["category"] || "general",
          template_type: parse_template_type(params["type"]),
          source_type: params["source_type"] || "user",
          source_id: params["source_id"],
          include_categories: params["include_categories"] || []
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

  defp validate_template_update_params(params) do
    validated =
      %{
        name: params["name"],
        description: params["description"],
        category: params["category"]
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    {:ok, validated}
  end

  defp validate_template_application_params(params) do
    validated = %{
      target_type: params["target_type"] || "user",
      target_id: params["target_id"],
      selective_keys: params["selective_keys"] || [],
      overwrite_existing: params["overwrite_existing"] || false,
      dry_run: params["dry_run"] || false
    }

    {:ok, validated}
  end

  defp parse_template_type(nil), do: :private
  defp parse_template_type("private"), do: :private
  defp parse_template_type("team"), do: :team
  defp parse_template_type("public"), do: :public
  defp parse_template_type(_), do: :private

  defp check_required_fields(params, required_fields) do
    missing = Enum.filter(required_fields, &(is_nil(params[&1]) or params[&1] == ""))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, missing}
    end
  end

  defp create_template(user, params) do
    case params.source_type do
      "user" ->
        source_id = params.source_id || user.id

        TemplateManager.create_template_from_user(source_id, params.name,
          description: params.description,
          category: params.category,
          template_type: params.template_type,
          include_categories: params.include_categories
        )

      "project" ->
        if params.source_id do
          TemplateManager.create_template_from_project(params.source_id, params.name, user.id,
            description: params.description,
            category: params.category,
            template_type: params.template_type,
            include_categories: params.include_categories
          )
        else
          {:error,
           %{field: :validation_error, message: "source_id is required for project templates"}}
        end

      _ ->
        {:error,
         %{field: :validation_error, message: "Invalid source_type. Must be 'user' or 'project'"}}
    end
  end

  defp get_template_details(template_id) do
    # Mock implementation - would use actual TemplateManager.get_template/1
    templates = elem(get_templates_list(nil, %{}), 1)

    case Enum.find(templates, &(&1.template_id == template_id)) do
      nil -> {:error, %{field: :not_found, message: "Template not found"}}
      template -> {:ok, template}
    end
  end

  defp get_template_for_update(template_id, user) do
    case get_template_details(template_id) do
      {:ok, template} ->
        # Check if user can update this template (owner or admin)
        if can_update_template?(template, user) do
          {:ok, template}
        else
          {:error, :forbidden}
        end

      error ->
        error
    end
  end

  defp get_template_for_deletion(template_id, user) do
    case get_template_details(template_id) do
      {:ok, template} ->
        # Check if user can delete this template (owner or admin)
        if can_delete_template?(template, user) do
          {:ok, template}
        else
          {:error, :forbidden}
        end

      error ->
        error
    end
  end

  defp can_update_template?(_template, _user) do
    # Mock implementation - would check actual ownership/permissions
    true
  end

  defp can_delete_template?(_template, _user) do
    # Mock implementation - would check actual ownership/permissions
    true
  end

  defp update_template(template, params) do
    # Mock implementation - would use actual template update
    updated_template = Map.merge(template, params)
    {:ok, updated_template}
  end

  defp delete_template(_template) do
    # Mock implementation - would delete actual template
    :ok
  end

  defp apply_template(template_id, user, params) do
    case params.target_type do
      "user" ->
        apply_template_to_user_target(template_id, user, params)

      "project" ->
        apply_template_to_project_target(template_id, user, params)

      _ ->
        {:error,
         %{field: :validation_error, message: "Invalid target_type. Must be 'user' or 'project'"}}
    end
  end

  defp apply_template_to_user_target(template_id, user, params) do
    target_id = params.target_id || user.id

    case params.dry_run do
      true -> create_user_preview(target_id)
      _ -> execute_user_template_application(template_id, target_id, params)
    end
  end

  defp apply_template_to_project_target(template_id, user, params) do
    case params.target_id do
      nil ->
        {:error,
         %{field: :validation_error, message: "target_id is required for project templates"}}

      target_id ->
        handle_project_template_application(template_id, target_id, user, params)
    end
  end

  defp create_user_preview(target_id) do
    {:ok,
     %{
       dry_run: true,
       target_type: "user",
       target_id: target_id,
       changes_preview: [
         %{key: "example.preference", current: "value1", new: "value2", action: "update"}
       ],
       summary: %{new: 1, updated: 2, conflicts: 0}
     }}
  end

  defp execute_user_template_application(template_id, target_id, params) do
    result =
      TemplateManager.apply_template_to_user(template_id, target_id,
        selective_keys: params.selective_keys,
        overwrite_existing: params.overwrite_existing
      )

    case result do
      {:ok, application_result} ->
        {:ok,
         Map.merge(application_result, %{
           dry_run: false,
           target_type: "user",
           target_id: target_id
         })}

      error ->
        error
    end
  end

  defp handle_project_template_application(template_id, target_id, user, params) do
    case params.dry_run do
      true -> create_project_preview(target_id)
      _ -> execute_project_template_application(template_id, target_id, user, params)
    end
  end

  defp create_project_preview(target_id) do
    {:ok,
     %{
       dry_run: true,
       target_type: "project",
       target_id: target_id,
       changes_preview: [
         %{key: "example.preference", current: "value1", new: "value2", action: "update"}
       ],
       summary: %{new: 1, updated: 2, conflicts: 0}
     }}
  end

  defp execute_project_template_application(template_id, target_id, user, params) do
    result =
      TemplateManager.apply_template_to_project(template_id, target_id, user.id,
        selective_keys: params.selective_keys,
        overwrite_existing: params.overwrite_existing
      )

    case result do
      {:ok, application_result} ->
        {:ok,
         Map.merge(application_result, %{
           dry_run: false,
           target_type: "project",
           target_id: target_id
         })}

      error ->
        error
    end
  end
end
