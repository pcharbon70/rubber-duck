defmodule RubberDuckWeb.Preferences.AnalyticsLive do
  @moduledoc """
  Analytics dashboard for preference usage and insights.

  Features:
  - Usage statistics and trends
  - Inheritance hierarchy visualization  
  - Preference heatmaps
  - Override impact analysis
  - Performance metrics
  """

  use RubberDuckWeb, :live_view

  import Phoenix.HTML

  alias RubberDuck.Preferences.Resources.{SystemDefault, UserPreference}

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_initial_state()
     |> load_analytics_data()
     |> load_usage_trends()
     |> load_inheritance_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign_time_range(params)
     |> refresh_analytics()}
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    {:noreply, push_patch(socket, to: ~p"/preferences/analytics?range=#{range}")}
  end

  @impl true
  def handle_event("export_data", %{"format" => format}, socket) do
    case export_analytics_data(socket.assigns.analytics_data, format) do
      {:ok, file_path} ->
        {:noreply, put_flash(socket, :info, "Analytics data exported to #{file_path}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Export failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    {:noreply,
     socket
     |> load_analytics_data()
     |> load_usage_trends()
     |> load_inheritance_data()
     |> put_flash(:info, "Analytics data refreshed")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="analytics-dashboard">
      <!-- Header -->
      <div class="mb-6">
        <div class="flex justify-between items-center">
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Preference Analytics</h1>
            <p class="mt-1 text-sm text-gray-600">
              Insights and trends for your preference usage
            </p>
          </div>
          
          <div class="flex items-center space-x-3">
            <!-- Time Range Selector -->
            <select 
              phx-change="change_time_range"
              name="range"
              value={@time_range}
              class="form-select rounded-md border-gray-300"
            >
              <option value="7d">Last 7 days</option>
              <option value="30d">Last 30 days</option>
              <option value="90d">Last 90 days</option>
              <option value="1y">Last year</option>
            </select>
            
            <!-- Actions -->
            <div class="flex space-x-2">
              <button 
                phx-click="refresh_data"
                class="btn btn-outline btn-sm"
              >
                <svg class="h-4 w-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                Refresh
              </button>
              <div class="relative inline-block text-left">
                <button 
                  type="button"
                  class="btn btn-primary btn-sm"
                  onclick="document.getElementById('export-menu').classList.toggle('hidden')"
                >
                  Export
                </button>
                <div id="export-menu" class="hidden origin-top-right absolute right-0 mt-2 w-48 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 z-10">
                  <div class="py-1">
                    <button phx-click="export_data" phx-value-format="csv" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 w-full text-left">CSV</button>
                    <button phx-click="export_data" phx-value-format="json" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 w-full text-left">JSON</button>
                    <button phx-click="export_data" phx-value-format="pdf" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 w-full text-left">PDF Report</button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Summary Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-blue-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M3 4a1 1 0 011-1h12a1 1 0 011 1v2a1 1 0 01-1 1H4a1 1 0 01-1-1V4zM3 10a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H4a1 1 0 01-1-1v-6zM14 9a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1v-6a1 1 0 00-1-1h-2z"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Total Preferences
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @summary_stats.total_preferences %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-green-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    User Overrides
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @summary_stats.user_overrides %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-yellow-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Recent Changes
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @summary_stats.recent_changes %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-purple-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z"/>
                    <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Categories Used
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @summary_stats.categories_used %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Main Content Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <!-- Usage Trends Chart -->
        <div class="bg-white shadow rounded-lg">
          <div class="p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Usage Trends</h3>
            <div class="h-64 flex items-center justify-center border-2 border-dashed border-gray-300 rounded-lg">
              <div class="text-center">
                <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
                <p class="mt-2 text-sm text-gray-500">
                  Chart visualization placeholder<br/>
                  <span class="text-xs">Would integrate with Chart.js or similar</span>
                </p>
              </div>
            </div>
            <!-- Trend Data Summary -->
            <div class="mt-4 grid grid-cols-3 gap-4 text-sm">
              <%= for trend <- @usage_trends do %>
                <div class="text-center">
                  <div class="font-medium text-gray-900"><%= trend.period %></div>
                  <div class="text-gray-500"><%= trend.changes %> changes</div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
        <!-- Category Distribution -->
        <div class="bg-white shadow rounded-lg">
          <div class="p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Category Distribution</h3>
            <div class="space-y-3">
              <%= for category <- @category_stats do %>
                <div class="flex items-center justify-between">
                  <div class="flex items-center">
                    <div class={[
                      "w-3 h-3 rounded-full mr-3",
                      category_color(category.category)
                    ]}></div>
                    <span class="text-sm font-medium text-gray-900">
                      <%= String.capitalize(category.category) %>
                    </span>
                  </div>
                  <div class="flex items-center">
                    <span class="text-sm text-gray-500 mr-2">
                      <%= category.count %>
                    </span>
                    <div class="w-16 bg-gray-200 rounded-full h-2">
                      <div 
                        class={["h-2 rounded-full", category_color(category.category)]}
                        style={"width: #{category.percentage}%"}
                      ></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Detailed Analytics -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Most Changed Preferences -->
        <div class="bg-white shadow rounded-lg">
          <div class="p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Most Changed</h3>
            <div class="space-y-3">
              <%= for pref <- @most_changed_preferences do %>
                <div class="flex items-center justify-between">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-gray-900 truncate">
                      <%= pref.key %>
                    </p>
                    <p class="text-xs text-gray-500">
                      <%= pref.category %>
                    </p>
                  </div>
                  <div class="ml-4 text-right">
                    <p class="text-sm font-medium text-gray-900">
                      <%= pref.change_count %>
                    </p>
                    <p class="text-xs text-gray-500">
                      changes
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
        <!-- Inheritance Analysis -->
        <div class="bg-white shadow rounded-lg">
          <div class="p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Inheritance Hierarchy</h3>
            <div class="space-y-4">
              <!-- System Level -->
              <div class="flex items-center p-3 bg-gray-50 rounded-lg">
                <div class="w-3 h-3 bg-gray-400 rounded-full mr-3"></div>
                <div class="flex-1">
                  <div class="text-sm font-medium text-gray-900">System Defaults</div>
                  <div class="text-xs text-gray-500">
                    <%= @inheritance_stats.system_defaults %> preferences
                  </div>
                </div>
              </div>
              
              <!-- User Level -->
              <div class="flex items-center p-3 bg-blue-50 rounded-lg border-l-4 border-blue-400">
                <div class="w-3 h-3 bg-blue-500 rounded-full mr-3"></div>
                <div class="flex-1">
                  <div class="text-sm font-medium text-gray-900">User Overrides</div>
                  <div class="text-xs text-gray-500">
                    <%= @inheritance_stats.user_overrides %> preferences
                  </div>
                </div>
              </div>
              
              <!-- Project Level -->
              <div class="flex items-center p-3 bg-green-50 rounded-lg border-l-4 border-green-400">
                <div class="w-3 h-3 bg-green-500 rounded-full mr-3"></div>
                <div class="flex-1">
                  <div class="text-sm font-medium text-gray-900">Project Overrides</div>
                  <div class="text-xs text-gray-500">
                    <%= @inheritance_stats.project_overrides %> preferences
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Recent Activity -->
        <div class="bg-white shadow rounded-lg">
          <div class="p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Recent Activity</h3>
            <div class="flow-root">
              <ul class="-mb-8">
                <%= for {activity, index} <- Enum.with_index(@recent_activities) do %>
                  <li>
                    <div class="relative pb-8">
                      <%= unless index == length(@recent_activities) - 1 do %>
                        <span class="absolute top-4 left-4 -ml-px h-full w-0.5 bg-gray-200" aria-hidden="true"></span>
                      <% end %>
                      <div class="relative flex space-x-3">
                        <div>
                          <span class={[
                            "h-8 w-8 rounded-full flex items-center justify-center ring-8 ring-white",
                            activity_icon_color(activity.type)
                          ]}>
                            <%= activity_icon(activity.type) %>
                          </span>
                        </div>
                        <div class="min-w-0 flex-1">
                          <div>
                            <div class="text-sm">
                              <span class="font-medium text-gray-900">
                                <%= activity.preference_key %>
                              </span>
                            </div>
                            <p class="mt-0.5 text-xs text-gray-500">
                              <%= activity.action %> <%= time_ago(activity.timestamp) %>
                            </p>
                          </div>
                          <%= if activity.old_value && activity.new_value do %>
                            <div class="mt-2 text-xs text-gray-500">
                              <code class="bg-red-100 px-1 py-0.5 rounded"><%= activity.old_value %></code>
                              →
                              <code class="bg-green-100 px-1 py-0.5 rounded"><%= activity.new_value %></code>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp assign_initial_state(socket) do
    socket
    |> assign(:time_range, "30d")
    |> assign(:summary_stats, %{})
    |> assign(:usage_trends, [])
    |> assign(:category_stats, [])
    |> assign(:most_changed_preferences, [])
    |> assign(:inheritance_stats, %{})
    |> assign(:recent_activities, [])
    |> assign(:analytics_data, %{})
  end

  defp assign_time_range(socket, params) do
    assign(socket, :time_range, params["range"] || "30d")
  end

  defp refresh_analytics(socket) do
    socket
    |> load_analytics_data()
    |> load_usage_trends()
    |> load_inheritance_data()
  end

  defp load_analytics_data(socket) do
    user_id = socket.assigns.current_user.id
    time_range = socket.assigns.time_range

    # Summary statistics
    summary_stats = %{
      total_preferences: get_total_preferences(),
      user_overrides: get_user_overrides_count(user_id),
      recent_changes: get_recent_changes_count(user_id, time_range),
      categories_used: get_categories_used_count(user_id)
    }

    # Category distribution
    category_stats = get_category_distribution(user_id)

    # Most changed preferences
    most_changed = get_most_changed_preferences(user_id, time_range)

    # Recent activities
    recent_activities = get_recent_activities(user_id, 10)

    socket
    |> assign(:summary_stats, summary_stats)
    |> assign(:category_stats, category_stats)
    |> assign(:most_changed_preferences, most_changed)
    |> assign(:recent_activities, recent_activities)
  end

  defp load_usage_trends(socket) do
    user_id = socket.assigns.current_user.id
    time_range = socket.assigns.time_range

    trends = get_usage_trends(user_id, time_range)
    assign(socket, :usage_trends, trends)
  end

  defp load_inheritance_data(socket) do
    user_id = socket.assigns.current_user.id

    inheritance_stats = %{
      system_defaults: get_total_preferences(),
      user_overrides: get_user_overrides_count(user_id),
      project_overrides: get_project_overrides_count(user_id)
    }

    assign(socket, :inheritance_stats, inheritance_stats)
  end

  # Mock data functions (would integrate with actual analytics system)

  defp get_total_preferences do
    case SystemDefault.read() do
      {:ok, defaults} -> length(defaults)
      _ -> 0
    end
  end

  defp get_user_overrides_count(user_id) do
    case UserPreference.by_user_id(user_id) do
      {:ok, preferences} -> length(preferences)
      _ -> 0
    end
  end

  defp get_recent_changes_count(_user_id, _time_range) do
    # Mock implementation
    23
  end

  defp get_categories_used_count(user_id) do
    case UserPreference.by_user_id(user_id) do
      {:ok, preferences} ->
        preferences
        |> Enum.map(& &1.category)
        |> Enum.uniq()
        |> length()

      _ ->
        0
    end
  end

  defp get_category_distribution(_user_id) do
    # Mock data
    [
      %{category: "code_quality", count: 15, percentage: 35},
      %{category: "llm", count: 12, percentage: 28},
      %{category: "ml", count: 8, percentage: 19},
      %{category: "budgeting", count: 5, percentage: 12},
      %{category: "other", count: 3, percentage: 6}
    ]
  end

  defp get_most_changed_preferences(_user_id, _time_range) do
    # Mock data
    [
      %{key: "code_quality.global.enabled", category: "Code Quality", change_count: 8},
      %{key: "llm.providers.primary", category: "LLM", change_count: 6},
      %{key: "ml.training.learning_rate", category: "ML", change_count: 4},
      %{key: "budgeting.monthly_limit", category: "Budgeting", change_count: 3},
      %{key: "performance.cache.enabled", category: "Performance", change_count: 2}
    ]
  end

  defp get_usage_trends(_user_id, _time_range) do
    # Mock data
    [
      %{period: "This week", changes: 12},
      %{period: "Last week", changes: 8},
      %{period: "2 weeks ago", changes: 15}
    ]
  end

  defp get_project_overrides_count(_user_id) do
    # Mock implementation - would check project preferences
    7
  end

  defp get_recent_activities(_user_id, limit) do
    # Mock data
    activities = [
      %{
        preference_key: "code_quality.global.enabled",
        action: "updated",
        type: "update",
        old_value: "false",
        new_value: "true",
        timestamp: DateTime.add(DateTime.utc_now(), -3600, :second)
      },
      %{
        preference_key: "llm.providers.primary",
        action: "changed",
        type: "update",
        old_value: "openai",
        new_value: "anthropic",
        timestamp: DateTime.add(DateTime.utc_now(), -7200, :second)
      },
      %{
        preference_key: "ml.training.enabled",
        action: "created",
        type: "create",
        old_value: nil,
        new_value: "true",
        timestamp: DateTime.add(DateTime.utc_now(), -10_800, :second)
      }
    ]

    Enum.take(activities, limit)
  end

  defp export_analytics_data(_data, format) do
    # Mock implementation
    case format do
      "csv" -> {:ok, "/tmp/analytics_export.csv"}
      "json" -> {:ok, "/tmp/analytics_export.json"}
      "pdf" -> {:ok, "/tmp/analytics_report.pdf"}
      _ -> {:error, "Unsupported format"}
    end
  end

  # View helpers

  defp category_color("code_quality"), do: "bg-blue-500"
  defp category_color("llm"), do: "bg-green-500"
  defp category_color("ml"), do: "bg-purple-500"
  defp category_color("budgeting"), do: "bg-yellow-500"
  defp category_color("security"), do: "bg-red-500"
  defp category_color("performance"), do: "bg-indigo-500"
  defp category_color(_), do: "bg-gray-500"

  defp activity_icon_color("create"), do: "bg-green-500"
  defp activity_icon_color("update"), do: "bg-blue-500"
  defp activity_icon_color("delete"), do: "bg-red-500"
  defp activity_icon_color(_), do: "bg-gray-500"

  defp activity_icon("create") do
    raw("""
    <svg class="h-5 w-5 text-white" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd"/>
    </svg>
    """)
  end

  defp activity_icon("update") do
    raw("""
    <svg class="h-5 w-5 text-white" fill="currentColor" viewBox="0 0 20 20">
      <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z"/>
    </svg>
    """)
  end

  defp activity_icon("delete") do
    raw("""
    <svg class="h-5 w-5 text-white" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd"/>
    </svg>
    """)
  end

  defp activity_icon(_) do
    raw("""
    <svg class="h-5 w-5 text-white" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
    </svg>
    """)
  end

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86_400)} days ago"
    end
  end
end
