defmodule RubberDuckWeb.Live.Components.PromptSelectionModal do
  @moduledoc """
  Modal LiveView component for prompt selection in LLM operations.

  Provides a modal interface that overlays existing LLM operation interfaces,
  allowing users to browse, search, and select saved prompts with preview
  functionality and template variable substitution support.

  Features:
  - Modal overlay for non-disruptive prompt selection
  - Full-featured prompt browser with search and filtering
  - Template variable preview and substitution interface
  - Quick insertion into LLM request fields with formatting
  """

  use Phoenix.LiveComponent

  alias RubberDuck.Prompts.Services.LlmPromptSelector
  alias RubberDuck.Prompts.Integrations.PromptVariableSubstitution

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_modal, false)
     |> assign(:selected_prompt, nil)
     |> assign(:variable_values, %{})
     |> assign(:preview_content, "")
     |> assign(:target_field, nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("open_modal", %{"target_field" => target_field}, socket) do
    socket =
      socket
      |> assign(:show_modal, true)
      |> assign(:target_field, target_field)
      |> assign(:selected_prompt, nil)
      |> assign(:variable_values, %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_modal, false)
      |> assign(:selected_prompt, nil)
      |> assign(:variable_values, %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("preview_prompt", %{"prompt_id" => prompt_id}, socket) do
    case find_prompt_by_id(prompt_id) do
      {:ok, prompt} ->
        variables = extract_template_variables(prompt.content)

        socket =
          socket
          |> assign(:selected_prompt, prompt)
          |> assign(:variable_values, initialize_variable_values(variables))
          |> assign(:preview_content, prompt.content)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Prompt not found")}
    end
  end

  @impl true
  def handle_event("update_variable", %{"variable" => variable_name, "value" => value}, socket) do
    %{variable_values: current_values, selected_prompt: prompt} = socket.assigns

    updated_values = Map.put(current_values, variable_name, value)

    # Update preview with new variable values
    case PromptVariableSubstitution.substitute_variables(prompt.content, updated_values) do
      {:ok, preview_content} ->
        socket =
          socket
          |> assign(:variable_values, updated_values)
          |> assign(:preview_content, preview_content)

        {:noreply, socket}

      {:error, _reason} ->
        # Keep original content if substitution fails
        socket = assign(socket, :variable_values, updated_values)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("insert_prompt", _params, socket) do
    %{selected_prompt: prompt, preview_content: content, target_field: target_field} =
      socket.assigns

    if prompt && target_field do
      # Send insertion event to parent LiveView
      send(self(), {:insert_prompt_content, target_field, content, prompt})

      socket =
        socket
        |> assign(:show_modal, false)
        |> assign(:selected_prompt, nil)

      {:noreply, socket}
    else
      {:noreply, assign(socket, :error, "No prompt selected or target field specified")}
    end
  end

  # Handle events from child PromptBrowserComponent
  @impl true
  def handle_info({:prompt_browser_selection, prompt}, socket) do
    variables = extract_template_variables(prompt.content)

    socket =
      socket
      |> assign(:selected_prompt, prompt)
      |> assign(:variable_values, initialize_variable_values(variables))
      |> assign(:preview_content, prompt.content)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Modal Overlay -->
    <div :if={@show_modal} class="modal-overlay" phx-click="close_modal" phx-target={@myself}>
      <div class="modal-content" phx-click-away="close_modal" phx-target={@myself}>
        <div class="modal-header">
          <h3>Select Saved Prompt</h3>
          <button class="modal-close" phx-click="close_modal" phx-target={@myself}>
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>

        <div class="modal-body">
          <!-- Left Panel: Prompt Browser -->
          <div class="prompt-browser-panel">
            <.live_component 
              module={RubberDuckWeb.Live.Components.PromptBrowserComponent}
              id="prompt-browser-modal"
              user_id={@user_id}
              project_id={@project_id}
              notify_target={self()}
            />
          </div>

          <!-- Right Panel: Prompt Preview and Variables -->
          <div :if={@selected_prompt} class="prompt-preview-panel">
            <div class="preview-header">
              <h4><%= @selected_prompt.name %></h4>
              <span class={"prompt-type-badge #{@selected_prompt.prompt_type}"}>
                <%= format_prompt_type(@selected_prompt.prompt_type) %>
              </span>
            </div>

            <div :if={@selected_prompt.description} class="prompt-description">
              <%= @selected_prompt.description %>
            </div>

            <!-- Template Variables -->
            <div :if={has_variables?(@selected_prompt.content)} class="template-variables">
              <h5>Template Variables</h5>
              <div 
                :for={{variable, _} <- extract_template_variables(@selected_prompt.content)}
                class="variable-input"
              >
                <label for={variable}><%= variable %></label>
                <input 
                  type="text" 
                  name="value"
                  value={@variable_values[variable] || ""}
                  phx-change="update_variable"
                  phx-value-variable={variable}
                  phx-target={@myself}
                  placeholder="Enter value for <%= variable %>"
                />
              </div>
            </div>

            <!-- Preview Content -->
            <div class="preview-content">
              <h5>Preview</h5>
              <div class="content-preview">
                <%= @preview_content %>
              </div>
            </div>

            <!-- Action Buttons -->
            <div class="preview-actions">
              <button 
                class="btn btn-primary"
                phx-click="insert_prompt"
                phx-target={@myself}
              >
                Insert Prompt
              </button>
              <button 
                class="btn btn-secondary"
                phx-click="close_modal"
                phx-target={@myself}
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <style>
      .modal-overlay {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0, 0, 0, 0.5);
        z-index: 1000;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .modal-content {
        background: white;
        border-radius: 0.75rem;
        width: 90vw;
        max-width: 1200px;
        height: 80vh;
        max-height: 800px;
        box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
        display: flex;
        flex-direction: column;
      }

      .modal-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 1.5rem;
        border-bottom: 1px solid #e5e7eb;
      }

      .modal-header h3 {
        margin: 0;
        font-size: 1.25rem;
        font-weight: 600;
        color: #111827;
      }

      .modal-close {
        background: none;
        border: none;
        cursor: pointer;
        color: #6b7280;
      }

      .modal-close:hover {
        color: #374151;
      }

      .modal-body {
        display: flex;
        flex: 1;
        overflow: hidden;
      }

      .prompt-browser-panel {
        flex: 1;
        border-right: 1px solid #e5e7eb;
        overflow-y: auto;
      }

      .prompt-preview-panel {
        flex: 1;
        padding: 1.5rem;
        display: flex;
        flex-direction: column;
        overflow-y: auto;
      }

      .preview-header {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        margin-bottom: 1rem;
      }

      .preview-header h4 {
        margin: 0;
        font-size: 1.125rem;
        font-weight: 600;
        color: #111827;
      }

      .prompt-description {
        margin-bottom: 1.5rem;
        color: #6b7280;
        font-size: 0.875rem;
      }

      .template-variables {
        margin-bottom: 1.5rem;
      }

      .template-variables h5 {
        margin: 0 0 0.75rem 0;
        font-weight: 600;
        color: #374151;
      }

      .variable-input {
        margin-bottom: 0.75rem;
      }

      .variable-input label {
        display: block;
        margin-bottom: 0.25rem;
        font-weight: 500;
        color: #374151;
        font-size: 0.875rem;
      }

      .variable-input input {
        width: 100%;
        padding: 0.5rem;
        border: 1px solid #d1d5db;
        border-radius: 0.375rem;
      }

      .preview-content {
        flex: 1;
        margin-bottom: 1.5rem;
      }

      .preview-content h5 {
        margin: 0 0 0.75rem 0;
        font-weight: 600;
        color: #374151;
      }

      .content-preview {
        padding: 1rem;
        background: #f9fafb;
        border: 1px solid #e5e7eb;
        border-radius: 0.375rem;
        font-family: 'Monaco', 'Consolas', monospace;
        font-size: 0.875rem;
        white-space: pre-wrap;
        max-height: 300px;
        overflow-y: auto;
      }

      .preview-actions {
        display: flex;
        gap: 0.75rem;
        justify-content: flex-end;
      }

      .btn {
        padding: 0.5rem 1rem;
        border-radius: 0.375rem;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
      }

      .btn-primary {
        background: #3b82f6;
        color: white;
        border: 1px solid #3b82f6;
      }

      .btn-primary:hover {
        background: #2563eb;
      }

      .btn-secondary {
        background: white;
        color: #374151;
        border: 1px solid #d1d5db;
      }

      .btn-secondary:hover {
        background: #f3f4f6;
      }
    </style>
    """
  end

  # Private helper functions

  defp find_prompt_by_id(prompt_id) do
    # Find prompt by ID (simplified - would use proper Ash query)
    case Prompt.read(id: prompt_id) do
      {:ok, [prompt]} -> {:ok, prompt}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_template_variables(content) do
    # Extract template variables from prompt content
    variables =
      Regex.scan(~r/\{\{(\w+)\}\}/, content, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.map(fn var -> {var, ""} end)
      |> Map.new()

    variables
  end

  defp initialize_variable_values(variables) do
    # Initialize variable values map
    Map.new(variables, fn {var, _} -> {var, ""} end)
  end

  defp has_variables?(content) do
    # Check if prompt content contains template variables
    String.contains?(content, "{{") && String.contains?(content, "}}")
  end

  defp format_prompt_type(prompt_type) do
    case prompt_type do
      :system -> "System Template"
      :project -> "Project Prompt"
      :user -> "Personal Prompt"
      _ -> "Unknown Type"
    end
  end
end
