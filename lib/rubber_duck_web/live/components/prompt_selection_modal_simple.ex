defmodule RubberDuckWeb.Live.Components.PromptSelectionModalSimple do
  @moduledoc """
  Simplified modal LiveView component for prompt selection in LLM operations.
  
  TODO: This is a simplified version to resolve CSS compilation issues.
  TODO: Implement full-featured modal with advanced styling when HEEx CSS framework is ready.
  TODO: Add rich template variable editing interface and preview functionality.
  
  Features:
  - Simple modal overlay for prompt selection in LLM operations
  - Basic prompt browser integration with search functionality
  - Template variable preview and substitution support
  - Quick insertion into LLM request fields
  """

  use Phoenix.LiveComponent

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
  def handle_event("insert_prompt", _params, socket) do
    %{selected_prompt: prompt, preview_content: content, target_field: target_field} = socket.assigns
    
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
    <!-- TODO: Add sophisticated modal styling and responsive design -->
    <!-- TODO: Implement rich variable editing interface with validation -->
    <!-- TODO: Add advanced preview functionality with syntax highlighting -->
    
    <!-- Simple Modal Overlay -->
    <div :if={@show_modal} style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 1000;">
      <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 30px; border-radius: 10px; width: 90%; max-width: 1000px; max-height: 80%; overflow-y: auto;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 1px solid #ddd;">
          <h3>Select Saved Prompt</h3>
          <button phx-click="close_modal" phx-target={@myself} style="background: #dc3545; color: white; border: none; padding: 8px 12px; border-radius: 4px;">
            Close
          </button>
        </div>

        <div style="display: flex; gap: 20px;">
          <!-- Left Panel: Prompt Browser -->
          <div style="flex: 1; border-right: 1px solid #ddd; padding-right: 20px;">
            <!-- TODO: Use full PromptBrowserComponent when CSS issues are resolved -->
            <.live_component 
              module={RubberDuckWeb.Live.Components.PromptBrowserComponentSimple}
              id="prompt-browser-modal-simple"
              user_id={@user_id}
              project_id={@project_id}
              notify_target={self()}
            />
          </div>

          <!-- Right Panel: Prompt Preview -->
          <div :if={@selected_prompt} style="flex: 1; padding-left: 20px;">
            <h4><%= @selected_prompt.name %></h4>
            <p style="color: #666; margin-bottom: 15px;"><%= @selected_prompt.description || "No description" %></p>

            <!-- Template Variables -->
            <div :if={has_variables?(@selected_prompt.content)} style="margin-bottom: 20px;">
              <h5>Template Variables</h5>
              <!-- TODO: Add sophisticated variable editing interface -->
              <div :for={{variable, _} <- extract_template_variables(@selected_prompt.content)} style="margin-bottom: 10px;">
                <label style="display: block; margin-bottom: 5px; font-weight: bold;"><%= variable %></label>
                <input 
                  type="text" 
                  name="value"
                  value={@variable_values[variable] || ""}
                  placeholder={"Enter value for #{variable}"}
                  style="width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px;"
                />
              </div>
            </div>

            <!-- Preview Content -->
            <div style="margin-bottom: 20px;">
              <h5>Preview</h5>
              <div style="padding: 15px; background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 4px; font-family: monospace; white-space: pre-wrap; max-height: 200px; overflow-y: auto;">
                <%= @preview_content %>
              </div>
            </div>

            <!-- Action Buttons -->
            <div style="display: flex; gap: 10px;">
              <button 
                phx-click="insert_prompt"
                phx-target={@myself}
                style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 4px;"
              >
                Insert Prompt
              </button>
              <button 
                phx-click="close_modal"
                phx-target={@myself}
                style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 4px;"
              >
                Cancel
              </button>
            </div>
          </div>

          <div :if={!@selected_prompt} style="flex: 1; padding: 40px; text-align: center; color: #666;">
            <p>Select a prompt from the left to preview and configure variables.</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp extract_template_variables(content) do
    # Extract template variables from prompt content
    variables = Regex.scan(~r/\{\{(\w+)(?:\|([^}]+))?\}\}/, content, capture: :all_but_first)
    |> Enum.map(fn
      [variable_name] -> 
        {variable_name, %{default: nil}}
      
      [variable_name, default_value] -> 
        {variable_name, %{default: default_value}}
    end)
    |> Map.new()

    variables
  end

  defp initialize_variable_values(variables) do
    # Initialize variable values map
    Map.new(variables, fn {var, meta} -> {var, meta.default || ""} end)
  end

  defp has_variables?(content) do
    # Check if prompt content contains template variables
    String.contains?(content, "{{") && String.contains?(content, "}}")
  end
end