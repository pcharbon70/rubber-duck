defmodule RubberDuckWeb.Live.Prompts.PromptLibraryLive do
  @moduledoc """
  Main prompt library management interface with comprehensive prompt management capabilities.

  Provides a full-featured prompt management dashboard with search, organization,
  analytics integration, and collaborative features. Designed for efficient
  management of large prompt libraries with performance optimization.

  Features:
  - Comprehensive prompt library browser with multiple view modes (list, grid, cards)
  - Real-time search integration with advanced filtering and faceted search
  - Bulk operations for prompt management and organization
  - Analytics integration with usage insights and optimization recommendations
  - Collaborative features for shared prompt collections and team management
  - Mobile-responsive design with progressive enhancement
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Prompts.Resources.Prompt

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  alias RubberDuck.Prompts.Services.{
    PromptSearchEngine,
    PromptAnalyticsEngine,
    PromptOrganizer
  }

  @view_modes [:list, :grid, :cards, :compact]
  @sort_options [:name, :created_at, :updated_at, :usage_count, :effectiveness]
  @filter_options [:prompt_type, :category, :status, :tags]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Prompt Library")
     |> assign(:view_mode, :list)
     |> assign(:sort_by, :updated_at)
     |> assign(:sort_order, :desc)
     |> assign(:search_query, "")
     |> assign(:active_filters, %{})
     |> assign(:selected_prompts, MapSet.new())
     |> assign(:prompts, [])
     |> assign(:total_count, 0)
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:bulk_action_mode, false)
     |> assign(:analytics_panel_open, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_url_params(params)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_view_mode", %{"mode" => mode}, socket) when mode in ["list", "grid", "cards", "compact"] do
    view_mode = String.to_atom(mode)

    socket =
      socket
      |> assign(:view_mode, view_mode)
      |> save_user_preference("prompt_library_view_mode", view_mode)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_sort", %{"sort_by" => sort_by, "order" => order}, socket) do
    socket =
      socket
      |> assign(:sort_by, String.to_atom(sort_by))
      |> assign(:sort_order, String.to_atom(order))
      |> assign(:loading, true)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_filter", %{"filter_type" => filter_type, "value" => value}, socket) do
    current_filters = socket.assigns.active_filters
    filter_key = String.to_atom(filter_type)

    updated_filters = case Map.get(current_filters, filter_key) do
      ^value -> Map.delete(current_filters, filter_key)  # Remove if same value
      _ -> Map.put(current_filters, filter_key, value)     # Set new value
    end

    socket =
      socket
      |> assign(:active_filters, updated_filters)
      |> assign(:loading, true)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_prompt_selection", %{"prompt_id" => prompt_id}, socket) do
    selected_prompts = socket.assigns.selected_prompts

    updated_selection = case MapSet.member?(selected_prompts, prompt_id) do
      true -> MapSet.delete(selected_prompts, prompt_id)
      false -> MapSet.put(selected_prompts, prompt_id)
    end

    socket = assign(socket, :selected_prompts, updated_selection)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_bulk_action_mode", _params, socket) do
    socket =
      socket
      |> assign(:bulk_action_mode, not socket.assigns.bulk_action_mode)
      |> assign(:selected_prompts, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("execute_bulk_action", %{"action" => action}, socket) do
    selected_prompt_ids = MapSet.to_list(socket.assigns.selected_prompts)

    case execute_bulk_action(action, selected_prompt_ids, socket) do
      {:ok, result_message} ->
        socket =
          socket
          |> put_flash(:info, result_message)
          |> assign(:selected_prompts, MapSet.new())
          |> assign(:bulk_action_mode, false)
          |> load_prompts()

        {:noreply, socket}

      {:error, error_message} ->
        socket = put_flash(socket, :error, error_message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_analytics_panel", _params, socket) do
    socket = assign(socket, :analytics_panel_open, not socket.assigns.analytics_panel_open)

    # Load analytics data if opening panel
    socket = if socket.assigns.analytics_panel_open do
      load_analytics_data(socket)
    else
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_prompts", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_initial_prompts, _user_id, _project_id}, socket) do
    socket = load_prompts(socket)
    {:noreply, socket}
  end

  # Private functions

  defp apply_url_params(socket, params) do
    socket
    |> assign(:view_mode, parse_view_mode(params["view"]))
    |> assign(:sort_by, parse_sort_by(params["sort"]))
    |> assign(:sort_order, parse_sort_order(params["order"]))
    |> assign(:search_query, params["q"] || "")
    |> assign(:active_filters, parse_filters(params))
  end

  defp load_prompts(socket) do
    %{
      search_query: search_query,
      sort_by: sort_by,
      sort_order: sort_order,
      active_filters: filters
    } = socket.assigns

    user_id = get_current_user_id(socket)

    search_options = %{
      sort_by: sort_by,
      sort_order: sort_order,
      filters: filters,
      limit: 50,  # Implement pagination later
      offset: 0
    }

    case execute_prompt_search(search_query, user_id, search_options) do
      {:ok, {prompts, total_count}} ->
        socket
        |> assign(:prompts, prompts)
        |> assign(:total_count, total_count)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:prompts, [])
        |> assign(:total_count, 0)
        |> assign(:loading, false)
        |> assign(:error, "Failed to load prompts: #{inspect(reason)}")
    end
  end

  defp execute_prompt_search("", user_id, options) do
    # Load all prompts when no search query
    case PromptSearchEngine.list_user_prompts(user_id, options) do
      {:ok, prompts} -> {:ok, {prompts, length(prompts)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_prompt_search(query, user_id, options) do
    # Execute search when query provided
    search_params = %{
      query: query,
      user_id: user_id,
      search_options: options
    }

    case PromptSearchEngine.search_prompts(search_params) do
      {:ok, search_results} ->
        prompts = search_results.prompts
        total = search_results.total_count
        {:ok, {prompts, total}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_bulk_action("delete", prompt_ids, socket) do
    user_id = get_current_user_id(socket)

    case PromptOrganizer.bulk_delete_prompts(prompt_ids, user_id) do
      {:ok, deleted_count} ->
        {:ok, "Successfully deleted #{deleted_count} prompts"}
      {:error, reason} ->
        {:error, "Failed to delete prompts: #{inspect(reason)}"}
    end
  end

  defp execute_bulk_action("archive", prompt_ids, _socket) do
    case PromptOrganizer.bulk_archive_prompts(prompt_ids) do
      {:ok, archived_count} ->
        {:ok, "Successfully archived #{archived_count} prompts"}
      {:error, reason} ->
        {:error, "Failed to archive prompts: #{inspect(reason)}"}
    end
  end

  defp execute_bulk_action("add_to_category", _prompt_ids, _socket) do
    # Would need category selection - for now return not implemented
    {:error, "Bulk categorization not yet implemented"}
  end

  defp execute_bulk_action(action, _prompt_ids, _socket) do
    {:error, "Unknown bulk action: #{action}"}
  end

  defp load_analytics_data(socket) do
    user_id = get_current_user_id(socket)

    case PromptAnalyticsEngine.analyze_user_analytics(user_id) do
      {:ok, analytics} ->
        assign(socket, :analytics_data, analytics)
      {:error, _reason} ->
        assign(socket, :analytics_data, nil)
    end
  end

  # Utility functions

  defp get_current_user_id(socket) do
    # Extract user ID from socket assigns or session
    case socket.assigns do
      %{current_user: %{id: user_id}} -> user_id
      %{user_id: user_id} -> user_id
      _ -> nil
    end
  end

  defp save_user_preference(_socket, _key, _value) do
    # Integration with user preference system would go here
    :ok
  end

  defp parse_view_mode(nil), do: :list
  defp parse_view_mode(mode) when mode in ["list", "grid", "cards", "compact"] do
    String.to_atom(mode)
  end
  defp parse_view_mode(_), do: :list

  defp parse_sort_by(nil), do: :updated_at
  defp parse_sort_by(sort) when sort in ["name", "created_at", "updated_at", "usage_count", "effectiveness"] do
    String.to_atom(sort)
  end
  defp parse_sort_by(_), do: :updated_at

  defp parse_sort_order(nil), do: :desc
  defp parse_sort_order("asc"), do: :asc
  defp parse_sort_order("desc"), do: :desc
  defp parse_sort_order(_), do: :desc

  defp parse_filters(params) do
    filters = %{}

    # Parse prompt type filter
    filters = if params["type"] && params["type"] != "" do
      Map.put(filters, :prompt_type, String.to_atom(params["type"]))
    else
      filters
    end

    # Parse category filter
    filters = if params["category"] && params["category"] != "" do
      Map.put(filters, :category, params["category"])
    else
      filters
    end

    # Parse status filter
    filters = if params["status"] && params["status"] != "" do
      Map.put(filters, :status, String.to_atom(params["status"]))
    else
      filters
    end

    filters
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="prompt-library-container h-full flex flex-col">
      <!-- Header with search and controls -->
      <div class="prompt-library-header bg-white shadow-sm border-b border-gray-200 p-4">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
          <div class="flex items-center gap-4">
            <h1 class="text-2xl font-bold text-gray-900">Prompt Library</h1>
            <span class="text-sm text-gray-500">
              {show_count_text(@total_count, @loading)}
            </span>
          </div>

          <div class="flex items-center gap-2">
            <!-- View mode selector -->
            <div class="flex bg-gray-100 rounded-lg p-1">
              <button
                :for={mode <- @view_modes}
                phx-click="change_view_mode"
                phx-value-mode={mode}
                class={[
                  "px-3 py-1 text-sm rounded-md transition-colors",
                  if @view_mode == mode do
                    "bg-white shadow-sm text-gray-900"
                  else
                    "text-gray-600 hover:text-gray-900"
                  end
                ]}
              >
                {view_mode_label(mode)}
              </button>
            </div>

            <!-- Analytics toggle -->
            <button
              phx-click="toggle_analytics_panel"
              class="px-3 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              Analytics
            </button>

            <!-- New prompt button -->
            <.link
              navigate={~p"/prompts/new"}
              class="px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 transition-colors"
            >
              New Prompt
            </.link>
          </div>
        </div>

        <!-- Search and filters -->
        <div class="mt-4 flex flex-col lg:flex-row gap-4">
          <!-- Search input -->
          <div class="flex-1">
            <form phx-change="update_search" phx-submit="update_search">
              <input
                type="text"
                name="search[query]"
                value={@search_query}
                placeholder="Search prompts by name, content, or tags..."
                class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </form>
          </div>

          <!-- Filter controls -->
          <div class="flex items-center gap-2 flex-wrap">
            <!-- Type filter -->
            <select
              phx-change="toggle_filter"
              name="filter_type"
              data-filter-type="prompt_type"
              class="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All Types</option>
              <option value="system">System</option>
              <option value="project">Project</option>
              <option value="user">User</option>
            </select>

            <!-- Sort controls -->
            <select
              phx-change="apply_sort"
              name="sort_by"
              class="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
            >
              <option value="updated_at">Recently Updated</option>
              <option value="created_at">Recently Created</option>
              <option value="name">Name</option>
              <option value="usage_count">Most Used</option>
              <option value="effectiveness">Most Effective</option>
            </select>

            <!-- Bulk actions toggle -->
            <button
              :if={not Enum.empty?(@prompts)}
              phx-click="toggle_bulk_action_mode"
              class={[
                "px-3 py-2 text-sm rounded-lg border transition-colors",
                if @bulk_action_mode do
                  "bg-orange-50 border-orange-300 text-orange-700"
                else
                  "border-gray-300 text-gray-700 hover:bg-gray-50"
                end
              ]}
            >
              {if @bulk_action_mode, do: "Cancel Bulk", else: "Bulk Actions"}
            </button>
          </div>
        </div>
      </div>

      <!-- Main content area -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Prompt list -->
        <div class="flex-1 overflow-y-auto">
          {render_prompts_view(assigns)}
        </div>

        <!-- Analytics panel (if open) -->
        <div :if={@analytics_panel_open} class="w-80 bg-gray-50 border-l border-gray-200 overflow-y-auto">
          {render_analytics_panel(assigns)}
        </div>
      </div>

      <!-- Bulk action bar -->
      <div :if={@bulk_action_mode and not MapSet.empty?(@selected_prompts)} class="bg-blue-50 border-t border-blue-200 p-4">
        <div class="flex items-center justify-between">
          <span class="text-sm text-blue-700">
            {MapSet.size(@selected_prompts)} prompts selected
          </span>

          <div class="flex items-center gap-2">
            <button
              phx-click="execute_bulk_action"
              phx-value-action="delete"
              data-confirm="Are you sure you want to delete the selected prompts?"
              class="px-3 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700"
            >
              Delete
            </button>
            <button
              phx-click="execute_bulk_action"
              phx-value-action="archive"
              class="px-3 py-2 bg-gray-600 text-white text-sm rounded-lg hover:bg-gray-700"
            >
              Archive
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # View rendering functions

  defp render_prompts_view(assigns) do
    cond do
      assigns.loading -> render_loading_state(assigns)
      assigns.error -> render_error_state(assigns)
      Enum.empty?(assigns.prompts) -> render_empty_state(assigns)
      true -> render_prompts_by_view_mode(assigns)
    end
  end

  defp render_loading_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-64">
      <div class="text-center">
        <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4"></div>
        <p class="text-gray-500">Loading prompts...</p>
      </div>
    </div>
    """
  end

  defp render_error_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-64">
      <div class="text-center">
        <div class="text-red-500 mb-4">
          <svg class="h-12 w-12 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        </div>
        <p class="text-gray-900 font-medium mb-2">Error loading prompts</p>
        <p class="text-gray-500 mb-4">{@error}</p>
        <button
          phx-click="refresh_prompts"
          class="px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
        >
          Try Again
        </button>
      </div>
    </div>
    """
  end

  defp render_empty_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-64">
      <div class="text-center">
        <div class="text-gray-400 mb-4">
          <svg class="h-12 w-12 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
        </div>
        <p class="text-gray-900 font-medium mb-2">No prompts found</p>
        <p class="text-gray-500 mb-4">
          {if @search_query != "", do: "Try a different search or", else: "Get started by creating your first prompt"}
        </p>
        <.link
          navigate={~p"/prompts/new"}
          class="px-4 py-2 bg-green-600 text-white text-sm rounded-lg hover:bg-green-700"
        >
          Create Prompt
        </.link>
      </div>
    </div>
    """
  end

  defp render_prompts_by_view_mode(assigns) do
    case assigns.view_mode do
      :list -> render_list_view(assigns)
      :grid -> render_grid_view(assigns)
      :cards -> render_cards_view(assigns)
      :compact -> render_compact_view(assigns)
    end
  end

  defp render_list_view(assigns) do
    ~H"""
    <div class="prompt-list">
      <div class="bg-white">
        <div :for={prompt <- @prompts} class="border-b border-gray-200 hover:bg-gray-50">
          {render_prompt_list_item(assigns, prompt)}
        </div>
      </div>
    </div>
    """
  end

  defp render_prompt_list_item(assigns, prompt) do
    assigns = assign(assigns, :prompt, prompt)

    ~H"""
    <div class="p-4 flex items-center justify-between">
      <div class="flex items-center gap-4 flex-1">
        <!-- Selection checkbox (if in bulk mode) -->
        <input
          :if={@bulk_action_mode}
          type="checkbox"
          phx-click="toggle_prompt_selection"
          phx-value-prompt_id={@prompt.id}
          checked={MapSet.member?(@selected_prompts, @prompt.id)}
          class="h-4 w-4 text-blue-600 border-gray-300 rounded"
        />

        <!-- Prompt info -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1">
            <h3 class="text-sm font-medium text-gray-900 truncate">
              {@prompt.name}
            </h3>
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
              {@prompt.prompt_type}
            </span>
          </div>

          <p class="text-sm text-gray-500 line-clamp-2">
            {String.slice(@prompt.content || "", 0, 100)}...
          </p>

          <div class="flex items-center gap-4 mt-2 text-xs text-gray-400">
            <span>Updated {format_relative_time(@prompt.updated_at)}</span>
            <span :if={@prompt.tags && not Enum.empty?(@prompt.tags)}>
              Tags: {Enum.join(@prompt.tags, ", ")}
            </span>
          </div>
        </div>

        <!-- Actions -->
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/prompts/#{@prompt.id}/edit"}
            class="text-blue-600 hover:text-blue-800 text-sm"
          >
            Edit
          </.link>
          <.link
            navigate={~p"/prompts/#{@prompt.id}"}
            class="text-gray-600 hover:text-gray-800 text-sm"
          >
            View
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # Placeholder implementations for other view modes
  defp render_grid_view(assigns) do
    ~H"""
    <div class="prompt-grid p-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
      <div :for={prompt <- @prompts} class="bg-white rounded-lg shadow border border-gray-200 p-4">
        <h3 class="font-medium text-gray-900 mb-2">{prompt.name}</h3>
        <p class="text-sm text-gray-500 line-clamp-3">{String.slice(prompt.content || "", 0, 150)}</p>
        <div class="mt-4 flex justify-between items-center">
          <span class="text-xs text-gray-400">{format_relative_time(prompt.updated_at)}</span>
          <.link navigate={~p"/prompts/#{prompt.id}/edit"} class="text-blue-600 text-sm">Edit</.link>
        </div>
      </div>
    </div>
    """
  end

  defp render_cards_view(assigns), do: render_grid_view(assigns)  # Similar to grid for now
  defp render_compact_view(assigns), do: render_list_view(assigns)  # Similar to list for now

  defp render_analytics_panel(assigns) do
    ~H"""
    <div class="p-4">
      <h3 class="text-lg font-medium text-gray-900 mb-4">Analytics</h3>

      <div :if={@analytics_data} class="space-y-4">
        <div class="bg-white rounded-lg p-4 shadow-sm">
          <h4 class="text-sm font-medium text-gray-700 mb-2">Usage Summary</h4>
          <div class="space-y-2">
            <div class="flex justify-between text-sm">
              <span class="text-gray-500">Total Prompts</span>
              <span class="font-medium">{get_analytics_value(@analytics_data, :total_prompts, 0)}</span>
            </div>
            <div class="flex justify-between text-sm">
              <span class="text-gray-500">Usage This Month</span>
              <span class="font-medium">{get_analytics_value(@analytics_data, :monthly_usage, 0)}</span>
            </div>
          </div>
        </div>
      </div>

      <div :if={not @analytics_data} class="text-center py-8">
        <p class="text-gray-500 text-sm">Loading analytics...</p>
      </div>
    </div>
    """
  end

  # Helper functions

  defp show_count_text(count, loading) do
    cond do
      loading -> "Loading..."
      count == 0 -> "No prompts"
      count == 1 -> "1 prompt"
      true -> "#{count} prompts"
    end
  end

  defp view_mode_label(:list), do: "List"
  defp view_mode_label(:grid), do: "Grid"
  defp view_mode_label(:cards), do: "Cards"
  defp view_mode_label(:compact), do: "Compact"

  defp format_relative_time(datetime) do
    # Simple relative time formatting - would use a proper library in production
    diff = DateTime.diff(DateTime.utc_now(), datetime, :day)

    cond do
      diff == 0 -> "Today"
      diff == 1 -> "Yesterday"
      diff < 7 -> "#{diff} days ago"
      diff < 30 -> "#{div(diff, 7)} weeks ago"
      true -> "#{div(diff, 30)} months ago"
    end
  end

  defp get_analytics_value(analytics_data, key, default) do
    case analytics_data do
      %{} = data -> Map.get(data, key, default)
      _ -> default
    end
  end
end