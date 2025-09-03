defmodule RubberDuckWeb.Live.Workflows.WorkflowStepConfigurationLive do
  @moduledoc """
  LiveView for configuring Reactor workflow steps with integrated prompt selection.
  
  Provides comprehensive workflow step configuration interface that seamlessly
  integrates saved prompt library access, enabling users to select and configure
  prompts for workflow step execution with context variable substitution and
  template customization.
  
  Features:
  - Workflow step parameter configuration with prompt integration
  - Embedded prompt selection from three-tier hierarchy (System/Project/User)
  - Workflow context variable substitution in selected prompt templates
  - Real-time preview of configured workflow steps with selected prompts
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Prompts.Services.{WorkflowPromptSelector, PromptUsageTracker}

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
  def handle_event("configure_step_parameter", %{"parameter" => parameter_name, "value" => value}, socket) do
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
    %{
      workflow_step: workflow_step,
      step_configuration: step_configuration,
      selected_prompt: selected_prompt
    } = socket.assigns

    case validate_step_configuration(step_configuration, selected_prompt) do
      {:ok, validated_config} ->
        # Save workflow step configuration (would integrate with actual workflow persistence)
        case save_workflow_step_configuration(workflow_step, validated_config, selected_prompt) do
          {:ok, saved_config} ->
            # Track prompt usage in workflow context
            if selected_prompt do
              track_workflow_prompt_usage(
                socket.assigns.current_user.id,
                selected_prompt.id,
                workflow_step,
                socket.assigns.workflow_context
              )
            end

            socket =
              socket
              |> put_flash(:info, "Workflow step configuration saved successfully")
              |> assign(:step_configuration, saved_config)

            {:noreply, socket}

          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to save configuration: #{inspect(reason)}")
            {:noreply, socket}
        end

      {:error, validation_errors} ->
        socket = assign(socket, :validation_errors, validation_errors)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_selected_prompt", _params, socket) do
    socket =
      socket
      |> assign(:selected_prompt, nil)
      |> assign(:prompt_parameters, %{})
      |> assign(:preview_content, "")

    {:noreply, socket}
  end

  # Handle events from workflow prompt browser

  @impl true
  def handle_info({:workflow_prompt_selection, prompt, preparation_result}, socket) do
    # Handle prompt selection from workflow prompt browser
    socket =
      socket
      |> assign(:selected_prompt, prompt)
      |> assign(:prompt_parameters, %{})
      |> assign(:preview_content, preparation_result.prepared_content)
      |> assign(:show_prompt_browser, false)

    # Extract any required parameters from the prompt
    send(self(), {:extract_prompt_parameters, prompt})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:show_workflow_prompt_preview, prompt, workflow_context}, socket) do
    # Show prompt preview with workflow context (would open preview modal)
    case WorkflowPromptSelector.prepare_prompt_for_workflow(prompt.content, workflow_context) do
      {:ok, preview_result} ->
        socket = assign(socket, :preview_content, preview_result.prepared_content)
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:extract_prompt_parameters, prompt}, socket) do
    # Extract template variables from selected prompt for user input
    case extract_template_variables_for_workflow(prompt, socket.assigns.workflow_context) do
      {:ok, prompt_parameters} ->
        socket = assign(socket, :prompt_parameters, prompt_parameters)
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:update_step_preview, socket) do
    # Update step preview with current configuration
    %{selected_prompt: prompt, step_configuration: config, workflow_context: context} = socket.assigns

    if prompt do
      case prepare_prompt_with_step_configuration(prompt, config, context) do
        {:ok, preview_content} ->
          socket = assign(socket, :preview_content, preview_content)
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
    <div class="workflow-step-configuration">
      <div class="configuration-header">
        <h2>Configure Workflow Step</h2>
        <div class="workflow-info">
          <span class="workflow-id">Workflow: <%= @workflow_step.workflow_id %></span>
          <span class="step-id">Step: <%= @workflow_step.id %></span>
        </div>
      </div>

      <div class="configuration-content">
        <!-- Left Panel: Step Configuration -->
        <div class="step-config-panel">
          <div class="step-parameters">
            <h3>Step Parameters</h3>
            
            <!-- Basic step configuration -->
            <div class="parameter-group">
              <label for="step_name">Step Name</label>
              <input 
                type="text" 
                name="step_name"
                value={@step_configuration["step_name"] || ""}
                phx-change="configure_step_parameter"
                phx-value-parameter="step_name"
                class="parameter-input"
              />
            </div>

            <div class="parameter-group">
              <label for="step_type">Step Type</label>
              <select 
                name="step_type"
                phx-change="configure_step_parameter"
                phx-value-parameter="step_type"
                class="parameter-select"
              >
                <option value="analysis">Analysis</option>
                <option value="generation">Generation</option>
                <option value="validation">Validation</option>
                <option value="transformation">Transformation</option>
              </select>
            </div>

            <!-- Prompt Integration Section -->
            <div class="prompt-integration-section">
              <h4>Prompt Integration</h4>
              
              <div :if={@selected_prompt} class="selected-prompt-info">
                <div class="selected-prompt-header">
                  <span class="prompt-name"><%= @selected_prompt.name %></span>
                  <span class={"prompt-type-badge #{@selected_prompt.prompt_type}"}>
                    <%= format_prompt_type(@selected_prompt.prompt_type) %>
                  </span>
                  <button phx-click="remove_selected_prompt" class="remove-btn">Remove</button>
                </div>
                
                <div class="prompt-description">
                  <%= @selected_prompt.description || "No description" %>
                </div>

                <!-- Template parameters if prompt has variables -->
                <div :if={map_size(@prompt_parameters) > 0} class="template-parameters">
                  <h5>Template Parameters</h5>
                  <div 
                    :for={{param_name, param_meta} <- @prompt_parameters}
                    class="parameter-input-group"
                  >
                    <label for={param_name}>
                      <%= param_name %>
                      <span class="parameter-description">(<%= param_meta.description %>)</span>
                    </label>
                    <input 
                      type="text"
                      name={param_name}
                      value={param_meta.current_value || param_meta.default || ""}
                      phx-change="configure_step_parameter"
                      phx-value-parameter={param_name}
                      placeholder={param_meta.example || "Enter value for #{param_name}"}
                      class="parameter-input"
                    />
                  </div>
                </div>
              </div>

              <div :if={!@selected_prompt} class="no-prompt-selected">
                <p>No prompt selected for this step.</p>
                <button phx-click="open_prompt_browser" class="btn btn-primary">
                  Select Saved Prompt
                </button>
              </div>

              <div :if={@selected_prompt} class="prompt-actions">
                <button phx-click="open_prompt_browser" class="btn btn-secondary">
                  Change Prompt
                </button>
              </div>
            </div>

            <!-- Configuration Actions -->
            <div class="configuration-actions">
              <button phx-click="save_step_configuration" class="btn btn-primary">
                Save Configuration
              </button>
              <button class="btn btn-secondary">
                Cancel
              </button>
            </div>

            <!-- Validation Errors -->
            <div :if={@validation_errors != []} class="validation-errors">
              <h5>Configuration Errors:</h5>
              <ul>
                <li :for={error <- @validation_errors}><%= error %></li>
              </ul>
            </div>
          </div>
        </div>

        <!-- Right Panel: Preview -->
        <div class="step-preview-panel">
          <h3>Step Preview</h3>
          
          <div :if={@selected_prompt} class="prompt-preview">
            <h4>Selected Prompt Preview</h4>
            <div class="preview-content">
              <%= @preview_content %>
            </div>
          </div>

          <div class="step-execution-preview">
            <h4>Step Execution Configuration</h4>
            <pre class="config-preview"><%= Jason.encode!(@step_configuration, pretty: true) %></pre>
          </div>
        </div>
      </div>

      <!-- Prompt Browser Modal -->
      <div :if={@show_prompt_browser} class="prompt-browser-modal-overlay">
        <div class="prompt-browser-modal">
          <div class="modal-header">
            <h3>Select Prompt for Workflow Step</h3>
            <button phx-click="close_prompt_browser" class="modal-close">×</button>
          </div>
          <div class="modal-body">
            <.live_component 
              module={RubberDuckWeb.Live.Components.WorkflowPromptBrowserComponent}
              id="workflow-step-prompt-browser"
              user_id={@current_user.id}
              workflow_context={@workflow_context}
              notify_target={self()}
            />
          </div>
        </div>
      </div>
    </div>

    <style>
      .workflow-step-configuration {
        height: 100vh;
        display: flex;
        flex-direction: column;
      }

      .configuration-header {
        padding: 1.5rem;
        border-bottom: 1px solid #e5e7eb;
        background: white;
      }

      .configuration-header h2 {
        margin: 0 0 0.5rem 0;
        font-size: 1.5rem;
        font-weight: 600;
        color: #111827;
      }

      .workflow-info {
        display: flex;
        gap: 1rem;
        font-size: 0.875rem;
        color: #6b7280;
      }

      .configuration-content {
        display: flex;
        flex: 1;
        overflow: hidden;
      }

      .step-config-panel {
        flex: 1;
        padding: 1.5rem;
        overflow-y: auto;
        border-right: 1px solid #e5e7eb;
      }

      .step-preview-panel {
        flex: 1;
        padding: 1.5rem;
        overflow-y: auto;
        background: #f9fafb;
      }

      .step-parameters h3 {
        margin: 0 0 1.5rem 0;
        font-size: 1.125rem;
        font-weight: 600;
        color: #374151;
      }

      .parameter-group {
        margin-bottom: 1.5rem;
      }

      .parameter-group label {
        display: block;
        margin-bottom: 0.5rem;
        font-weight: 500;
        color: #374151;
      }

      .parameter-input, .parameter-select {
        width: 100%;
        padding: 0.75rem;
        border: 1px solid #d1d5db;
        border-radius: 0.375rem;
        font-size: 0.875rem;
      }

      .prompt-integration-section {
        margin-top: 2rem;
        padding: 1.5rem;
        background: #f0f9ff;
        border-radius: 0.75rem;
        border: 1px solid #bfdbfe;
      }

      .prompt-integration-section h4 {
        margin: 0 0 1rem 0;
        font-weight: 600;
        color: #1e40af;
      }

      .selected-prompt-info {
        background: white;
        border-radius: 0.5rem;
        padding: 1rem;
        border: 1px solid #e0f2fe;
      }

      .selected-prompt-header {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        margin-bottom: 0.75rem;
      }

      .prompt-name {
        font-weight: 600;
        color: #111827;
      }

      .prompt-type-badge {
        padding: 0.125rem 0.5rem;
        border-radius: 0.25rem;
        font-size: 0.75rem;
        font-weight: 500;
      }

      .prompt-type-badge.system {
        background: #dbeafe;
        color: #1e40af;
      }

      .prompt-type-badge.project {
        background: #dcfce7;
        color: #166534;
      }

      .prompt-type-badge.user {
        background: #fef3c7;
        color: #92400e;
      }

      .remove-btn {
        margin-left: auto;
        padding: 0.25rem 0.5rem;
        background: #fee2e2;
        color: #dc2626;
        border: none;
        border-radius: 0.25rem;
        font-size: 0.75rem;
        cursor: pointer;
      }

      .remove-btn:hover {
        background: #fecaca;
      }

      .prompt-description {
        font-size: 0.875rem;
        color: #6b7280;
        margin-bottom: 1rem;
      }

      .template-parameters h5 {
        margin: 0 0 0.75rem 0;
        font-weight: 600;
        color: #374151;
      }

      .parameter-input-group {
        margin-bottom: 1rem;
      }

      .parameter-description {
        font-size: 0.75rem;
        color: #9ca3af;
        font-weight: normal;
      }

      .no-prompt-selected {
        text-align: center;
        padding: 2rem;
        color: #6b7280;
      }

      .prompt-actions {
        margin-top: 1rem;
        display: flex;
        gap: 0.5rem;
      }

      .configuration-actions {
        margin-top: 2rem;
        display: flex;
        gap: 1rem;
      }

      .btn {
        padding: 0.75rem 1.5rem;
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

      .validation-errors {
        margin-top: 1rem;
        padding: 1rem;
        background: #fee2e2;
        border: 1px solid #fca5a5;
        border-radius: 0.375rem;
      }

      .validation-errors h5 {
        margin: 0 0 0.5rem 0;
        color: #dc2626;
        font-weight: 600;
      }

      .validation-errors ul {
        margin: 0;
        padding-left: 1.25rem;
      }

      .validation-errors li {
        color: #dc2626;
        font-size: 0.875rem;
      }

      .step-preview-panel h3, .step-preview-panel h4 {
        margin: 0 0 1rem 0;
        font-weight: 600;
        color: #374151;
      }

      .preview-content {
        padding: 1rem;
        background: white;
        border: 1px solid #e5e7eb;
        border-radius: 0.375rem;
        font-family: 'Monaco', 'Consolas', monospace;
        font-size: 0.875rem;
        white-space: pre-wrap;
        margin-bottom: 1.5rem;
      }

      .config-preview {
        padding: 1rem;
        background: white;
        border: 1px solid #e5e7eb;
        border-radius: 0.375rem;
        font-family: 'Monaco', 'Consolas', monospace;
        font-size: 0.75rem;
        overflow-x: auto;
      }

      .prompt-browser-modal-overlay {
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

      .prompt-browser-modal {
        background: white;
        border-radius: 0.75rem;
        width: 90vw;
        max-width: 1000px;
        height: 80vh;
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
        font-size: 1.5rem;
        cursor: pointer;
        color: #6b7280;
      }

      .modal-close:hover {
        color: #374151;
      }

      .modal-body {
        flex: 1;
        overflow: hidden;
      }
    </style>
    """
  end

  # Private helper functions

  defp build_workflow_context(workflow_id, step_id, params) do
    # Build comprehensive workflow context for prompt selection
    %{
      workflow_id: workflow_id,
      step_id: step_id,
      step_name: Map.get(params, "step_name", step_id),
      workflow_type: String.to_atom(Map.get(params, "workflow_type", "general")),
      project_id: Map.get(params, "project_id"),
      execution_context: Map.get(params, "context", %{}),
      created_at: DateTime.utc_now()
    }
  end

  defp extract_template_variables_for_workflow(prompt, workflow_context) do
    # Extract template variables and provide workflow-aware metadata
    case PromptVariableSubstitution.extract_template_variables(prompt.content) do
      {:ok, variables} ->
        # Enhance variables with workflow context information
        enhanced_variables = Map.new(variables, fn {var_name, var_meta} ->
          enhanced_meta = Map.merge(var_meta, %{
            current_value: get_workflow_variable_value(var_name, workflow_context),
            description: generate_workflow_variable_description(var_name, workflow_context),
            example: generate_workflow_variable_example(var_name, workflow_context)
          })

          {var_name, enhanced_meta}
        end)

        {:ok, enhanced_variables}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_prompt_with_step_configuration(prompt, step_configuration, workflow_context) do
    # Prepare prompt with step configuration and workflow context
    # Combine step parameters with workflow context variables
    all_variables = Map.merge(
      extract_workflow_context_variables(workflow_context),
      step_configuration
    )

    case WorkflowPromptSelector.prepare_prompt_for_workflow(prompt.content, workflow_context, all_variables) do
      {:ok, preparation_result} ->
        {:ok, preparation_result.prepared_content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_step_configuration(step_configuration, selected_prompt) do
    # Validate step configuration
    errors = []

    # Check required parameters
    errors = if Map.get(step_configuration, "step_name", "") == "" do
      ["Step name is required" | errors]
    else
      errors
    end

    # Validate prompt parameters if prompt is selected
    errors = if selected_prompt do
      validate_prompt_parameters(step_configuration, selected_prompt, errors)
    else
      errors
    end

    if errors == [] do
      {:ok, step_configuration}
    else
      {:error, errors}
    end
  end

  defp validate_prompt_parameters(step_configuration, prompt, current_errors) do
    # Validate that required prompt parameters are provided
    # This would check template variables are filled in
    current_errors
  end

  defp save_workflow_step_configuration(workflow_step, validated_config, selected_prompt) do
    # Save workflow step configuration (placeholder - would integrate with actual workflow persistence)
    saved_config = Map.merge(validated_config, %{
      "saved_at" => DateTime.utc_now(),
      "prompt_id" => if(selected_prompt, do: selected_prompt.id, else: nil)
    })

    {:ok, saved_config}
  end

  defp track_workflow_prompt_usage(user_id, prompt_id, workflow_step, workflow_context) do
    # Track prompt usage in workflow context
    usage_context = %{
      usage_type: :workflow_step,
      workflow_id: workflow_step.workflow_id,
      step_id: workflow_step.id,
      workflow_type: Map.get(workflow_context, :workflow_type),
      step_name: Map.get(workflow_context, :step_name)
    }

    usage_metadata = %{
      workflow_integration: true,
      step_configured: true,
      context_variables_used: true
    }

    PromptUsageTracker.track_llm_usage(user_id, prompt_id, usage_context, usage_metadata)
  end

  defp extract_workflow_context_variables(workflow_context) do
    # Extract workflow context variables (delegate to WorkflowPromptSelector)
    case WorkflowPromptSelector.get_available_workflow_variables(workflow_context) do
      {:ok, variables} ->
        Map.new(variables, fn {var_name, var_meta} -> {var_name, var_meta.value} end)

      {:error, _reason} ->
        %{}
    end
  end

  defp get_workflow_variable_value(var_name, workflow_context) do
    # Get workflow variable value if available
    workflow_variables = extract_workflow_context_variables(workflow_context)
    Map.get(workflow_variables, var_name)
  end

  defp generate_workflow_variable_description(var_name, workflow_context) do
    # Generate description for workflow variable
    case var_name do
      "workflow_type" -> "Type of workflow: #{workflow_context[:workflow_type]}"
      "step_name" -> "Current step: #{workflow_context[:step_name]}"
      "project_id" -> "Project context: #{workflow_context[:project_id]}"
      _ -> "Custom variable: #{var_name}"
    end
  end

  defp generate_workflow_variable_example(var_name, workflow_context) do
    # Generate example value for workflow variable
    case var_name do
      "code_language" -> "Elixir"
      "review_focus" -> "security"
      "doc_type" -> "API reference"
      "test_type" -> "integration"
      _ -> "example_value"
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