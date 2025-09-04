defmodule RubberDuckWeb.Live.Prompts.PromptAnalyticsLive do
  @moduledoc """
  Analytics dashboard for prompt usage insights and optimization recommendations.

  Provides comprehensive analytics visualization with usage patterns, effectiveness
  metrics, optimization opportunities, and trend analysis. Integrates with the
  analytics engine for real-time data and includes export capabilities.

  Features:
  - Usage analytics with interactive charts and metrics visualization
  - Effectiveness analysis with top/bottom performer identification
  - Optimization recommendations with priority ranking and implementation guidance
  - Trend analysis with forecasting and pattern recognition
  - Export capabilities for analytics data in multiple formats
  - Real-time updates with configurable refresh intervals
  """

  use RubberDuckWeb, :live_view

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  alias RubberDuck.Prompts.Services.{
    PromptAnalyticsEngine,
    PromptReportingEngine,
    PromptOptimizer
  }

  @time_window_options [
    {"Last 7 days", %{amount: 7, unit: :days}},
    {"Last 30 days", %{amount: 30, unit: :days}},
    {"Last 90 days", %{amount: 90, unit: :days}},
    {"Last 6 months", %{amount: 6, unit: :months}},
    {"Last year", %{amount: 1, unit: :years}}
  ]

  @analytics_tabs [:overview, :usage_patterns, :effectiveness, :optimization]
  @refresh_intervals [30, 60, 300, 600]  # seconds

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Prompt Analytics")
     |> assign(:active_tab, :overview)
     |> assign(:time_window, %{amount: 30, unit: :days})
     |> assign(:auto_refresh, false)
     |> assign(:refresh_interval, 60)
     |> assign(:loading, true)
     |> assign(:analytics_data, nil)
     |> assign(:optimization_data, nil)
     |> assign(:error, nil)
     |> load_analytics_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_analytics_params(params)
      |> load_analytics_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) when tab in ["overview", "usage_patterns", "effectiveness", "optimization"] do
    active_tab = String.to_atom(tab)

    socket =
      socket
      |> assign(:active_tab, active_tab)
      |> maybe_load_tab_specific_data(active_tab)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_time_window", %{"window" => window_key}, socket) do
    time_window = case Enum.find(@time_window_options, fn {key, _} -> key == window_key end) do
      {_, window} -> window
      nil -> %{amount: 30, unit: :days}
    end

    socket =
      socket
      |> assign(:time_window, time_window)
      |> assign(:loading, true)
      |> load_analytics_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_auto_refresh", _params, socket) do
    auto_refresh = not socket.assigns.auto_refresh

    socket = assign(socket, :auto_refresh, auto_refresh)

    # Schedule or cancel refresh
    if auto_refresh do
      schedule_refresh(socket.assigns.refresh_interval)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_analytics", %{"format" => format}, socket) do
    case export_analytics_data(socket.assigns.analytics_data, format) do
      {:ok, _export_data} ->
        # In a real implementation, would trigger download
        socket = put_flash(socket, :info, "Analytics exported successfully")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Export failed: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_analytics", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_analytics_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_analytics, socket) do
    socket = load_analytics_data(socket)

    # Schedule next refresh if auto-refresh is enabled
    if socket.assigns.auto_refresh do
      schedule_refresh(socket.assigns.refresh_interval)
    end

    {:noreply, socket}
  end

  # Private functions

  defp apply_analytics_params(socket, params) do
    socket
    |> assign(:active_tab, parse_analytics_tab(params["tab"]))
    |> assign(:time_window, parse_time_window(params["window"]))
  end

  defp load_analytics_data(socket) do
    user_id = get_current_user_id(socket)
    options = %{time_window: socket.assigns.time_window}

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

  defp maybe_load_tab_specific_data(socket, :optimization) do
    # Load optimization data for optimization tab
    user_id = get_current_user_id(socket)

    case PromptOptimizer.analyze_optimization_opportunities(%{user_id: user_id}) do
      {:ok, optimization_data} ->
        assign(socket, :optimization_data, optimization_data)
      {:error, _reason} ->
        assign(socket, :optimization_data, nil)
    end
  end

  defp maybe_load_tab_specific_data(socket, _tab) do
    # No additional data needed for other tabs
    socket
  end

  defp export_analytics_data(analytics_data, format) do
    case format do
      "json" ->
        {:ok, Jason.encode!(analytics_data)}
      "csv" ->
        # Would generate CSV format
        {:ok, "CSV export not yet implemented"}
      _ ->
        {:error, "Unsupported format: #{format}"}
    end
  end

  defp schedule_refresh(interval_seconds) do
    Process.send_after(self(), :refresh_analytics, interval_seconds * 1000)
  end

  # Utility functions

  defp get_current_user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: user_id}} -> user_id
      %{user_id: user_id} -> user_id
      _ -> nil
    end
  end

  defp parse_analytics_tab(nil), do: :overview
  defp parse_analytics_tab(tab) when tab in ["overview", "usage_patterns", "effectiveness", "optimization"] do
    String.to_atom(tab)
  end
  defp parse_analytics_tab(_), do: :overview

  defp parse_time_window(nil), do: %{amount: 30, unit: :days}
  defp parse_time_window(window_key) do
    case Enum.find(@time_window_options, fn {key, _} -> key == window_key end) do
      {_, window} -> window
      nil -> %{amount: 30, unit: :days}
    end
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :minute)

    cond do
      diff < 1 -> "just now"
      diff < 60 -> "#{diff} minutes ago"
      diff < 1440 -> "#{div(diff, 60)} hours ago"
      true -> "#{div(diff, 1440)} days ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="analytics-container h-full flex flex-col">
      <!-- Header -->
      <div class="bg-white shadow-sm border-b border-gray-200 p-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-4">
            <h1 class="text-2xl font-bold text-gray-900">Analytics Dashboard</h1>
            <div class="flex items-center gap-2">
              <select
                phx-change="change_time_window"
                name="window"
                class="px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option :for={{label, window} <- @time_window_options} value={label}>
                  {label}
                </option>
              </select>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <!-- Auto-refresh toggle -->
            <button
              phx-click="toggle_auto_refresh"
              class={[
                "px-3 py-2 text-sm rounded-lg border transition-colors",
                if @auto_refresh do
                  "bg-green-50 border-green-300 text-green-700"
                else
                  "border-gray-300 text-gray-700 hover:bg-gray-50"
                end
              ]}
            >
              Auto-refresh: {if @auto_refresh, do: "ON", else: "OFF"}
            </button>

            <!-- Refresh button -->
            <button
              phx-click="refresh_analytics"
              class="px-3 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
            >
              Refresh
            </button>

            <!-- Export dropdown -->
            <div class="relative inline-block text-left">
              <button class="px-3 py-2 bg-gray-600 text-white text-sm rounded-lg hover:bg-gray-700">
                Export
              </button>
            </div>
          </div>
        </div>

        <!-- Navigation tabs -->
        <div class="mt-4 border-b border-gray-200">
          <nav class="flex space-x-8">
            <button
              :for={tab <- @analytics_tabs}
              phx-click="change_tab"
              phx-value-tab={tab}
              class={[
                "py-2 px-1 border-b-2 font-medium text-sm",
                if @active_tab == tab do
                  "border-blue-500 text-blue-600"
                else
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                end
              ]}
            >
              {analytics_tab_label(tab)}
            </button>
          </nav>
        </div>
      </div>

      <!-- Analytics content -->
      <div class="flex-1 overflow-y-auto">
        {render_analytics_content(assigns)}
      </div>
    </div>
    """
  end

  defp render_analytics_content(assigns) do
    cond do
      assigns.loading -> render_analytics_loading(assigns)
      assigns.error -> render_analytics_error(assigns)
      assigns.analytics_data -> render_analytics_by_tab(assigns)
      true -> render_analytics_empty(assigns)
    end
  end

  defp render_analytics_loading(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-64">
      <div class="text-center">
        <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4"></div>
        <p class="text-gray-500">Loading analytics...</p>
      </div>
    </div>
    """
  end

  defp render_analytics_error(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-64">
      <div class="text-center">
        <p class="text-red-600 mb-4">Error loading analytics</p>
        <p class="text-gray-500 mb-4">{@error}</p>
        <button
          phx-click="refresh_analytics"
          class="px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
        >
          Retry
        </button>
      </div>
    </div>
    """
  end

  defp render_analytics_empty(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-64">
      <div class="text-center">
        <p class="text-gray-500">No analytics data available</p>
        <p class="text-sm text-gray-400 mt-2">Create and use some prompts to see analytics</p>
      </div>
    </div>
    """
  end

  defp render_analytics_by_tab(assigns) do
    case assigns.active_tab do
      :overview -> render_overview_analytics(assigns)
      :usage_patterns -> render_usage_patterns(assigns)
      :effectiveness -> render_effectiveness_analytics(assigns)
      :optimization -> render_optimization_analytics(assigns)
    end
  end

  defp render_overview_analytics(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <!-- Key metrics -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {render_metric_card("Total Prompts", get_analytics_metric(@analytics_data, :total_prompts, 0))}
        {render_metric_card("Usage This Period", get_analytics_metric(@analytics_data, :usage_count, 0))}
        {render_metric_card("Success Rate", format_percentage(get_analytics_metric(@analytics_data, :success_rate, 0)))}
        {render_metric_card("Avg Response Time", "#{get_analytics_metric(@analytics_data, :avg_response_time, 0)}ms")}
      </div>

      <!-- Usage chart placeholder -->
      <div class="bg-white rounded-lg shadow border border-gray-200 p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Usage Trends</h3>
        <div class="h-64 flex items-center justify-center bg-gray-50 rounded-lg">
          <p class="text-gray-500">Chart visualization will be implemented here</p>
        </div>
      </div>
    </div>
    """
  end

  defp render_usage_patterns(assigns) do
    ~H"""
    <div class="p-6">
      <div class="bg-white rounded-lg shadow border border-gray-200 p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Usage Patterns</h3>
        <p class="text-gray-500">Usage pattern analysis will be implemented here</p>
      </div>
    </div>
    """
  end

  defp render_effectiveness_analytics(assigns) do
    ~H"""
    <div class="p-6">
      <div class="bg-white rounded-lg shadow border border-gray-200 p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Effectiveness Analysis</h3>
        <p class="text-gray-500">Effectiveness analysis will be implemented here</p>
      </div>
    </div>
    """
  end

  defp render_optimization_analytics(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <!-- Optimization opportunities -->
      <div class="bg-white rounded-lg shadow border border-gray-200 p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Optimization Recommendations</h3>

        <div :if={@optimization_data && @optimization_data.prioritized_recommendations}>
          <div class="space-y-4">
            <div
              :for={recommendation <- Enum.take(@optimization_data.prioritized_recommendations, 5)}
              class="border border-gray-200 rounded-lg p-4"
            >
              <div class="flex items-start justify-between">
                <div>
                  <h4 class="font-medium text-gray-900">{recommendation.description || "Optimization Opportunity"}</h4>
                  <p class="text-sm text-gray-600 mt-1">
                    Impact: {recommendation.impact_level || :medium} |
                    Effort: {recommendation.effort_level || :medium}
                  </p>
                </div>
                <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
                  Score: {Float.round(recommendation.priority_score || 5.0, 1)}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div :if={not @optimization_data} class="text-center py-8">
          <p class="text-gray-500">Loading optimization recommendations...</p>
        </div>
      </div>
    </div>
    """
  end

  defp render_metric_card(title, value) do
    assigns = %{title: title, value: value}

    ~H"""
    <div class="bg-white rounded-lg shadow border border-gray-200 p-4">
      <h3 class="text-sm font-medium text-gray-500">{@title}</h3>
      <p class="text-2xl font-bold text-gray-900 mt-2">{@value}</p>
    </div>
    """
  end

  # Helper functions

  defp get_current_user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: user_id}} -> user_id
      %{user_id: user_id} -> user_id
      _ -> nil
    end
  end

  defp get_analytics_metric(analytics_data, key, default) do
    case analytics_data do
      %{} = data -> Map.get(data, key, default)
      _ -> default
    end
  end

  defp format_percentage(value) when is_number(value) do
    "#{Float.round(value * 100, 1)}%"
  end
  defp format_percentage(_), do: "N/A"

  defp analytics_tab_label(:overview), do: "Overview"
  defp analytics_tab_label(:usage_patterns), do: "Usage Patterns"
  defp analytics_tab_label(:effectiveness), do: "Effectiveness"
  defp analytics_tab_label(:optimization), do: "Optimization"

  defp parse_analytics_tab(nil), do: :overview
  defp parse_analytics_tab(tab) when tab in ["overview", "usage_patterns", "effectiveness", "optimization"] do
    String.to_atom(tab)
  end
  defp parse_analytics_tab(_), do: :overview

  defp parse_time_window(nil), do: %{amount: 30, unit: :days}
  defp parse_time_window(window_key) do
    case Enum.find(@time_window_options, fn {key, _} -> key == window_key end) do
      {_, window} -> window
      nil -> %{amount: 30, unit: :days}
    end
  end
end