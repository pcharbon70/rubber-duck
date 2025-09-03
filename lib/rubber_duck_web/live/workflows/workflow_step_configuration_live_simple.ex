defmodule RubberDuckWeb.Live.Workflows.WorkflowStepConfigurationLiveSimple do
  @moduledoc """
  Simplified LiveView for workflow step configuration with prompt selection.

  TODO: This is a simplified version to resolve compilation issues.
  TODO: Add complete CSS styling and advanced UI features when framework is ready.
  TODO: Implement full workflow step configuration interface with rich template editing.

  Features:
  - Basic workflow step parameter configuration with prompt integration
  - Simple prompt selection from three-tier hierarchy (System/Project/User)
  - Workflow context variable substitution in selected prompt templates
  - Basic preview of configured workflow steps with selected prompts
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Prompts.Services.{PromptUsageTracker, WorkflowPromptSelector}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:workflow_step, %{})
     |> assign(:workflow_context, %{})
     |> assign(:selected_prompt, nil)
     |> assign(:prompt_parameters, %{})
     |> assign(:show_prompt_browser, false)
     |> assign(:step_configuration, %{})
     |> assign(:validation_errors, [])
     |> assign(:preview_content, "")}
  end

  @impl true
  def handle_params(%{"workflow_id" => workflow_id, "step_id" => step_id} = params, _uri, socket) do
    # Load workflow step configuration context
    workflow_context = build_workflow_context(workflow_id, step_id, params)

    socket =
      socket
      |> assign(:workflow_context, workflow_context)
      |> assign(:workflow_step, %{id: step_id, workflow_id: workflow_id})

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_prompt_browser", _params, socket) do
    socket = assign(socket, :show_prompt_browser, true)
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_prompt_browser", _params, socket) do
    socket = assign(socket, :show_prompt_browser, false)
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "configure_step_parameter",
        %{"parameter" => parameter_name, "value" => value},
        socket
      ) do
    current_config = socket.assigns.step_configuration
    updated_config = Map.put(current_config, parameter_name, value)

    socket = assign(socket, :step_configuration, updated_config)

    # Update preview if prompt is selected
    if socket.assigns.selected_prompt do
      send(self(), :update_step_preview)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_step_configuration", _params, socket) do
    # TODO: Implement full step configuration validation and persistence
    # TODO: Add integration with actual Reactor workflow system
    # TODO: Implement comprehensive error handling and user feedback

    %{step_configuration: step_configuration, selected_prompt: selected_prompt} = socket.assigns

    case validate_step_configuration_basic(step_configuration, selected_prompt) do
      {:ok, validated_config} ->
        socket =
          put_flash(
            socket,
            :info,
            "Step configuration saved (TODO: integrate with workflow persistence)"
          )

        {:noreply, socket}

      {:error, validation_errors} ->
        socket = assign(socket, :validation_errors, validation_errors)
        {:noreply, socket}
    end
  end

  # Handle events from workflow prompt browser

  @impl true
  def handle_info({:workflow_prompt_selection, prompt, preparation_result}, socket) do
    socket =
      socket
      |> assign(:selected_prompt, prompt)
      |> assign(:preview_content, preparation_result.prepared_content)
      |> assign(:show_prompt_browser, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:update_step_preview, socket) do
    # TODO: Implement sophisticated preview with variable substitution
    %{selected_prompt: prompt, step_configuration: config, workflow_context: context} =
      socket.assigns

    if prompt do
      case WorkflowPromptSelector.prepare_prompt_for_workflow(prompt.content, context, config) do
        {:ok, preparation_result} ->
          socket = assign(socket, :preview_content, preparation_result.prepared_content)
          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- TODO: Add comprehensive workflow step configuration interface -->
    <!-- TODO: Implement rich CSS styling and responsive design -->
    <!-- TODO: Add advanced template variable editing and validation -->
    <div style="padding: 20px; border: 1px solid #ccc; margin: 10px;">
      <h2>Workflow Step Configuration</h2>
      
      <div style="margin-bottom: 20px;">
        <p>Workflow: <%= @workflow_step.workflow_id %></p>
        <p>Step: <%= @workflow_step.id %></p>
        <p :if={@workflow_context[:workflow_type]}>Type: <%= @workflow_context[:workflow_type] %></p>
      </div>

      <!-- Basic Configuration -->
      <div style="margin-bottom: 20px;">
        <label>Step Name:</label>
        <input 
          type="text" 
          name="step_name"
          value={@step_configuration["step_name"] || ""}
          phx-change="configure_step_parameter"
          phx-value-parameter="step_name"
          style="width: 100%; padding: 8px; margin: 5px 0;"
        />
      </div>

      <!-- Prompt Integration -->
      <div style="border: 1px solid #ddd; padding: 15px; margin: 10px 0; background: #f9f9f9;">
        <h3>Prompt Integration</h3>
        
        <div :if={@selected_prompt} style="border: 1px solid #bbb; padding: 10px; background: white;">
          <h4><%= @selected_prompt.name %> (<%= format_prompt_type(@selected_prompt.prompt_type) %>)</h4>
          <p><%= @selected_prompt.description || "No description" %></p>
          
          <div :if={@preview_content != ""} style="margin: 10px 0; padding: 10px; background: #f5f5f5; border: 1px solid #ccc; font-family: monospace; white-space: pre-wrap;">
            <%= @preview_content %>
          </div>
          
          <button phx-click="open_prompt_browser" style="margin: 5px; padding: 8px 15px; background: #e0e0e0;">
            Change Prompt
          </button>
        </div>

        <div :if={!@selected_prompt}>
          <p>No prompt selected for this step.</p>
          <button phx-click="open_prompt_browser" style="padding: 10px 20px; background: #007bff; color: white; border: none;">
            Select Saved Prompt
          </button>
        </div>
      </div>

      <!-- Configuration Actions -->
      <div style="margin: 20px 0;">
        <button phx-click="save_step_configuration" style="padding: 10px 20px; background: #28a745; color: white; border: none; margin-right: 10px;">
          Save Configuration
        </button>
        <button style="padding: 10px 20px; background: #6c757d; color: white; border: none;">
          Cancel
        </button>
      </div>

      <!-- Validation Errors -->
      <div :if={@validation_errors != []} style="padding: 10px; background: #ffe6e6; border: 1px solid #ff9999; margin: 10px 0;">
        <h4>Configuration Errors:</h4>
        <ul>
          <li :for={error <- @validation_errors} style="color: #d00;"><%= error %></li>
        </ul>
      </div>

      <!-- Simple Prompt Browser Modal -->
      <div :if={@show_prompt_browser} style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 1000;">
        <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 30px; border-radius: 10px; width: 80%; max-width: 800px; max-height: 80%; overflow-y: auto;">
          <h3>Select Prompt for Workflow Step</h3>
          <button phx-click="close_prompt_browser" style="float: right; background: #dc3545; color: white; border: none; padding: 5px 10px;">
            Close
          </button>
          
          <!-- TODO: Integrate full WorkflowPromptBrowserComponent when CSS issues are resolved -->
          <.live_component 
            module={RubberDuckWeb.Live.Components.WorkflowPromptBrowserComponentSimple}
            id="workflow-step-prompt-browser-simple"
            user_id={@current_user && @current_user.id}
            workflow_context={@workflow_context}
            notify_target={self()}
          />
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp build_workflow_context(workflow_id, step_id, params) do
    %{
      workflow_id: workflow_id,
      step_id: step_id,
      step_name: Map.get(params, "step_name", step_id),
      workflow_type: String.to_existing_atom(Map.get(params, "workflow_type", "general")),
      project_id: Map.get(params, "project_id"),
      created_at: DateTime.utc_now()
    }
  rescue
    ArgumentError ->
      # Handle invalid workflow_type gracefully
      %{
        workflow_id: workflow_id,
        step_id: step_id,
        step_name: Map.get(params, "step_name", step_id),
        workflow_type: :general,
        project_id: Map.get(params, "project_id"),
        created_at: DateTime.utc_now()
      }
  end

  defp validate_step_configuration_basic(step_configuration, selected_prompt) do
    # Basic validation for step configuration
    errors = []

    errors =
      if Map.get(step_configuration, "step_name", "") == "" do
        ["Step name is required" | errors]
      else
        errors
      end

    if errors == [] do
      {:ok, step_configuration}
    else
      {:error, errors}
    end
  end

  defp format_prompt_type(prompt_type) do
    case prompt_type do
      :system -> "System"
      :project -> "Project"
      :user -> "Personal"
      _ -> "Unknown"
    end
  end
end
