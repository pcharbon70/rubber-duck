defmodule RubberDuck.HealthCheck.HTTPEndpoint do
  @moduledoc """
  HTTP endpoint for health check responses.

  Provides JSON endpoints for Kubernetes probes and monitoring systems:
  - /health - Simple health check (200 OK / 503 Service Unavailable)
  - /health/detailed - Detailed health status with component breakdown
  - /health/ready - Readiness probe for Kubernetes
  - /health/live - Liveness probe for Kubernetes
  """

  use Plug.Router
  require Logger

  alias RubberDuck.HealthCheck.StatusAggregator

  plug(Plug.Logger)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # Simple health check endpoint
  get "/health" do
    case StatusAggregator.get_overall_status() do
      :healthy ->
        send_json_response(conn, 200, %{status: "healthy"})

      :warning ->
        send_json_response(conn, 200, %{status: "warning"})

      status when status in [:degraded, :critical, :error] ->
        send_json_response(conn, 503, %{status: to_string(status)})

      _ ->
        send_json_response(conn, 503, %{status: "unknown"})
    end
  end

  # Detailed health status endpoint
  get "/health/detailed" do
    detailed_status = StatusAggregator.get_detailed_status()

    http_status =
      case detailed_status.overall_status do
        status when status in [:healthy, :warning] -> 200
        _ -> 503
      end

    response = %{
      status: to_string(detailed_status.overall_status),
      timestamp: detailed_status.last_update,
      summary: detailed_status.summary,
      components: format_component_statuses(detailed_status.components)
    }

    send_json_response(conn, http_status, response)
  end

  # Kubernetes readiness probe
  get "/health/ready" do
    detailed_status = StatusAggregator.get_detailed_status()

    # Ready if overall status is healthy or warning (can serve traffic)
    case detailed_status.overall_status do
      status when status in [:healthy, :warning] ->
        response = %{
          status: "ready",
          components_healthy: detailed_status.summary.healthy,
          components_total: detailed_status.summary.total_components
        }

        send_json_response(conn, 200, response)

      _ ->
        response = %{
          status: "not_ready",
          reason: to_string(detailed_status.overall_status),
          components_healthy: detailed_status.summary.healthy,
          components_total: detailed_status.summary.total_components
        }

        send_json_response(conn, 503, response)
    end
  end

  # Kubernetes liveness probe
  get "/health/live" do
    # Liveness is more permissive - only fail on critical system issues
    detailed_status = StatusAggregator.get_detailed_status()

    case detailed_status.overall_status do
      :critical ->
        # Check if it's a recoverable issue
        if recoverable_critical_state?(detailed_status.components) do
          send_json_response(conn, 200, %{status: "alive", condition: "degraded"})
        else
          send_json_response(conn, 503, %{status: "unhealthy", reason: "critical_system_failure"})
        end

      _ ->
        send_json_response(conn, 200, %{status: "alive"})
    end
  end

  # Health history endpoint
  get "/health/history" do
    limit =
      conn.query_params["limit"]
      |> case do
        nil ->
          10

        limit_str ->
          case Integer.parse(limit_str) do
            {limit_int, _} when limit_int > 0 and limit_int <= 100 -> limit_int
            _ -> 10
          end
      end

    history = StatusAggregator.get_status_history(limit)

    formatted_history =
      Enum.map(history, fn entry ->
        %{
          status: to_string(entry.status),
          timestamp: entry.timestamp,
          component_count: map_size(entry.components)
        }
      end)

    send_json_response(conn, 200, %{history: formatted_history})
  end

  # Metrics endpoint (Prometheus-style)
  get "/health/metrics" do
    detailed_status = StatusAggregator.get_detailed_status()

    metrics_text = format_prometheus_metrics(detailed_status)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics_text)
  end

  # Catch-all for unknown paths
  match _ do
    send_json_response(conn, 404, %{
      error: "Not Found",
      available_endpoints: [
        "/health",
        "/health/detailed",
        "/health/ready",
        "/health/live",
        "/health/history",
        "/health/metrics"
      ]
    })
  end

  ## Helper Functions

  defp send_json_response(conn, status, data) do
    json_data = Jason.encode!(data)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, json_data)
  end

  defp format_component_statuses(components) do
    Map.new(components, fn {component_name, status_data} ->
      formatted_status = %{
        status: to_string(status_data.status),
        last_check: status_data[:last_check],
        details: Map.drop(status_data, [:monitor, :status, :last_check])
      }

      {component_name, formatted_status}
    end)
  end

  defp recoverable_critical_state?(components) do
    # Consider critical state recoverable if it's only resource-related
    # and not infrastructure failure
    database_status = get_in(components, [:database, :status])

    # If database is healthy, critical state might be recoverable
    database_status == :healthy
  end

  defp format_prometheus_metrics(detailed_status) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    overall_status_numeric = status_to_numeric(detailed_status.overall_status)

    metrics = [
      # Overall health status
      "# HELP rubber_duck_health_status Overall health status (1=healthy, 2=warning, 3=degraded, 4=critical)",
      "# TYPE rubber_duck_health_status gauge",
      "rubber_duck_health_status #{overall_status_numeric} #{timestamp}",
      "",

      # Health percentage
      "# HELP rubber_duck_health_percentage Percentage of healthy components",
      "# TYPE rubber_duck_health_percentage gauge",
      "rubber_duck_health_percentage #{detailed_status.summary.health_percentage} #{timestamp}",
      "",

      # Component counts
      "# HELP rubber_duck_components_total Total number of monitored components",
      "# TYPE rubber_duck_components_total gauge",
      "rubber_duck_components_total #{detailed_status.summary.total_components} #{timestamp}",
      "",
      "# HELP rubber_duck_components_healthy Number of healthy components",
      "# TYPE rubber_duck_components_healthy gauge",
      "rubber_duck_components_healthy #{detailed_status.summary.healthy} #{timestamp}",
      "",

      # Individual component statuses
      "# HELP rubber_duck_component_status Status of individual components (1=healthy, 2=warning, 3=degraded, 4=critical)",
      "# TYPE rubber_duck_component_status gauge"
    ]

    # Add individual component metrics
    component_metrics =
      Enum.flat_map(detailed_status.components, fn {component_name, status_data} ->
        component_status_numeric = status_to_numeric(status_data.status)

        [
          "rubber_duck_component_status{component=\"#{component_name}\"} #{component_status_numeric} #{timestamp}"
        ]
      end)

    (metrics ++ component_metrics)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp status_to_numeric(:healthy), do: 1
  defp status_to_numeric(:warning), do: 2
  defp status_to_numeric(:degraded), do: 3
  defp status_to_numeric(:critical), do: 4
  defp status_to_numeric(:error), do: 4
  defp status_to_numeric(:unavailable), do: 3
  defp status_to_numeric(_), do: 0
end

defmodule RubberDuck.HealthCheck.HTTPServer do
  @moduledoc """
  GenServer wrapper for the Health Check HTTP endpoint.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 4001)

    Logger.info("Starting Health Check HTTP Endpoint on port #{port}")

    # Start the HTTP server with the router
    case start_http_server(port) do
      {:ok, _pid} ->
        {:ok, %{port: port}}

      {:error, reason} ->
        Logger.error("Failed to start health check HTTP server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp start_http_server(port) do
    case Code.ensure_loaded(Plug.Cowboy) do
      {:module, plug_cowboy} ->
        :erlang.apply(plug_cowboy, :http, [RubberDuck.HealthCheck.HTTPEndpoint, [], [port: port]])

      {:error, _} ->
        # Fallback: log that HTTP endpoint is not available
        Logger.warning("Plug.Cowboy not available, health check HTTP endpoint disabled")
        {:ok, nil}
    end
  end
end
