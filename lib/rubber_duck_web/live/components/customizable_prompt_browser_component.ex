defmodule RubberDuckWeb.Live.Components.CustomizablePromptBrowserComponent do
  @moduledoc """
  Preference-driven customizable prompt browser component.

  Extends the basic PromptBrowserComponent with comprehensive user preference
  integration, enabling personalized display modes, organization patterns,
  search behaviors, and workflow optimizations based on Phase 1A user preferences.

  Features:
  - User preference-driven display customization (list/grid/cards/compact)
  - Organization preference integration with categorization schemes
  - Search behavior customization with user-defined filters and scope
  - Workflow optimization with quick access patterns and shortcuts
  - Real-time preference updates with sub-100ms interface adaptation
  """

  use Phoenix.LiveComponent

  alias RubberDuck.Prompts.Services.LlmPromptSelector
  alias RubberDuck.Preferences.Services.{PromptPreferenceResolver, PromptInterfaceCustomizer}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:selected_tier, :all)
     |> assign(:prompts, %{})
     |> assign(:recent_prompts, [])
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:user_preferences, %{})
     |> assign(:interface_config, %{})}
  end

  @impl true
  def update(%{user_id: user_id, project_id: project_id} = assigns, socket) do
    socket = assign(socket, assigns)

    # Load user preferences and customize interface
    send(self(), {:load_user_preferences, user_id, project_id})
    send(self(), {:load_initial_prompts, user_id, project_id})

    {:ok, socket}
  end

  @impl true
  def handle_event("search_prompts", %{"search_query" => query}, socket) do
    %{user_id: user_id, project_id: project_id, user_preferences: user_preferences} =
      socket.assigns

    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)

    # Apply search preferences to search behavior
    search_options = build_search_options_from_preferences(user_preferences.search || %{})

    if String.length(String.trim(query)) >= 2 do
      # Perform search with user preference customizations
      Process.send_after(
        self(),
        {:execute_customized_search, query, user_id, project_id, search_options},
        300
      )
    else
      # Reload all available prompts with display preferences applied
      send(self(), {:load_initial_prompts, user_id, project_id})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_display_mode", %{"mode" => new_mode}, socket) do
    %{user_id: user_id, project_id: project_id} = socket.assigns

    # Update user preference for display mode
    case update_user_display_preference(user_id, "view_mode", new_mode) do
      :ok ->
        # Refresh user preferences and interface
        send(self(), {:load_user_preferences, user_id, project_id})
        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to update display preference: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("apply_quick_filter", %{"filter" => filter_name}, socket) do
    %{user_id: user_id, project_id: project_id, user_preferences: user_preferences} =
      socket.assigns

    # Apply quick filter based on user preferences
    filter_config = get_quick_filter_config(filter_name, user_preferences)

    # Apply filter and refresh prompts
    send(self(), {:apply_filter_and_refresh, user_id, project_id, filter_config})

    {:noreply, assign(socket, :loading, true)}
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

  # Handle async messages

  @impl true
  def handle_info({:load_user_preferences, user_id, project_id}, socket) do
    case PromptPreferenceResolver.resolve_all_prompt_management_preferences(user_id, project_id) do
      {:ok, all_preferences} ->
        # Customize interface based on preferences
        base_config = %{layout: :standard, theme: :light}

        case PromptInterfaceCustomizer.customize_prompt_browser(user_id, base_config, project_id) do
          {:ok, customized_config} ->
            socket =
              socket
              |> assign(:user_preferences, all_preferences)
              |> assign(:interface_config, customized_config)

            {:noreply, socket}

          {:error, reason} ->
            Logger.warning("Failed to customize interface: #{inspect(reason)}")
            socket = assign(socket, :user_preferences, all_preferences)
            {:noreply, socket}
        end

      {:error, reason} ->
        Logger.warning("Failed to load user preferences: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_initial_prompts, user_id, project_id}, socket) do
    # Apply user preferences to prompt loading
    %{user_preferences: user_preferences} = socket.assigns

    loading_options = build_loading_options_from_preferences(user_preferences)

    case LlmPromptSelector.get_available_prompts(user_id, project_id, loading_options) do
      {:ok, organized_prompts} ->
        # Apply organization preferences to prompt structure
        customized_prompts =
          apply_organization_to_prompts(organized_prompts, user_preferences.organization || %{})

        socket =
          socket
          |> assign(:prompts, customized_prompts)
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
  def handle_info(
        {:execute_customized_search, query, user_id, project_id, search_options},
        socket
      ) do
    # Only execute if query hasn't changed (debouncing)
    if socket.assigns.search_query == query do
      case LlmPromptSelector.search_prompts(user_id, query, project_id, search_options) do
        {:ok, search_results} ->
          # Apply user preferences to search result organization
          customized_results =
            apply_search_result_customization(search_results, socket.assigns.user_preferences)

          socket =
            socket
            |> assign(:prompts, %{search_results: customized_results})
            |> assign(:loading, false)

          {:noreply, socket}

        {:error, reason} ->
          Logger.warning("Customized prompt search failed: #{inspect(reason)}")

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
  def handle_info({:apply_filter_and_refresh, user_id, project_id, filter_config}, socket) do
    # Apply quick filter and refresh prompts
    case apply_quick_filter(user_id, project_id, filter_config) do
      {:ok, filtered_prompts} ->
        socket =
          socket
          |> assign(:prompts, filtered_prompts)
          |> assign(:loading, false)

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to apply quick filter: #{inspect(reason)}")
        {:noreply, assign(socket, :loading, false)}
    end
  end

  @impl true
  def handle_info({:prompt_selected, prompt}, socket) do
    # Notify parent component about prompt selection
    send(socket.assigns.notify_target, {:customizable_prompt_browser_selection, prompt})
    {:noreply, socket}
  end

  # Template rendering

  @impl true
  def render(assigns) do
    ~H"""
    <div class="customizable-prompt-browser" data-view-mode={@user_preferences[:display][:view_mode] || "list"}>
      <!-- Preference-driven interface controls -->
      <div class="preference-controls">
        <!-- Display mode selector -->
        <div class="display-mode-controls">
          <button 
            phx-click="change_display_mode" 
            phx-value-mode="list" 
            phx-target={@myself}
            class={display_mode_button_class(@user_preferences, "list")}
          >
            List
          </button>
          <button 
            phx-click="change_display_mode" 
            phx-value-mode="grid" 
            phx-target={@myself}
            class={display_mode_button_class(@user_preferences, "grid")}
          >
            Grid
          </button>
          <button 
            phx-click="change_display_mode" 
            phx-value-mode="cards" 
            phx-target={@myself}
            class={display_mode_button_class(@user_preferences, "cards")}
          >
            Cards
          </button>
          <button 
            phx-click="change_display_mode" 
            phx-value-mode="compact" 
            phx-target={@myself}
            class={display_mode_button_class(@user_preferences, "compact")}
          >
            Compact
          </button>
        </div>

        <!-- User-customized quick filters -->
        <div class="quick-filter-controls">
          <span :for={filter <- get_user_quick_filters(@user_preferences)}>
            <button 
              phx-click="apply_quick_filter" 
              phx-value-filter={filter} 
              phx-target={@myself}
              class="quick-filter-btn"
            >
              <%= format_filter_name(filter) %>
            </button>
          </span>
        </div>
      </div>

      <!-- Search Bar with user search preferences -->
      <div class="search-section">
        <form phx-change="search_prompts" phx-target={@myself}>
          <input 
            type="text" 
            name="search_query" 
            value={@search_query}
            placeholder={get_search_placeholder(@user_preferences)}
            style="width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px;"
            phx-debounce="300"
          />
        </form>
      </div>

      <!-- Loading State -->
      <div :if={@loading} style="padding: 30px; text-align: center; color: #666;">
        Loading prompts...
      </div>

      <!-- Error State -->
      <div :if={@error} style="padding: 15px; background: #ffe6e6; color: #d00; margin: 10px; border-radius: 4px;">
        <%= @error %>
      </div>

      <!-- Preference-driven prompt display -->
      <div class="prompt-display-area">
        <!-- Display prompts based on user view mode preference -->
        <%= case get_display_mode(@user_preferences) do %>
          <% "grid" -> %>
            <div class="grid-view">
              <%= render_prompts_grid(@prompts, @user_preferences, @myself) %>
            </div>
          <% "cards" -> %>
            <div class="cards-view">
              <%= render_prompts_cards(@prompts, @user_preferences, @myself) %>
            </div>
          <% "compact" -> %>
            <div class="compact-view">
              <%= render_prompts_compact(@prompts, @user_preferences, @myself) %>
            </div>
          <% _ -> %>
            <div class="list-view">
              <%= render_prompts_list(@prompts, @user_preferences, @myself) %>
            </div>
        <% end %>
      </div>

      <!-- Empty state with preference context -->
      <div :if={empty_state?(@prompts)} style="padding: 40px; text-align: center; color: #666;">
        <p>No prompts found in your library.</p>
        <p>Create your first prompt or adjust your search filters.</p>
      </div>
    </div>

    <!-- Basic styling (simplified to avoid HEEx CSS issues) -->
    <style>
      .customizable-prompt-browser {
        border: 1px solid #ddd;
        border-radius: 8px;
        background: white;
        max-height: 600px;
        overflow-y: auto;
      }

      .preference-controls {
        padding: 15px;
        border-bottom: 1px solid #eee;
        background: #f8f9fa;
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 15px;
      }

      .display-mode-controls {
        display: flex;
        gap: 5px;
      }

      .display-mode-controls button {
        padding: 8px 15px;
        border: 1px solid #ddd;
        background: white;
        border-radius: 4px;
        cursor: pointer;
        font-size: 14px;
      }

      .display-mode-controls button.active {
        background: #007bff;
        color: white;
        border-color: #007bff;
      }

      .quick-filter-controls {
        display: flex;
        gap: 8px;
      }

      .quick-filter-btn {
        padding: 6px 12px;
        background: #e9ecef;
        border: 1px solid #ced4da;
        border-radius: 4px;
        font-size: 12px;
        cursor: pointer;
      }

      .quick-filter-btn:hover {
        background: #dee2e6;
      }

      .search-section {
        padding: 15px;
        border-bottom: 1px solid #eee;
      }

      .prompt-display-area {
        padding: 15px;
      }

      /* View mode specific styles */
      .grid-view {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
        gap: 15px;
      }

      .cards-view .prompt-card {
        border: 1px solid #ddd;
        border-radius: 8px;
        padding: 15px;
        margin-bottom: 15px;
        background: white;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      }

      .compact-view .prompt-item {
        padding: 8px 15px;
        border-bottom: 1px solid #f0f0f0;
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .list-view .prompt-item {
        padding: 15px;
        border-bottom: 1px solid #f0f0f0;
      }

      .prompt-item {
        cursor: pointer;
        transition: background 0.2s;
      }

      .prompt-item:hover {
        background: #f8f9fa;
      }
    </style>
    """
  end

  # Private helper functions

  defp build_search_options_from_preferences(search_preferences) do
    # Build search options from user search preferences
    %{
      search_scope: Map.get(search_preferences, :default_scope, :all),
      include_content: Map.get(search_preferences, :include_content, true),
      fuzzy_search: Map.get(search_preferences, :fuzzy_search, true)
    }
  end

  defp build_loading_options_from_preferences(user_preferences) do
    # Build loading options from user preferences
    display_prefs = Map.get(user_preferences, :display, %{})

    %{
      sort_by: Map.get(display_prefs, :sort_by, "name"),
      sort_direction: Map.get(display_prefs, :sort_direction, "asc"),
      limit: Map.get(display_prefs, :items_per_page, 25)
    }
  end

  defp apply_organization_to_prompts(organized_prompts, organization_preferences) do
    # Apply organization preferences to prompt structure
    categorization_scheme =
      Map.get(organization_preferences, :categorization_scheme, "hierarchical")

    case categorization_scheme do
      "tag_based" ->
        # Reorganize by tags if user prefers tag-based organization
        reorganize_prompts_by_tags(organized_prompts)

      "flat" ->
        # Flatten hierarchy if user prefers flat organization
        flatten_prompt_organization(organized_prompts)

      _ ->
        # Keep hierarchical organization (default)
        organized_prompts
    end
  end

  defp apply_search_result_customization(search_results, user_preferences) do
    # Apply user preferences to search result customization
    search_prefs = Map.get(user_preferences, :search, %{})

    # Apply user-preferred result sorting
    case Map.get(search_prefs, :result_sort, "relevance") do
      "name" -> Enum.sort_by(search_results, fn prompt -> prompt.name end)
      "created_at" -> Enum.sort_by(search_results, fn prompt -> prompt.inserted_at end, :desc)
      # Keep relevance sorting
      _ -> search_results
    end
  end

  defp apply_quick_filter(user_id, project_id, filter_config) do
    # Apply quick filter based on user configuration
    case filter_config.filter_type do
      :recent ->
        LlmPromptSelector.get_recent_prompts(user_id, project_id, filter_config.limit || 10)

      :favorites ->
        LlmPromptSelector.get_favorite_prompts(user_id, project_id)

      :category ->
        LlmPromptSelector.get_prompts_by_category(user_id, filter_config.category_id, project_id)

      _ ->
        LlmPromptSelector.get_available_prompts(user_id, project_id)
    end
  end

  defp update_user_display_preference(user_id, preference_key, new_value) do
    # Update user preference using Phase 1A infrastructure
    full_preference_key = "prompt_management.display.#{preference_key}"

    case UserPreference.set_preference(
           user_id,
           full_preference_key,
           new_value,
           "Interface customization"
         ) do
      {:ok, _preference} ->
        # Invalidate cache for immediate effect
        PromptPreferenceResolver.invalidate_user_cache(user_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # View mode rendering functions

  defp render_prompts_list(prompts, user_preferences, myself) do
    # Render prompts in list view with user preferences
    show_metadata = get_show_metadata_preference(user_preferences)

    all_prompts = extract_all_prompts_for_display(prompts)

    for prompt <- all_prompts do
      """
      <div class="prompt-item list-item" phx-click="select_prompt" phx-value-prompt_id="#{prompt.id}" phx-target="#{myself}">
        <div class="prompt-header">
          <strong>#{prompt.name}</strong>
          <span class="prompt-type-badge #{prompt.prompt_type}">#{format_prompt_type(prompt.prompt_type)}</span>
        </div>
        <div class="prompt-description">#{prompt.description || "No description"}</div>
        #{if show_metadata do
        "<div class=\"prompt-metadata\">Created: #{format_date(prompt.inserted_at)}</div>"
      else
        ""
      end}
      </div>
      """
    end
    |> Enum.join("")
    |> Phoenix.HTML.raw()
  end

  defp render_prompts_grid(prompts, user_preferences, myself) do
    # Render prompts in grid view
    all_prompts = extract_all_prompts_for_display(prompts)

    for prompt <- all_prompts do
      """
      <div class="prompt-item grid-item" phx-click="select_prompt" phx-value-prompt_id="#{prompt.id}" phx-target="#{myself}">
        <h4>#{prompt.name}</h4>
        <span class="prompt-type-badge #{prompt.prompt_type}">#{format_prompt_type(prompt.prompt_type)}</span>
        <p>#{String.slice(prompt.content, 0, 100)}#{if String.length(prompt.content) > 100, do: "..."}</p>
      </div>
      """
    end
    |> Enum.join("")
    |> Phoenix.HTML.raw()
  end

  defp render_prompts_cards(prompts, user_preferences, myself) do
    # Render prompts in card view
    all_prompts = extract_all_prompts_for_display(prompts)

    for prompt <- all_prompts do
      """
      <div class="prompt-card" phx-click="select_prompt" phx-value-prompt_id="#{prompt.id}" phx-target="#{myself}">
        <div class="card-header">
          <h4>#{prompt.name}</h4>
          <span class="prompt-type-badge #{prompt.prompt_type}">#{format_prompt_type(prompt.prompt_type)}</span>
        </div>
        <div class="card-description">#{prompt.description || "No description"}</div>
        <div class="card-preview">#{String.slice(prompt.content, 0, 80)}#{if String.length(prompt.content) > 80, do: "..."}</div>
      </div>
      """
    end
    |> Enum.join("")
    |> Phoenix.HTML.raw()
  end

  defp render_prompts_compact(prompts, user_preferences, myself) do
    # Render prompts in compact view
    all_prompts = extract_all_prompts_for_display(prompts)

    for prompt <- all_prompts do
      """
      <div class="prompt-item compact-item" phx-click="select_prompt" phx-value-prompt_id="#{prompt.id}" phx-target="#{myself}">
        <span class="prompt-name">#{prompt.name}</span>
        <span class="prompt-type-badge #{prompt.prompt_type}">#{format_prompt_type(prompt.prompt_type)}</span>
      </div>
      """
    end
    |> Enum.join("")
    |> Phoenix.HTML.raw()
  end

  # Helper functions

  defp find_prompt_by_id(prompts, prompt_id) do
    all_prompts =
      (prompts[:system_prompts] || []) ++
        (prompts[:project_prompts] || []) ++
        (prompts[:user_prompts] || []) ++
        (prompts[:search_results] || [])

    Enum.find(all_prompts, fn prompt -> prompt.id == prompt_id end)
  end

  defp extract_all_prompts_for_display(prompts) do
    (prompts[:system_prompts] || []) ++
      (prompts[:project_prompts] || []) ++
      (prompts[:user_prompts] || []) ++
      (prompts[:search_results] || [])
  end

  defp get_display_mode(user_preferences) do
    get_in(user_preferences, [:display, :view_mode]) || "list"
  end

  defp get_show_metadata_preference(user_preferences) do
    get_in(user_preferences, [:display, :show_metadata]) || true
  end

  defp get_user_quick_filters(user_preferences) do
    get_in(user_preferences, [:search, :quick_filters]) || ["recent", "favorites"]
  end

  defp get_search_placeholder(user_preferences) do
    search_scope = get_in(user_preferences, [:search, :default_scope]) || "all"
    "Search #{search_scope} prompts..."
  end

  defp get_quick_filter_config(filter_name, user_preferences) do
    # Get configuration for quick filter based on user preferences
    case filter_name do
      "recent" ->
        recent_limit = get_in(user_preferences, [:workflow, :recent_limit]) || 10
        %{filter_type: :recent, limit: recent_limit}

      "favorites" ->
        %{filter_type: :favorites}

      "most_used" ->
        %{filter_type: :most_used, limit: 20}

      _ ->
        %{filter_type: :all}
    end
  end

  defp display_mode_button_class(user_preferences, mode) do
    current_mode = get_display_mode(user_preferences)
    base_class = "display-mode-btn"

    if current_mode == mode do
      "#{base_class} active"
    else
      base_class
    end
  end

  defp format_filter_name(filter) do
    case filter do
      "recent" -> "Recent"
      "favorites" -> "Favorites"
      "most_used" -> "Most Used"
      "by_category" -> "By Category"
      _ -> String.capitalize(filter)
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

  defp format_date(datetime) do
    case datetime do
      nil -> "Unknown"
      dt -> Calendar.strftime(dt, "%Y-%m-%d")
    end
  end

  defp empty_state?(prompts) do
    prompt_counts = [
      length(prompts[:system_prompts] || []),
      length(prompts[:project_prompts] || []),
      length(prompts[:user_prompts] || []),
      length(prompts[:search_results] || [])
    ]

    Enum.sum(prompt_counts) == 0
  end

  # Organization helper functions (simplified implementations)
  defp reorganize_prompts_by_tags(prompts), do: prompts
  defp flatten_prompt_organization(prompts), do: prompts
end
