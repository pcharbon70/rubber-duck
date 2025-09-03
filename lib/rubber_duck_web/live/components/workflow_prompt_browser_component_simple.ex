defmodule RubberDuckWeb.Live.Components.WorkflowPromptBrowserComponentSimple do
  @moduledoc """
  Simplified LiveView component for browsing saved prompts in workflow contexts.

  TODO: This is a simplified version to resolve compilation issues.
  TODO: Integrate full CSS styling and advanced features when UI framework is ready.
  TODO: Add complete workflow context awareness and variable preview functionality.

  Features:
  - Basic workflow context-aware prompt browsing
  - Simple prompt selection for workflow step configuration  
  - Workflow variable display and context integration
  - Performance optimized using Section 6.1 infrastructure
  """

  use Phoenix.LiveComponent

  alias RubberDuck.Prompts.Services.WorkflowPromptSelector

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:selected_tier, :all)
     |> assign(:prompts, %{})
     |> assign(:recommended_prompts, [])
     |> assign(:workflow_variables, %{})
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:workflow_context, %{})}
  end

  @impl true
  def update(%{user_id: user_id, workflow_context: workflow_context} = assigns, socket) do
    socket = assign(socket, assigns)

    # Load workflow-suitable prompts and context variables
    send(self(), {:load_workflow_prompts, user_id, workflow_context})
    send(self(), {:load_workflow_variables, workflow_context})

    {:ok, socket}
  end

  @impl true
  def handle_event("select_workflow_prompt", %{"prompt_id" => prompt_id}, socket) do
    %{
      prompts: prompts,
      recommended_prompts: recommended_prompts,
      workflow_context: workflow_context
    } = socket.assigns

    # Find selected prompt across all collections
    selected_prompt =
      find_prompt_by_id(
        [
          prompts[:system_prompts] || [],
          prompts[:project_prompts] || [],
          prompts[:user_prompts] || [],
          prompts[:search_results] || [],
          recommended_prompts
        ],
        prompt_id
      )

    case selected_prompt do
      nil ->
        {:noreply, assign(socket, :error, "Prompt not found")}

      prompt ->
        # Prepare prompt for workflow context
        case WorkflowPromptSelector.prepare_prompt_for_workflow(
               prompt.content,
               workflow_context,
               %{}
             ) do
          {:ok, preparation_result} ->
            # Send prepared prompt to parent component
            send(self(), {:workflow_prompt_selected, prompt, preparation_result})
            {:noreply, socket}

          {:error, reason} ->
            Logger.warning("Failed to prepare prompt for workflow: #{inspect(reason)}")
            {:noreply, assign(socket, :error, "Failed to prepare prompt for workflow")}
        end
    end
  end

  # Handle async messages

  @impl true
  def handle_info({:load_workflow_prompts, user_id, workflow_context}, socket) do
    case WorkflowPromptSelector.get_workflow_suitable_prompts(user_id, workflow_context) do
      {:ok, workflow_prompts} ->
        socket =
          socket
          |> assign(:prompts, workflow_prompts)
          |> assign(:loading, false)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to load workflow prompts: #{inspect(reason)}")

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to load workflow prompts")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_workflow_variables, workflow_context}, socket) do
    case WorkflowPromptSelector.get_available_workflow_variables(workflow_context) do
      {:ok, workflow_variables} ->
        socket = assign(socket, :workflow_variables, workflow_variables)
        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to load workflow variables: #{inspect(reason)}")
        {:noreply, assign(socket, :workflow_variables, %{})}
    end
  end

  @impl true
  def handle_info({:workflow_prompt_selected, prompt, preparation_result}, socket) do
    # Notify parent component about workflow prompt selection
    send(socket.assigns.notify_target, {:workflow_prompt_selection, prompt, preparation_result})
    {:noreply, socket}
  end

  # Template rendering

  @impl true
  def render(assigns) do
    ~H"""
    <!-- TODO: Add complete styling and advanced workflow context features -->
    <div class="workflow-prompt-browser-simple">
      <h4>Workflow Prompt Selection</h4>
      
      <div :if={@workflow_context[:workflow_type]}>
        <p>Workflow Type: <%= @workflow_context[:workflow_type] %></p>
        <p :if={@workflow_context[:step_name]}>Step: <%= @workflow_context[:step_name] %></p>
      </div>

      <div :if={@loading}>Loading workflow prompts...</div>
      <div :if={@error}><p style="color: red;"><%= @error %></p></div>

      <!-- Available Workflow Variables -->
      <div :if={map_size(@workflow_variables) > 0}>
        <h5>Available Variables:</h5>
        <p>
          <span :for={{var_name, _var_meta} <- @workflow_variables}>
            <!-- TODO: Fix template variable display syntax for HEEx -->
            [<%= var_name %>]
          </span>
        </p>
      </div>

      <!-- System Prompts -->
      <div :if={@prompts[:system_prompts] && length(@prompts[:system_prompts]) > 0}>
        <h5>System Templates</h5>
        <div :for={prompt <- @prompts[:system_prompts]}>
          <button 
            phx-click="select_workflow_prompt"
            phx-value-prompt_id={prompt.id}
            phx-target={@myself}
            style="display: block; margin: 5px 0; padding: 10px; border: 1px solid #ccc; background: #f0f9ff;"
          >
            <strong><%= prompt.name %></strong> (System)
            <br><%= prompt.description || "No description" %>
          </button>
        </div>
      </div>

      <!-- Project Prompts -->
      <div :if={@prompts[:project_prompts] && length(@prompts[:project_prompts]) > 0}>
        <h5>Project Prompts</h5>
        <div :for={prompt <- @prompts[:project_prompts]}>
          <button 
            phx-click="select_workflow_prompt"
            phx-value-prompt_id={prompt.id}
            phx-target={@myself}
            style="display: block; margin: 5px 0; padding: 10px; border: 1px solid #ccc; background: #f0fdf4;"
          >
            <strong><%= prompt.name %></strong> (Project)
            <br><%= prompt.description || "No description" %>
          </button>
        </div>
      </div>

      <!-- User Prompts -->
      <div :if={@prompts[:user_prompts] && length(@prompts[:user_prompts]) > 0}>
        <h5>My Prompts</h5>
        <div :for={prompt <- @prompts[:user_prompts]}>
          <button 
            phx-click="select_workflow_prompt"
            phx-value-prompt_id={prompt.id}
            phx-target={@myself}
            style="display: block; margin: 5px 0; padding: 10px; border: 1px solid #ccc; background: #fefce8;"
          >
            <strong><%= prompt.name %></strong> (Personal)
            <br><%= prompt.description || "No description" %>
          </button>
        </div>
      </div>

      <!-- Recommended Prompts -->
      <div :if={@recommended_prompts != []}>
        <h5>Recommended for This Step</h5>
        <div :for={prompt <- @recommended_prompts}>
          <button 
            phx-click="select_workflow_prompt"
            phx-value-prompt_id={prompt.id}
            phx-target={@myself}
            style="display: block; margin: 5px 0; padding: 10px; border: 2px solid #fbbf24; background: #fef3c7;"
          >
            <strong><%= prompt.name %></strong> (Recommended)
            <br><%= prompt.description || "No description" %>
            <br><small>Relevance: <%= if prompt.step_relevance_score, do: Float.round(prompt.step_relevance_score, 2), else: "N/A" %></small>
          </button>
        </div>
      </div>

      <div :if={is_empty_state?(@prompts, @recommended_prompts)}>
        <p>No prompts available. Create prompts in the Prompt Library.</p>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp find_prompt_by_id(prompt_collections, prompt_id) do
    prompt_collections
    |> List.flatten()
    |> Enum.find(fn prompt -> prompt.id == prompt_id end)
  end

  defp is_empty_state?(prompts, recommended_prompts) do
    prompt_counts = [
      length(prompts[:system_prompts] || []),
      length(prompts[:project_prompts] || []),
      length(prompts[:user_prompts] || []),
      length(prompts[:search_results] || []),
      length(recommended_prompts)
    ]

    Enum.sum(prompt_counts) == 0
  end
end
