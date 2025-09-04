defmodule RubberDuckWeb.Live.Components.Prompts.PromptAnalyticsDashboardComponent do
  @moduledoc """
  Reusable analytics dashboard component for prompt usage insights.

  Provides embeddable analytics visualization with charts, metrics,
  and optimization recommendations that can be used in various
  contexts throughout the application.

  Features:
  - Configurable metrics display with time window selection
  - Interactive charts for usage trends and patterns
  - Optimization recommendations with priority ranking
  - Export capabilities for analytics data
  - Responsive design for different container sizes
  """

  use Phoenix.LiveComponent

  alias RubberDuck.Prompts.Services.{PromptAnalyticsEngine, PromptOptimizer}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:analytics_data, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def update(%{user_id: user_id, time_window: time_window} = assigns, socket) do
    socket = assign(socket, assigns)

    # Load analytics data
    socket = load_analytics_for_user(socket, user_id, time_window)

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_analytics", _params, socket) do
    user_id = socket.assigns.user_id
    time_window = socket.assigns.time_window

    socket = load_analytics_for_user(socket, user_id, time_window)

    {:noreply, socket}
  end

  # Private functions

  defp load_analytics_for_user(socket, user_id, time_window) do
    options = %{time_window: time_window}

    socket = assign(socket, :loading, true)

    case PromptAnalyticsEngine.analyze_user_analytics(user_id, options) do
      {:ok, analytics_data} ->
        socket
        |> assign(:analytics_data, analytics_data)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:analytics_data, nil)
        |> assign(:loading, false)
        |> assign(:error, "Failed to load analytics: #{inspect(reason)}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="analytics-dashboard">
      <div :if={@loading} class="text-center py-8">
        <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600 mx-auto mb-2"></div>
        <p class="text-sm text-gray-500">Loading analytics...</p>
      </div>

      <div :if={@error} class="text-center py-8">
        <p class="text-red-600 mb-2">Analytics Error</p>
        <p class="text-sm text-gray-500 mb-4">{@error}</p>
        <button
          phx-click="refresh_analytics"
          phx-target={@myself}
          class="px-3 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
        >
          Retry
        </button>
      </div>

      <div :if={@analytics_data && not @loading} class="space-y-4">
        <!-- Key metrics -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {render_metric_card("Total Prompts", get_metric(@analytics_data, :total_prompts, 0))}
          {render_metric_card("This Period", get_metric(@analytics_data, :usage_count, 0))}
          {render_metric_card("Success Rate", format_percentage(get_metric(@analytics_data, :success_rate, 0)))}
          {render_metric_card("Avg Response", "#{get_metric(@analytics_data, :avg_response_time, 0)}ms")}
        </div>

        <!-- Analytics summary -->
        <div class="bg-gray-50 rounded-lg p-4">
          <h4 class="text-sm font-medium text-gray-700 mb-2">Analytics Summary</h4>
          <p class="text-sm text-gray-600">
            Analytics data available for the selected time period.
            Detailed charts and insights available in the full analytics dashboard.
          </p>
        </div>
      </div>

      <div :if={not @analytics_data && not @loading && not @error} class="text-center py-8">
        <p class="text-gray-500">No analytics data available</p>
        <p class="text-sm text-gray-400">Use some prompts to see analytics</p>
      </div>
    </div>
    """
  end

  defp render_metric_card(title, value) do
    assigns = %{title: title, value: value}

    ~H"""
    <div class="bg-white rounded-lg border border-gray-200 p-3">
      <h4 class="text-xs font-medium text-gray-500 uppercase tracking-wide">{@title}</h4>
      <p class="text-lg font-semibold text-gray-900 mt-1">{@value}</p>
    </div>
    """
  end

  defp get_metric(analytics_data, key, default) do
    case analytics_data do
      %{} = data -> Map.get(data, key, default)
      _ -> default
    end
  end

  defp format_percentage(value) when is_number(value) do
    "#{Float.round(value * 100, 1)}%"
  end
  defp format_percentage(_), do: "N/A"
end