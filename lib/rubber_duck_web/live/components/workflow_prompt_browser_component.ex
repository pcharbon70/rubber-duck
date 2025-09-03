defmodule RubberDuckWeb.Live.Components.WorkflowPromptBrowserComponent do
  @moduledoc """
  LiveView component for browsing and selecting saved prompts in Reactor workflow contexts.
  
  Extends the PromptBrowserComponent for workflow step configuration interfaces,
  providing workflow context-aware prompt selection, variable substitution preview
  with workflow variables, and seamless integration with Reactor workflow steps.
  
  Features:
  - Workflow context-aware prompt browsing with step-specific recommendations
  - Extension of Section 6.1 PromptBrowserComponent for workflow environments  
  - Workflow variable preview and substitution with context integration
  - Performance optimized for workflow execution with minimal step configuration overhead
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
  def handle_event("search_workflow_prompts", %{"search_query" => query}, socket) do
    %{user_id: user_id, workflow_context: workflow_context} = socket.assigns
    
    socket = 
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)

    if String.length(String.trim(query)) >= 2 do
      # Perform workflow-aware search
      Process.send_after(self(), {:execute_workflow_search, query, user_id, workflow_context}, 300)
    else
      # Reload workflow-suitable prompts
      send(self(), {:load_workflow_prompts, user_id, workflow_context})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("get_step_recommendations", %{"step_type" => step_type}, socket) do
    %{user_id: user_id, workflow_context: workflow_context} = socket.assigns
    
    step_type_atom = String.to_existing_atom(step_type)
    
    # Load step-specific recommendations
    send(self(), {:load_step_recommendations, user_id, step_type_atom, workflow_context})
    
    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_event("select_workflow_prompt", %{"prompt_id" => prompt_id}, socket) do
    %{prompts: prompts, recommended_prompts: recommended_prompts, workflow_context: workflow_context} = socket.assigns
    
    # Find selected prompt across all collections
    selected_prompt = find_prompt_by_id([
      prompts[:system_prompts] || [],
      prompts[:project_prompts] || [],
      prompts[:user_prompts] || [],
      prompts[:search_results] || [],
      recommended_prompts
    ], prompt_id)
    
    case selected_prompt do
      nil ->
        {:noreply, assign(socket, :error, "Prompt not found")}

      prompt ->
        # Prepare prompt for workflow context
        case WorkflowPromptSelector.prepare_prompt_for_workflow(
          prompt.content,
          workflow_context,
          %{}  # No additional user variables yet
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

  @impl true
  def handle_event("preview_with_workflow_context", %{"prompt_id" => prompt_id}, socket) do
    %{workflow_context: workflow_context} = socket.assigns
    
    # Find and preview prompt with workflow context
    case find_prompt_by_id_across_collections(socket.assigns, prompt_id) do
      nil ->
        {:noreply, assign(socket, :error, "Prompt not found for preview")}

      prompt ->
        # Show preview with workflow variables applied
        send(self(), {:show_workflow_prompt_preview, prompt, workflow_context})
        {:noreply, socket}
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
  def handle_info({:execute_workflow_search, query, user_id, workflow_context}, socket) do
    # Only execute if query hasn't changed (debouncing)
    if socket.assigns.search_query == query do
      case WorkflowPromptSelector.search_workflow_prompts(user_id, query, workflow_context) do
        {:ok, search_results} ->
          socket =
            socket
            |> assign(:prompts, %{search_results: search_results})
            |> assign(:loading, false)

          {:noreply, socket}

        {:error, reason} ->
          Logger.warning("Workflow prompt search failed: #{inspect(reason)}")
          
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error, "Search failed")

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_step_recommendations, user_id, step_type, workflow_context}, socket) do
    case WorkflowPromptSelector.get_recommended_prompts_for_step(user_id, step_type, workflow_context) do
      {:ok, recommendations} ->
        socket =
          socket
          |> assign(:recommended_prompts, recommendations.recommended_prompts)
          |> assign(:loading, false)

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to load step recommendations: #{inspect(reason)}")
        {:noreply, assign(socket, :loading, false)}
    end
  end

  @impl true
  def handle_info({:workflow_prompt_selected, prompt, preparation_result}, socket) do
    # Notify parent component about workflow prompt selection
    send(socket.assigns.notify_target, {:workflow_prompt_selection, prompt, preparation_result})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:show_workflow_prompt_preview, prompt, workflow_context}, socket) do
    # Show prompt preview with workflow context applied (would open preview modal)
    send(socket.assigns.notify_target, {:show_workflow_prompt_preview, prompt, workflow_context})
    {:noreply, socket}
  end

  # Template rendering

  @impl true
  def render(assigns) do
    ~H"""
    <div class="workflow-prompt-browser">
      <!-- Workflow Context Info -->
      <div class="workflow-context-info">
        <span class="workflow-type-badge">
          <%= format_workflow_type(@workflow_context[:workflow_type]) %>
        </span>
        <span :if={@workflow_context[:step_name]} class="step-name">
          Step: <%= @workflow_context[:step_name] %>
        </span>
      </div>

      <!-- Search Bar with workflow context -->
      <div class="workflow-prompt-search">
        <form phx-change="search_workflow_prompts" phx-target={@myself}>
          <input 
            type="text" 
            name="search_query" 
            value={@search_query}
            placeholder="Search prompts for this workflow..."
            class="w-full px-3 py-2 border rounded-md"
            phx-debounce="300"
          />
        </form>
      </div>

      <!-- Step-specific recommendations -->
      <div class="step-recommendations">
        <h4>Recommended for this step:</h4>
        <div class="recommendation-buttons">
          <button 
            phx-click="get_step_recommendations" 
            phx-value-step_type="analysis" 
            phx-target={@myself}
            class="rec-btn"
          >
            Analysis Prompts
          </button>
          <button 
            phx-click="get_step_recommendations" 
            phx-value-step_type="generation" 
            phx-target={@myself}
            class="rec-btn"
          >
            Generation Prompts
          </button>
          <button 
            phx-click="get_step_recommendations" 
            phx-value-step_type="validation" 
            phx-target={@myself}
            class="rec-btn"
          >
            Validation Prompts
          </button>
        </div>
      </div>

      <!-- Available workflow variables -->
      <div :if={map_size(@workflow_variables) > 0} class="workflow-variables-info">
        <h5>Available Variables:</h5>
        <div class="variable-list">
          <span 
            :for={{var_name, var_meta} <- @workflow_variables} 
            class="variable-tag"
            title={var_meta.description}
          >
            {{<%= var_name %>}}
          </span>
        </div>
      </div>

      <!-- Loading State -->
      <div :if={@loading} class="loading-spinner">
        Loading workflow prompts...
      </div>

      <!-- Error State -->
      <div :if={@error} class="error-message">
        <%= @error %>
      </div>

      <!-- Recommended Prompts -->
      <div :if={@recommended_prompts != []} class="recommended-prompts-section">
        <h4>Recommended Prompts</h4>
        <div class="prompt-list">
          <div 
            :for={prompt <- @recommended_prompts} 
            class="prompt-item recommended-prompt"
            phx-click="select_workflow_prompt"
            phx-value-prompt_id={prompt.id}
            phx-target={@myself}
          >
            <div class="prompt-header">
              <span class="prompt-name"><%= prompt.name %></span>
              <span class={"prompt-type-badge #{prompt.prompt_type}"}><%= format_prompt_type(prompt.prompt_type) %></span>
              <span :if={prompt.step_relevance_score} class="relevance-score">
                Relevance: <%= Float.round(prompt.step_relevance_score, 1) %>
              </span>
            </div>
            <div class="prompt-preview">
              <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
            </div>
            <button 
              phx-click="preview_with_workflow_context"
              phx-value-prompt_id={prompt.id}
              phx-target={@myself}
              class="preview-btn"
            >
              Preview with Context
            </button>
          </div>
        </div>
      </div>

      <!-- Regular prompt browser (reuse from Section 6.1 but with workflow context) -->
      <.live_component 
        module={RubberDuckWeb.Live.Components.PromptBrowserComponent}
        id="workflow-prompt-browser"
        user_id={@user_id}
        project_id={@workflow_context[:project_id]}
        notify_target={self()}
        workflow_enhanced={true}
        workflow_context={@workflow_context}
      />
    </div>

    <style>
      .workflow-prompt-browser {
        max-height: 600px;
        overflow-y: auto;
      }

      .workflow-context-info {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.75rem 1rem;
        background: #f0f9ff;
        border-bottom: 1px solid #e0f2fe;
      }

      .workflow-type-badge {
        padding: 0.25rem 0.75rem;
        background: #3b82f6;
        color: white;
        border-radius: 1rem;
        font-size: 0.75rem;
        font-weight: 500;
      }

      .step-name {
        padding: 0.25rem 0.5rem;
        background: #e0f2fe;
        color: #0369a1;
        border-radius: 0.375rem;
        font-size: 0.75rem;
      }

      .workflow-prompt-search {
        padding: 1rem;
        border-bottom: 1px solid #e5e7eb;
        background: #f9fafb;
      }

      .step-recommendations {
        padding: 1rem;
        border-bottom: 1px solid #e5e7eb;
        background: #fefce8;
      }

      .step-recommendations h4 {
        margin: 0 0 0.75rem 0;
        font-size: 0.875rem;
        font-weight: 600;
        color: #92400e;
      }

      .recommendation-buttons {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
      }

      .rec-btn {
        padding: 0.375rem 0.75rem;
        background: #fbbf24;
        color: #92400e;
        border: none;
        border-radius: 0.375rem;
        font-size: 0.75rem;
        cursor: pointer;
        transition: background 0.2s;
      }

      .rec-btn:hover {
        background: #f59e0b;
      }

      .workflow-variables-info {
        padding: 0.75rem 1rem;
        border-bottom: 1px solid #e5e7eb;
        background: #f0fdf4;
      }

      .workflow-variables-info h5 {
        margin: 0 0 0.5rem 0;
        font-size: 0.75rem;
        font-weight: 600;
        color: #166534;
      }

      .variable-list {
        display: flex;
        gap: 0.375rem;
        flex-wrap: wrap;
      }

      .variable-tag {
        padding: 0.125rem 0.375rem;
        background: #dcfce7;
        color: #166534;
        border-radius: 0.25rem;
        font-size: 0.65rem;
        font-family: 'Monaco', 'Consolas', monospace;
        cursor: help;
      }

      .recommended-prompts-section {
        padding: 1rem;
        border-bottom: 1px solid #e5e7eb;
      }

      .recommended-prompts-section h4 {
        margin: 0 0 0.75rem 0;
        font-weight: 600;
        color: #374151;
      }

      .prompt-item.recommended-prompt {
        background: #fefce8;
        border: 1px solid #fde047;
      }

      .prompt-item.recommended-prompt:hover {
        border-color: #facc15;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
      }

      .preview-btn {
        margin-top: 0.5rem;
        padding: 0.25rem 0.5rem;
        background: #f3f4f6;
        border: 1px solid #d1d5db;
        border-radius: 0.25rem;
        font-size: 0.75rem;
        cursor: pointer;
      }

      .preview-btn:hover {
        background: #e5e7eb;
      }

      .prompt-list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .prompt-item {
        padding: 0.75rem;
        border: 1px solid #e5e7eb;
        border-radius: 0.375rem;
        cursor: pointer;
        transition: all 0.2s;
      }

      .prompt-header {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin-bottom: 0.25rem;
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

      .relevance-score {
        margin-left: auto;
        font-size: 0.75rem;
        color: #6b7280;
      }

      .prompt-preview {
        font-size: 0.75rem;
        color: #9ca3af;
        font-family: 'Monaco', 'Consolas', monospace;
        background: #f9fafb;
        padding: 0.25rem 0.5rem;
        border-radius: 0.25rem;
        margin-bottom: 0.25rem;
      }

      .loading-spinner {
        padding: 2rem;
        text-align: center;
        color: #6b7280;
      }

      .error-message {
        padding: 1rem;
        background: #fee2e2;
        color: #dc2626;
        border-radius: 0.375rem;
        margin: 1rem;
      }
    </style>
    """
  end

  # Private helper functions

  defp find_prompt_by_id(prompt_collections, prompt_id) do
    prompt_collections
    |> List.flatten()
    |> Enum.find(fn prompt -> prompt.id == prompt_id end)
  end

  defp find_prompt_by_id_across_collections(assigns, prompt_id) do
    all_prompts = (assigns.prompts[:system_prompts] || []) ++ 
                  (assigns.prompts[:project_prompts] || []) ++ 
                  (assigns.prompts[:user_prompts] || []) ++
                  (assigns.prompts[:search_results] || []) ++
                  (assigns.recommended_prompts || [])
    
    Enum.find(all_prompts, fn prompt -> prompt.id == prompt_id end)
  end

  defp format_workflow_type(workflow_type) do
    case workflow_type do
      :code_review -> "Code Review"
      :documentation -> "Documentation"
      :testing -> "Testing"
      :refactoring -> "Refactoring"
      :debugging -> "Debugging"
      _ -> "General Workflow"
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