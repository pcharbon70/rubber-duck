defmodule RubberDuckWeb.Live.Components.PromptBrowserComponent do
  @moduledoc """
  LiveView component for browsing and selecting saved prompts in LLM operations.

  Provides an embeddable prompt browser interface that allows users to browse
  their three-tier prompt hierarchy (System/Project/User), search for relevant
  prompts, and select prompts for insertion into LLM request fields with
  template variable substitution support.

  Features:
  - Three-tier prompt browsing with hierarchical navigation
  - Real-time search with live filtering and suggestions
  - Quick access to recent and favorite prompts
  - Template variable preview and substitution
  - Performance optimized for large prompt collections
  """

  use Phoenix.LiveComponent

  alias RubberDuck.Prompts.Services.LlmPromptSelector

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:selected_tier, :all)
     |> assign(:selected_category, nil)
     |> assign(:prompts, %{})
     |> assign(:recent_prompts, [])
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  @impl true
  def update(%{user_id: user_id, project_id: project_id} = assigns, socket) do
    socket = assign(socket, assigns)

    # Load initial prompts asynchronously to avoid blocking
    send(self(), {:load_initial_prompts, user_id, project_id})

    {:ok, socket}
  end

  @impl true
  def handle_event("search_prompts", %{"search_query" => query}, socket) do
    %{user_id: user_id, project_id: project_id} = socket.assigns

    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)

    if String.length(String.trim(query)) >= 2 do
      # Perform search with debouncing
      Process.send_after(self(), {:execute_search, query, user_id, project_id}, 300)
    else
      # Reload all available prompts if search is cleared
      send(self(), {:load_initial_prompts, user_id, project_id})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_tier", %{"tier" => tier}, socket) do
    %{user_id: user_id, project_id: project_id} = socket.assigns
    selected_tier = String.to_existing_atom(tier)

    socket = assign(socket, :selected_tier, selected_tier)

    # Filter prompts by selected tier
    send(self(), {:filter_by_tier, selected_tier, user_id, project_id})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_prompt", %{"prompt_id" => prompt_id}, socket) do
    %{prompts: prompts} = socket.assigns

    # Find selected prompt across all tiers
    selected_prompt = find_prompt_by_id(prompts, prompt_id)

    case selected_prompt do
      nil ->
        {:noreply, assign(socket, :error, "Prompt not found")}

      prompt ->
        # Send event to parent LiveView with selected prompt
        send(self(), {:prompt_selected, prompt})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_recent", _params, socket) do
    %{user_id: user_id, project_id: project_id} = socket.assigns

    case LlmPromptSelector.get_recent_prompts(user_id, project_id, 10) do
      {:ok, recent_prompts} ->
        socket = assign(socket, :recent_prompts, recent_prompts)
        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to load recent prompts: #{inspect(reason)}")
        {:noreply, assign(socket, :error, "Failed to load recent prompts")}
    end
  end

  @impl true
  def handle_event("load_favorites", _params, socket) do
    %{user_id: user_id, project_id: project_id} = socket.assigns

    case LlmPromptSelector.get_favorite_prompts(user_id, project_id) do
      {:ok, favorite_prompts} ->
        socket = assign(socket, :prompts, %{favorites: favorite_prompts})
        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to load favorite prompts: #{inspect(reason)}")
        {:noreply, assign(socket, :error, "Failed to load favorite prompts")}
    end
  end

  # Handle async messages

  @impl true
  def handle_info({:load_initial_prompts, user_id, project_id}, socket) do
    case LlmPromptSelector.get_available_prompts(user_id, project_id) do
      {:ok, organized_prompts} ->
        socket =
          socket
          |> assign(:prompts, organized_prompts)
          |> assign(:loading, false)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to load initial prompts: #{inspect(reason)}")

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to load prompts")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:execute_search, query, user_id, project_id}, socket) do
    # Only execute if query hasn't changed (debouncing)
    if socket.assigns.search_query == query do
      case LlmPromptSelector.search_prompts(user_id, query, project_id) do
        {:ok, search_results} ->
          socket =
            socket
            |> assign(:prompts, %{search_results: search_results})
            |> assign(:loading, false)

          {:noreply, socket}

        {:error, reason} ->
          Logger.warning("Prompt search failed: #{inspect(reason)}")

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
  def handle_info({:filter_by_tier, tier, user_id, project_id}, socket) do
    case LlmPromptSelector.get_available_prompts(user_id, project_id) do
      {:ok, organized_prompts} ->
        filtered_prompts = filter_prompts_by_tier(organized_prompts, tier)

        socket =
          socket
          |> assign(:prompts, filtered_prompts)
          |> assign(:loading, false)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to filter prompts")}
    end
  end

  @impl true
  def handle_info({:prompt_selected, prompt}, socket) do
    # Notify parent component about prompt selection
    send(socket.assigns.notify_target, {:prompt_browser_selection, prompt})
    {:noreply, socket}
  end

  # Template rendering

  @impl true
  def render(assigns) do
    ~H"""
    <div class="prompt-browser-component">
      <!-- Search Bar -->
      <div class="prompt-search-section">
        <form phx-change="search_prompts" phx-target={@myself}>
          <input 
            type="text" 
            name="search_query" 
            value={@search_query}
            placeholder="Search your saved prompts..."
            class="w-full px-3 py-2 border rounded-md"
            phx-debounce="300"
          />
        </form>
      </div>

      <!-- Tier Selection -->
      <div class="prompt-tier-tabs">
        <button 
          phx-click="select_tier" 
          phx-value-tier="all" 
          phx-target={@myself}
          class={tier_button_class(@selected_tier, :all)}
        >
          All Prompts
        </button>
        <button 
          phx-click="select_tier" 
          phx-value-tier="user" 
          phx-target={@myself}
          class={tier_button_class(@selected_tier, :user)}
        >
          My Prompts
        </button>
        <button 
          phx-click="select_tier" 
          phx-value-tier="project" 
          phx-target={@myself}
          class={tier_button_class(@selected_tier, :project)}
        >
          Project Prompts
        </button>
        <button 
          phx-click="select_tier" 
          phx-value-tier="system" 
          phx-target={@myself}
          class={tier_button_class(@selected_tier, :system)}
        >
          System Templates
        </button>
      </div>

      <!-- Quick Access -->
      <div class="prompt-quick-access">
        <button phx-click="load_recent" phx-target={@myself} class="quick-access-btn">
          Recent Prompts
        </button>
        <button phx-click="load_favorites" phx-target={@myself} class="quick-access-btn">
          Favorites
        </button>
      </div>

      <!-- Loading State -->
      <div :if={@loading} class="loading-spinner">
        Loading prompts...
      </div>

      <!-- Error State -->
      <div :if={@error} class="error-message">
        <%= @error %>
      </div>

      <!-- Prompt Lists -->
      <div class="prompt-lists">
        <!-- System Prompts -->
        <div :if={should_show_tier?(@selected_tier, :system) and @prompts[:system_prompts]} class="prompt-tier-section">
          <h4>System Templates</h4>
          <div class="prompt-list">
            <div 
              :for={prompt <- @prompts[:system_prompts]} 
              class="prompt-item system-prompt"
              phx-click="select_prompt"
              phx-value-prompt_id={prompt.id}
              phx-target={@myself}
            >
              <div class="prompt-header">
                <span class="prompt-name"><%= prompt.name %></span>
                <span class="prompt-type-badge system">System</span>
              </div>
              <div class="prompt-description">
                <%= prompt.description || "No description" %>
              </div>
              <div class="prompt-preview">
                <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
              </div>
            </div>
          </div>
        </div>

        <!-- Project Prompts -->
        <div :if={should_show_tier?(@selected_tier, :project) and @prompts[:project_prompts]} class="prompt-tier-section">
          <h4>Project Prompts</h4>
          <div class="prompt-list">
            <div 
              :for={prompt <- @prompts[:project_prompts]} 
              class="prompt-item project-prompt"
              phx-click="select_prompt"
              phx-value-prompt_id={prompt.id}
              phx-target={@myself}
            >
              <div class="prompt-header">
                <span class="prompt-name"><%= prompt.name %></span>
                <span class="prompt-type-badge project">Project</span>
              </div>
              <div class="prompt-description">
                <%= prompt.description || "No description" %>
              </div>
              <div class="prompt-preview">
                <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
              </div>
            </div>
          </div>
        </div>

        <!-- User Prompts -->
        <div :if={should_show_tier?(@selected_tier, :user) and @prompts[:user_prompts]} class="prompt-tier-section">
          <h4>My Prompts</h4>
          <div class="prompt-list">
            <div 
              :for={prompt <- @prompts[:user_prompts]} 
              class="prompt-item user-prompt"
              phx-click="select_prompt"
              phx-value-prompt_id={prompt.id}
              phx-target={@myself}
            >
              <div class="prompt-header">
                <span class="prompt-name"><%= prompt.name %></span>
                <span class="prompt-type-badge user">Personal</span>
              </div>
              <div class="prompt-description">
                <%= prompt.description || "No description" %>
              </div>
              <div class="prompt-preview">
                <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
              </div>
            </div>
          </div>
        </div>

        <!-- Search Results -->
        <div :if={@prompts[:search_results]} class="prompt-tier-section">
          <h4>Search Results</h4>
          <div class="prompt-list">
            <div 
              :for={prompt <- @prompts[:search_results]} 
              class="prompt-item search-result"
              phx-click="select_prompt"
              phx-value-prompt_id={prompt.id}
              phx-target={@myself}
            >
              <div class="prompt-header">
                <span class="prompt-name"><%= prompt.name %></span>
                <span class={"prompt-type-badge #{prompt.prompt_type}"}><%= format_prompt_type(prompt.prompt_type) %></span>
                <span :if={prompt.relevance_score} class="relevance-score">
                  Relevance: <%= Float.round(prompt.relevance_score, 1) %>
                </span>
              </div>
              <div class="prompt-description">
                <%= prompt.description || "No description" %>
              </div>
              <div class="prompt-preview">
                <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
              </div>
            </div>
          </div>
        </div>

        <!-- Recent Prompts -->
        <div :if={@recent_prompts != []} class="prompt-tier-section recent-prompts">
          <h4>Recent Prompts</h4>
          <div class="prompt-list">
            <div 
              :for={prompt <- @recent_prompts} 
              class="prompt-item recent-prompt"
              phx-click="select_prompt"
              phx-value-prompt_id={prompt.id}
              phx-target={@myself}
            >
              <div class="prompt-header">
                <span class="prompt-name"><%= prompt.name %></span>
                <span class={"prompt-type-badge #{prompt.prompt_type}"}><%= format_prompt_type(prompt.prompt_type) %></span>
              </div>
              <div class="prompt-preview">
                <%= String.slice(prompt.content, 0, 80) %><%= if String.length(prompt.content) > 80, do: "..." %>
              </div>
            </div>
          </div>
        </div>

        <!-- Empty State -->
        <div :if={is_empty_state?(@prompts, @recent_prompts)} class="empty-state">
          <p>No prompts found. Create your first prompt in the Prompt Library.</p>
        </div>
      </div>
    </div>

    <style>
      .prompt-browser-component {
        max-height: 500px;
        overflow-y: auto;
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        background: white;
      }

      .prompt-search-section {
        padding: 1rem;
        border-bottom: 1px solid #e5e7eb;
        background: #f9fafb;
      }

      .prompt-tier-tabs {
        display: flex;
        border-bottom: 1px solid #e5e7eb;
        background: #f9fafb;
      }

      .prompt-tier-tabs button {
        flex: 1;
        padding: 0.75rem 1rem;
        border: none;
        background: transparent;
        cursor: pointer;
        font-weight: 500;
      }

      .prompt-tier-tabs button.active {
        background: white;
        border-bottom: 2px solid #3b82f6;
        color: #3b82f6;
      }

      .prompt-quick-access {
        display: flex;
        gap: 0.5rem;
        padding: 0.75rem 1rem;
        border-bottom: 1px solid #e5e7eb;
        background: #f9fafb;
      }

      .quick-access-btn {
        padding: 0.5rem 1rem;
        border: 1px solid #d1d5db;
        border-radius: 0.375rem;
        background: white;
        cursor: pointer;
        font-size: 0.875rem;
      }

      .quick-access-btn:hover {
        background: #f3f4f6;
      }

      .prompt-lists {
        padding: 1rem;
      }

      .prompt-tier-section {
        margin-bottom: 1.5rem;
      }

      .prompt-tier-section h4 {
        margin: 0 0 0.75rem 0;
        font-weight: 600;
        color: #374151;
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

      .prompt-item:hover {
        border-color: #3b82f6;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
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

      .prompt-description {
        font-size: 0.875rem;
        color: #6b7280;
        margin-bottom: 0.25rem;
      }

      .prompt-preview {
        font-size: 0.75rem;
        color: #9ca3af;
        font-family: 'Monaco', 'Consolas', monospace;
        background: #f9fafb;
        padding: 0.25rem 0.5rem;
        border-radius: 0.25rem;
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

      .empty-state {
        padding: 2rem;
        text-align: center;
        color: #6b7280;
      }
    </style>
    """
  end

  # Private helper functions

  defp find_prompt_by_id(prompts, prompt_id) do
    all_prompts =
      (prompts[:system_prompts] || []) ++
        (prompts[:project_prompts] || []) ++
        (prompts[:user_prompts] || []) ++
        (prompts[:search_results] || []) ++
        (prompts[:favorites] || [])

    Enum.find(all_prompts, fn prompt -> prompt.id == prompt_id end)
  end

  defp should_show_tier?(selected_tier, tier) do
    selected_tier == :all or selected_tier == tier
  end

  defp filter_prompts_by_tier(organized_prompts, tier) do
    case tier do
      :system -> %{system_prompts: organized_prompts[:system_prompts] || []}
      :project -> %{project_prompts: organized_prompts[:project_prompts] || []}
      :user -> %{user_prompts: organized_prompts[:user_prompts] || []}
      :all -> organized_prompts
    end
  end

  defp tier_button_class(selected_tier, tier) do
    base_classes = "tier-tab-button"
    if selected_tier == tier, do: "#{base_classes} active", else: base_classes
  end

  defp format_prompt_type(prompt_type) do
    case prompt_type do
      :system -> "System"
      :project -> "Project"
      :user -> "Personal"
      _ -> "Unknown"
    end
  end

  defp is_empty_state?(prompts, recent_prompts) do
    prompt_counts = [
      length(prompts[:system_prompts] || []),
      length(prompts[:project_prompts] || []),
      length(prompts[:user_prompts] || []),
      length(prompts[:search_results] || []),
      length(prompts[:favorites] || []),
      length(recent_prompts)
    ]

    Enum.sum(prompt_counts) == 0
  end
end
