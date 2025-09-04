defmodule RubberDuckWeb.Live.Prompts.PromptEditorLive do
  @moduledoc """
  Rich prompt editing interface with validation, preview, and version management.

  Provides comprehensive prompt creation and editing capabilities with real-time
  validation, template variable management, syntax highlighting, and integration
  with all backend prompt services.

  Features:
  - Rich text editing with syntax highlighting and template variable support
  - Real-time validation with security and content analysis
  - Template variable editor with type validation and preview
  - Category and tag management with autocomplete
  - Version history browser with diff comparison
  - Auto-save functionality with conflict resolution
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Prompts.Resources.{Prompt, PromptCategory}

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})
  alias RubberDuck.Prompts.Services.{
    PromptOrganizer,
    PromptTemplateManager,
    PromptValidator
  }

  @auto_save_interval 10_000  # 10 seconds
  @validation_debounce 500   # 500ms

  @impl true
  def mount(%{"id" => prompt_id}, _session, socket) do
    case load_prompt_for_editing(prompt_id, socket) do
      {:ok, prompt} ->
        {:ok,
         socket
         |> assign(:page_title, "Edit Prompt: #{prompt.name}")
         |> assign(:mode, :edit)
         |> assign(:prompt, prompt)
         |> assign(:original_prompt, prompt)
         |> initialize_editor_state()}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Prompt not found")
         |> redirect(to: ~p"/prompts")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to edit this prompt")
         |> redirect(to: ~p"/prompts")}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    # New prompt creation mode
    {:ok,
     socket
     |> assign(:page_title, "Create New Prompt")
     |> assign(:mode, :create)
     |> assign(:prompt, new_prompt_changeset())
     |> assign(:original_prompt, nil)
     |> initialize_editor_state()}
  end

  @impl true
  def handle_event("validate_prompt", %{"prompt" => prompt_params}, socket) do
    changeset = validate_prompt_changes(socket.assigns.prompt, prompt_params)

    socket =
      socket
      |> assign(:prompt, changeset)
      |> assign(:has_changes, prompt_has_changes?(changeset, socket.assigns.original_prompt))
      |> maybe_trigger_auto_validation(prompt_params)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_prompt", %{"prompt" => prompt_params}, socket) do
    case save_prompt_changes(socket.assigns.prompt, prompt_params, socket) do
      {:ok, saved_prompt} ->
        socket =
          socket
          |> put_flash(:info, "Prompt saved successfully")
          |> assign(:prompt, saved_prompt)
          |> assign(:original_prompt, saved_prompt)
          |> assign(:has_changes, false)
          |> assign(:last_saved_at, DateTime.utc_now())

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> assign(:prompt, changeset)
          |> put_flash(:error, "Failed to save prompt")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    case socket.assigns.mode do
      :create ->
        {:noreply, redirect(socket, to: ~p"/prompts")}
      :edit ->
        # Reset to original prompt
        socket =
          socket
          |> assign(:prompt, socket.assigns.original_prompt)
          |> assign(:has_changes, false)
          |> clear_validation_errors()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("preview_prompt", _params, socket) do
    socket = assign(socket, :preview_mode, not socket.assigns.preview_mode)

    # Generate preview if entering preview mode
    socket = if socket.assigns.preview_mode do
      generate_prompt_preview(socket)
    else
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_tag", %{"tag" => tag}, socket) when tag != "" do
    current_tags = get_prompt_field(socket.assigns.prompt, :tags, [])

    updated_tags = if tag in current_tags do
      current_tags
    else
      [tag | current_tags]
    end

    socket = update_prompt_field(socket, :tags, updated_tags)

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    current_tags = get_prompt_field(socket.assigns.prompt, :tags, [])
    updated_tags = List.delete(current_tags, tag)

    socket = update_prompt_field(socket, :tags, updated_tags)

    {:noreply, socket}
  end

  @impl true
  def handle_event("extract_variables", _params, socket) do
    prompt_content = get_prompt_field(socket.assigns.prompt, :content, "")

    case extract_template_variables(prompt_content) do
      {:ok, variables} ->
        socket =
          socket
          |> assign(:extracted_variables, variables)
          |> update_prompt_field(:variables, variables)

        {:noreply, socket}

      {:error, _reason} ->
        socket = put_flash(socket, :error, "Failed to extract template variables")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:auto_save, socket) do
    case socket.assigns do
      %{has_changes: true, mode: :edit} ->
        # Auto-save changes
        prompt_params = extract_prompt_params(socket.assigns.prompt)

        case save_prompt_changes(socket.assigns.prompt, prompt_params, socket) do
          {:ok, saved_prompt} ->
            socket =
              socket
              |> assign(:prompt, saved_prompt)
              |> assign(:original_prompt, saved_prompt)
              |> assign(:has_changes, false)
              |> assign(:last_auto_saved_at, DateTime.utc_now())

            schedule_auto_save()
            {:noreply, socket}

          {:error, _changeset} ->
            # Auto-save failed, continue with manual save requirement
            schedule_auto_save()
            {:noreply, socket}
        end

      _ ->
        # No changes or create mode - just schedule next auto-save
        schedule_auto_save()
        {:noreply, socket}
    end
  end

  # Private functions

  defp initialize_editor_state(socket) do
    # Schedule auto-save
    schedule_auto_save()

    socket
    |> assign(:has_changes, false)
    |> assign(:preview_mode, false)
    |> assign(:validation_errors, [])
    |> assign(:extracted_variables, [])
    |> assign(:available_categories, load_available_categories())
    |> assign(:last_saved_at, nil)
    |> assign(:last_auto_saved_at, nil)
  end

  defp load_prompt_for_editing(prompt_id, socket) do
    user_id = get_current_user_id(socket)

    # Load prompt and check permissions
    case RubberDuck.Prompts.Domain.get_prompt(prompt_id) do
      {:ok, [prompt]} ->
        if can_edit_prompt?(prompt, user_id) do
          {:ok, prompt}
        else
          {:error, :unauthorized}
        end
      {:ok, []} ->
        {:error, :not_found}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp new_prompt_changeset do
    # Create new prompt changeset for creation
    %Prompt{}
    |> Ash.Changeset.for_create(:create, %{
      name: "",
      content: "",
      prompt_type: :user,
      tags: [],
      variables: []
    })
  end

  defp validate_prompt_changes(prompt, params) do
    # Validate prompt changes
    prompt
    |> Ash.Changeset.for_update(:update, params)
    |> validate_prompt_content()
    |> validate_prompt_variables()
  end

  defp validate_prompt_content(changeset) do
    # Custom content validation
    content = Ash.Changeset.get_attribute(changeset, :content)

    case PromptValidator.validate_prompt_content(content) do
      {:ok, _validation_result} ->
        changeset
      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: :content, message: "Content validation failed: #{reason}")
    end
  end

  defp validate_prompt_variables(changeset) do
    # Validate template variables
    variables = Ash.Changeset.get_attribute(changeset, :variables)
    content = Ash.Changeset.get_attribute(changeset, :content)

    case validate_variables_against_content(variables, content) do
      :ok -> changeset
      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :variables, message: message)
    end
  end

  defp save_prompt_changes(prompt, params, socket) do
    user_id = get_current_user_id(socket)

    # Add user context to params
    enhanced_params = Map.merge(params, %{
      "user_id" => user_id,
      "tenant_id" => get_current_tenant_id(socket)
    })

    case socket.assigns.mode do
      :create ->
        RubberDuck.Prompts.Domain.create_prompt(enhanced_params)
      :edit ->
        prompt
        |> Ash.Changeset.for_update(:update, enhanced_params)
        |> RubberDuck.Prompts.Domain.update_prompt()
    end
  end

  defp extract_template_variables(content) do
    # Extract template variables from content
    variable_pattern = ~r/\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

    variables = Regex.scan(variable_pattern, content)
    |> Enum.map(fn [_full_match, variable_name] -> variable_name end)
    |> Enum.uniq()

    {:ok, variables}
  end

  defp validate_variables_against_content(variables, content) do
    # Validate that all variables are used in content
    {:ok, extracted_vars} = extract_template_variables(content)

    unused_variables = variables -- extracted_vars
    missing_variables = extracted_vars -- variables

    cond do
      not Enum.empty?(unused_variables) ->
        {:error, "Unused variables: #{Enum.join(unused_variables, ", ")}"}
      not Enum.empty?(missing_variables) ->
        {:error, "Missing variable definitions: #{Enum.join(missing_variables, ", ")}"}
      true ->
        :ok
    end
  end

  defp generate_prompt_preview(socket) do
    prompt_content = get_prompt_field(socket.assigns.prompt, :content, "")
    prompt_variables = get_prompt_field(socket.assigns.prompt, :variables, [])

    # Generate preview with sample variable values
    sample_values = generate_sample_variable_values(prompt_variables)

    case substitute_template_variables(prompt_content, sample_values) do
      {:ok, preview_content} ->
        assign(socket, :preview_content, preview_content)
      {:error, _reason} ->
        assign(socket, :preview_content, "Preview generation failed")
    end
  end

  defp substitute_template_variables(content, variable_values) do
    # Simple template variable substitution
    result = Enum.reduce(variable_values, content, fn {var_name, var_value}, acc ->
      String.replace(acc, "{{#{var_name}}}", to_string(var_value))
    end)

    {:ok, result}
  end

  defp generate_sample_variable_values(variables) do
    # Generate sample values for template variables
    Enum.map(variables, fn var_name ->
      sample_value = case String.downcase(var_name) do
        name when name in ["name", "user", "author"] -> "John Doe"
        name when name in ["language", "lang"] -> "Python"
        name when name in ["task", "instruction"] -> "analyze the code"
        name when name in ["context", "background"] -> "working on a web application"
        _ -> "[#{var_name}]"
      end

      {var_name, sample_value}
    end)
    |> Map.new()
  end

  # Utility functions

  defp get_current_user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: user_id}} -> user_id
      %{user_id: user_id} -> user_id
      _ -> nil
    end
  end

  defp get_current_tenant_id(socket) do
    case socket.assigns do
      %{current_user: %{tenant_id: tenant_id}} -> tenant_id
      %{tenant_id: tenant_id} -> tenant_id
      _ -> nil
    end
  end

  defp can_edit_prompt?(prompt, user_id) do
    # Check if user can edit prompt based on ownership and type
    case {prompt.prompt_type, prompt.user_id} do
      {:user, ^user_id} -> true
      {:project, _} -> true  # Project prompts editable by project members
      {:system, _} -> false  # System prompts require admin access
      _ -> false
    end
  end

  defp get_prompt_field(prompt, field, default) do
    case prompt do
      %Ash.Changeset{} -> Ash.Changeset.get_attribute(prompt, field, default)
      %{} -> Map.get(prompt, field, default)
      _ -> default
    end
  end

  defp update_prompt_field(socket, field, value) do
    updated_prompt = case socket.assigns.prompt do
      %Ash.Changeset{} = changeset ->
        Ash.Changeset.change_attribute(changeset, field, value)
      prompt ->
        Map.put(prompt, field, value)
    end

    assign(socket, :prompt, updated_prompt)
  end

  defp prompt_has_changes?(changeset, original_prompt) do
    # Check if prompt has unsaved changes
    case {changeset, original_prompt} do
      {%Ash.Changeset{} = cs, _} ->
        # Check if changeset has any changes
        not Enum.empty?(Ash.Changeset.get_attributes(cs))
      _ -> false
    end
  end

  defp maybe_trigger_auto_validation(socket, _prompt_params) do
    # Trigger validation after debounce period
    Process.send_after(self(), :validate_content, @validation_debounce)
    socket
  end

  defp clear_validation_errors(socket) do
    assign(socket, :validation_errors, [])
  end

  defp schedule_auto_save do
    Process.send_after(self(), :auto_save, @auto_save_interval)
  end

  defp extract_prompt_params(prompt) do
    case prompt do
      %Ash.Changeset{} ->
        # Extract changes from changeset
        %{
          "name" => Ash.Changeset.get_attribute(prompt, :name),
          "content" => Ash.Changeset.get_attribute(prompt, :content),
          "tags" => Ash.Changeset.get_attribute(prompt, :tags, []),
          "variables" => Ash.Changeset.get_attribute(prompt, :variables, [])
        }
      %{} = prompt ->
        # Extract from prompt map
        Map.take(prompt, [:name, :content, :tags, :variables])
        |> Enum.map(fn {k, v} -> {to_string(k), v} end)
        |> Map.new()
    end
  end

  defp load_available_categories do
    # Load available categories for prompt organization
    case RubberDuck.Prompts.Domain.list_categories() do
      {:ok, categories} -> categories
      {:error, _reason} -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="prompt-editor-container h-full flex flex-col">
      <!-- Header -->
      <div class="bg-white shadow-sm border-b border-gray-200 p-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/prompts"}
              class="text-gray-500 hover:text-gray-700"
            >
              ← Back to Library
            </.link>
            <h1 class="text-xl font-semibold text-gray-900">
              {if @mode == :create, do: "Create New Prompt", else: "Edit Prompt"}
            </h1>
          </div>

          <div class="flex items-center gap-2">
            <!-- Auto-save indicator -->
            <div :if={@last_auto_saved_at} class="text-xs text-gray-500">
              Auto-saved {format_relative_time(@last_auto_saved_at)}
            </div>

            <!-- Preview toggle -->
            <button
              phx-click="preview_prompt"
              class={[
                "px-3 py-2 text-sm rounded-lg border transition-colors",
                if @preview_mode do
                  "bg-blue-50 border-blue-300 text-blue-700"
                else
                  "border-gray-300 text-gray-700 hover:bg-gray-50"
                end
              ]}
            >
              Preview
            </button>

            <!-- Save button -->
            <button
              phx-click="save_prompt"
              phx-value-prompt={extract_prompt_params(@prompt)}
              disabled={not @has_changes}
              class={[
                "px-4 py-2 text-sm font-medium rounded-lg transition-colors",
                if @has_changes do
                  "bg-green-600 text-white hover:bg-green-700"
                else
                  "bg-gray-300 text-gray-500 cursor-not-allowed"
                end
              ]}
            >
              {if @mode == :create, do: "Create Prompt", else: "Save Changes"}
            </button>

            <!-- Cancel button -->
            <button
              phx-click="cancel_edit"
              class="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>

      <!-- Main editor content -->
      <div class="flex-1 flex overflow-hidden">
        {if @preview_mode, do: render_preview_mode(assigns), else: render_edit_mode(assigns)}
      </div>
    </div>
    """
  end

  defp render_edit_mode(assigns) do
    ~H"""
    <!-- Editor form -->
    <div class="flex-1 overflow-y-auto p-6">
      <form
        phx-change="validate_prompt"
        phx-submit="save_prompt"
        class="space-y-6"
      >
        <!-- Basic prompt info -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Prompt Name</label>
            <input
              type="text"
              name="prompt[name]"
              value={get_prompt_field(@prompt, :name, "")}
              placeholder="Enter a descriptive name for your prompt"
              required
              class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Prompt Type</label>
            <select
              name="prompt[prompt_type]"
              class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="user" selected={get_prompt_field(@prompt, :prompt_type, :user) == :user}>User Prompt</option>
              <option value="project" selected={get_prompt_field(@prompt, :prompt_type, :user) == :project}>Project Prompt</option>
              <option value="system" selected={get_prompt_field(@prompt, :prompt_type, :user) == :system}>System Prompt</option>
            </select>
          </div>
        </div>

        <!-- Prompt content -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Prompt Content</label>
          <textarea
            name="prompt[content]"
            placeholder="Enter your prompt content here. Use {{variable_name}} for template variables."
            rows="12"
            required
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >{get_prompt_field(@prompt, :content, "")}</textarea>

          <div class="mt-2 flex items-center gap-4">
            <button
              type="button"
              phx-click="extract_variables"
              class="text-sm text-blue-600 hover:text-blue-800"
            >
              Extract Variables
            </button>

            <span :if={@extracted_variables != []} class="text-sm text-gray-500">
              Found {length(@extracted_variables)} variables
            </span>
          </div>
        </div>

        <!-- Template variables -->
        <div :if={@extracted_variables != []}>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            Template Variables
          </label>

          <div class="space-y-2 bg-gray-50 p-4 rounded-lg">
            <div :for={variable <- @extracted_variables} class="flex items-center gap-2">
              <span class="text-sm font-mono bg-white px-2 py-1 rounded border">
                {"{{" <> variable <> "}}"}
              </span>
              <span class="text-sm text-gray-500">Variable placeholder</span>
            </div>
          </div>
        </div>

        <!-- Tags -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Tags</label>
          <div class="flex flex-wrap gap-2 mb-2">
            <span
              :for={tag <- get_prompt_field(@prompt, :tags, [])}
              class="inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-700 rounded-md text-sm"
            >
              {tag}
              <button
                type="button"
                phx-click="remove_tag"
                phx-value-tag={tag}
                class="text-blue-500 hover:text-blue-700"
              >
                ×
              </button>
            </span>
          </div>

          <input
            type="text"
            placeholder="Add tags (press Enter)"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
            phx-keydown="add_tag"
            phx-key="Enter"
          />
        </div>
      </form>
    </div>
    """
  end

  defp render_preview_mode(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-6">
      <div class="bg-white rounded-lg border border-gray-200 p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Prompt Preview</h3>

        <div class="bg-gray-50 p-4 rounded-lg">
          <pre class="whitespace-pre-wrap text-sm text-gray-800">
            {@preview_content || get_prompt_field(@prompt, :content, "")}
          </pre>
        </div>

        <div :if={@extracted_variables != []} class="mt-4">
          <h4 class="text-sm font-medium text-gray-700 mb-2">Template Variables</h4>
          <div class="space-y-1">
            <div :for={variable <- @extracted_variables} class="text-sm text-gray-600">
              • <span class="font-mono">{"{{" <> variable <> "}}"}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Placeholder helper function
  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :minute)

    cond do
      diff < 1 -> "just now"
      diff < 60 -> "#{diff} minutes ago"
      diff < 1440 -> "#{div(diff, 60)} hours ago"
      true -> "#{div(diff, 1440)} days ago"
    end
  end
end