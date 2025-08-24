defmodule RubberDuckWeb.Preferences.DashboardLive do
  @moduledoc """
  Main preference dashboard providing comprehensive preference management interface.

  Features:
  - Real-time preference updates via PubSub
  - Category-based organization
  - Search and filtering
  - User and project context switching
  - Quick access to templates and analytics
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Preferences.{PreferenceResolver, PreferenceWatcher}
  alias RubberDuck.Preferences.Resources.{PreferenceCategory, SystemDefault, UserPreference}

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to preference changes for real-time updates
      PreferenceWatcher.subscribe_user_changes(socket.assigns.current_user.id)
    end

    {:ok,
     socket
     |> assign_initial_state()
     |> load_preferences()
     |> load_categories()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign_filters(params)
     |> apply_filters()}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> apply_filters()}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: ~p"/preferences?category=#{category}")}
  end

  @impl true
  def handle_event("toggle_project_context", %{"project_id" => project_id}, socket) do
    new_project_id = if socket.assigns.project_id == project_id, do: nil, else: project_id

    {:noreply,
     socket
     |> assign(:project_id, new_project_id)
     |> load_preferences()
     |> apply_filters()}
  end

  @impl true
  def handle_event("quick_edit", %{"key" => key, "value" => value}, socket) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project_id

    case update_preference_value(user_id, key, value, project_id) do
      {:ok, _preference} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{key}")
         |> load_preferences()
         |> apply_filters()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update #{key}: #{reason}")}
    end
  end

  @impl true
  def handle_info({:preference_changed, change_event}, socket) do
    if change_event.user_id == socket.assigns.current_user.id do
      {:noreply,
       socket
       |> load_preferences()
       |> apply_filters()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="preference-dashboard">
      <!-- Header with context selector and search -->
      <div class="dashboard-header">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-2xl font-bold text-gray-900">Preference Management</h1>
          <div class="flex space-x-4">
            <.link 
              navigate={~p"/preferences/templates"} 
              class="btn btn-outline"
            >
              Browse Templates
            </.link>
            <.link 
              navigate={~p"/preferences/analytics"} 
              class="btn btn-outline"
            >
              View Analytics
            </.link>
          </div>
        </div>
        
        <!-- Context and Search Bar -->
        <div class="bg-white rounded-lg shadow p-4 mb-6">
          <div class="flex flex-wrap items-center gap-4">
            <!-- Project Context Toggle -->
            <div class="flex items-center space-x-2">
              <label class="text-sm font-medium text-gray-700">Context:</label>
              <select 
                phx-change="toggle_project_context"
                name="project_id"
                class="form-select rounded-md border-gray-300"
              >
                <option value="" selected={is_nil(@project_id)}>User Preferences</option>
                <%= for project <- @available_projects do %>
                  <option value={project.id} selected={@project_id == project.id}>
                    <%= project.name %> (Project)
                  </option>
                <% end %>
              </select>
            </div>
            
            <!-- Search -->
            <div class="flex-1 max-w-md">
              <.form 
                for={%{}}
                as={:search}
                phx-change="search"
                class="flex"
              >
                <.input
                  type="search"
                  name="query"
                  value={@search_query}
                  placeholder="Search preferences..."
                  class="flex-1"
                />
              </.form>
            </div>
            
            <!-- Quick Stats -->
            <div class="text-sm text-gray-600">
              Showing <%= length(@filtered_preferences) %> of <%= length(@all_preferences) %> preferences
            </div>
          </div>
        </div>
      </div>
      
      <!-- Main Content Area -->
      <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
        <!-- Category Sidebar -->
        <div class="lg:col-span-1">
          <div class="bg-white rounded-lg shadow">
            <div class="p-4 border-b border-gray-200">
              <h3 class="font-medium text-gray-900">Categories</h3>
            </div>
            <nav class="p-2">
              <.link
                patch={~p"/preferences"}
                class={[
                  "block px-3 py-2 rounded-md text-sm font-medium",
                  if(is_nil(@selected_category), 
                     do: "bg-blue-100 text-blue-700", 
                     else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50")
                ]}
              >
                All Categories
                <span class="ml-auto text-xs text-gray-400">
                  <%= length(@all_preferences) %>
                </span>
              </.link>
              
              <%= for category <- @categories do %>
                <.link
                  patch={~p"/preferences?category=#{category.name}"}
                  class={[
                    "block px-3 py-2 rounded-md text-sm font-medium flex justify-between items-center",
                    if(@selected_category == category.name,
                       do: "bg-blue-100 text-blue-700",
                       else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50")
                  ]}
                >
                  <span><%= String.capitalize(category.name) %></span>
                  <span class="text-xs text-gray-400">
                    <%= count_preferences_by_category(@all_preferences, category.name) %>
                  </span>
                </.link>
              <% end %>
            </nav>
          </div>
        </div>
        
        <!-- Preferences List -->
        <div class="lg:col-span-3">
          <div class="bg-white rounded-lg shadow">
            <div class="p-4 border-b border-gray-200">
              <div class="flex justify-between items-center">
                <h3 class="font-medium text-gray-900">
                  <%= if @selected_category do %>
                    <%= String.capitalize(@selected_category) %> Preferences
                  <% else %>
                    All Preferences
                  <% end %>
                </h3>
                <div class="flex space-x-2">
                  <button 
                    type="button"
                    class="btn btn-sm btn-outline"
                    data-view="grid"
                  >
                    Grid
                  </button>
                  <button 
                    type="button" 
                    class="btn btn-sm btn-primary"
                    data-view="table"
                  >
                    Table
                  </button>
                </div>
              </div>
            </div>
            
            <%= if length(@filtered_preferences) > 0 do %>
              <div class="divide-y divide-gray-200">
                <%= for preference <- @filtered_preferences do %>
                  <div class="p-4 hover:bg-gray-50">
                    <div class="flex justify-between items-start">
                      <div class="flex-1 min-w-0">
                        <div class="flex items-center space-x-2">
                          <h4 class="text-sm font-medium text-gray-900 truncate">
                            <%= preference.key %>
                          </h4>
                          <%= if preference.source != "system" do %>
                            <span class={[
                              "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
                              case preference.source do
                                "user" -> "bg-blue-100 text-blue-800"
                                "project" -> "bg-green-100 text-green-800"
                                _ -> "bg-gray-100 text-gray-800"
                              end
                            ]}>
                              <%= String.capitalize(preference.source) %>
                            </span>
                          <% end %>
                        </div>
                        <p class="text-xs text-gray-500 mt-1">
                          <%= preference.description %>
                        </p>
                        <div class="mt-2">
                          <%= if preference.editable do %>
                            <.form
                              for={%{}}
                              as={:quick_edit}
                              phx-submit="quick_edit"
                              class="flex items-center space-x-2"
                            >
                              <input type="hidden" name="key" value={preference.key} />
                              <.input
                                type={input_type_for_preference(preference)}
                                name="value"
                                value={preference.value}
                                class="text-sm"
                                size="sm"
                              />
                              <button type="submit" class="btn btn-xs btn-primary">
                                Update
                              </button>
                            </.form>
                          <% else %>
                            <code class="text-sm text-gray-700 bg-gray-100 px-2 py-1 rounded">
                              <%= preference.value %>
                            </code>
                          <% end %>
                        </div>
                      </div>
                      <div class="ml-4 flex-shrink-0">
                        <.link
                          navigate={~p"/preferences/edit/#{preference.key}"}
                          class="text-sm text-blue-600 hover:text-blue-500"
                        >
                          Edit
                        </.link>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="p-8 text-center">
                <div class="text-gray-400 mb-4">
                  <svg class="mx-auto h-12 w-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                </div>
                <h3 class="text-lg font-medium text-gray-900 mb-2">No preferences found</h3>
                <p class="text-gray-500">
                  <%= if @search_query != "" do %>
                    No preferences match your search "<%= @search_query %>".
                  <% else %>
                    No preferences available in this category.
                  <% end %>
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp assign_initial_state(socket) do
    socket
    |> assign(:search_query, "")
    |> assign(:selected_category, nil)
    |> assign(:project_id, nil)
    |> assign(:all_preferences, [])
    |> assign(:filtered_preferences, [])
    |> assign(:categories, [])
    |> assign(:available_projects, get_user_projects(socket.assigns.current_user.id))
  end

  defp assign_filters(socket, params) do
    socket
    |> assign(:selected_category, params["category"])
    |> assign(:search_query, params["search"] || "")
  end

  defp load_preferences(socket) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project_id

    preferences = get_all_preferences_for_user(user_id, project_id)

    socket
    |> assign(:all_preferences, preferences)
  end

  defp load_categories(socket) do
    case PreferenceCategory.read() do
      {:ok, categories} ->
        assign(socket, :categories, categories)

      {:error, _} ->
        assign(socket, :categories, [])
    end
  end

  defp apply_filters(socket) do
    preferences =
      socket.assigns.all_preferences
      |> filter_by_category(socket.assigns.selected_category)
      |> filter_by_search(socket.assigns.search_query)

    assign(socket, :filtered_preferences, preferences)
  end

  defp filter_by_category(preferences, nil), do: preferences

  defp filter_by_category(preferences, category) do
    Enum.filter(preferences, &(&1.category == category))
  end

  defp filter_by_search(preferences, ""), do: preferences

  defp filter_by_search(preferences, query) do
    query = String.downcase(query)

    Enum.filter(preferences, fn pref ->
      String.contains?(String.downcase(pref.key), query) or
        String.contains?(String.downcase(pref.description || ""), query)
    end)
  end

  defp get_all_preferences_for_user(user_id, project_id) do
    case SystemDefault.read() do
      {:ok, system_defaults} -> build_user_preferences(user_id, project_id, system_defaults)
      {:error, _} -> []
    end
  end

  defp build_user_preferences(user_id, project_id, system_defaults) do
    Enum.map(system_defaults, &build_user_preference(user_id, project_id, &1))
  end

  defp build_user_preference(user_id, project_id, default) do
    case PreferenceResolver.resolve(user_id, default.preference_key, project_id) do
      {:ok, value} -> build_resolved_user_preference(user_id, project_id, default, value)
      {:error, _} -> build_default_user_preference(default, project_id)
    end
  end

  defp build_resolved_user_preference(user_id, project_id, default, value) do
    %{
      key: default.preference_key,
      value: value,
      category: default.category,
      description: default.description,
      data_type: default.data_type,
      source: determine_preference_source(user_id, default.preference_key, project_id),
      editable: preference_editable?(default.preference_key, project_id)
    }
  end

  defp build_default_user_preference(default, project_id) do
    %{
      key: default.preference_key,
      value: default.default_value,
      category: default.category,
      description: default.description,
      data_type: default.data_type,
      source: "system",
      editable: preference_editable?(default.preference_key, project_id)
    }
  end

  defp determine_preference_source(user_id, key, project_id) do
    case UserPreference.by_user_and_key(user_id, key) do
      {:ok, [_user_pref]} -> resolve_source_with_project_check(project_id, key)
      {:ok, []} -> "system"
      _ -> "unknown"
    end
  end

  defp resolve_source_with_project_check(nil, _key), do: "user"
  defp resolve_source_with_project_check(project_id, key) do
    case check_project_override(project_id, key) do
      true -> "project"
      false -> "user"
    end
  end

  defp check_project_override(_project_id, _key) do
    # Placeholder for project override checking
    false
  end

  defp preference_editable?(_key, _project_id) do
    # All preferences are editable for now
    true
  end

  defp get_user_projects(_user_id) do
    # Placeholder for user project retrieval
    [
      %{id: "proj1", name: "Example Project"},
      %{id: "proj2", name: "Another Project"}
    ]
  end

  defp count_preferences_by_category(preferences, category) do
    preferences
    |> Enum.count(&(&1.category == category))
  end

  defp input_type_for_preference(preference) do
    case preference.data_type do
      "boolean" -> "checkbox"
      "number" -> "number"
      "float" -> "number"
      _ -> "text"
    end
  end

  defp update_preference_value(user_id, key, value, project_id) do
    if project_id do
      # Update project preference
      {:error, "Project preference updates not yet implemented"}
    else
      # Update user preference
      case UserPreference.by_user_and_key(user_id, key) do
        {:ok, [existing]} ->
          UserPreference.update(existing, %{value: value})

        {:ok, []} ->
          attrs = %{
            user_id: user_id,
            preference_key: key,
            value: value,
            category: get_preference_category(key),
            source: :dashboard
          }

          UserPreference.create(attrs)

        error ->
          error
      end
    end
  end

  defp get_preference_category(key) do
    key |> String.split(".") |> hd()
  end
end
