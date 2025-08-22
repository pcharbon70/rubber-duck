defmodule RubberDuck.HealthCheck.ServiceMonitor do
  @moduledoc """
  Service availability health monitor.

  Monitors:
  - Phoenix PubSub availability
  - Oban job processing system
  - Skills Registry availability
  - Directives Engine availability
  - Instructions Processor availability
  """

  use GenServer
  require Logger

  alias RubberDuck.Telemetry.VMMetrics

  # 20 seconds
  @check_interval 20_000

  defstruct [
    :timer_ref,
    :last_check,
    :health_status,
    :service_statuses,
    :failure_counts
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Service Health Monitor")

    # Perform initial check
    send(self(), :perform_service_check)

    state = %__MODULE__{
      timer_ref: nil,
      last_check: nil,
      health_status: :unknown,
      service_statuses: %{},
      failure_counts: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_report = %{
      status: state.health_status,
      last_check: state.last_check,
      services: state.service_statuses,
      failure_counts: state.failure_counts
    }

    {:reply, health_report, state}
  end

  @impl true
  def handle_cast(:force_check, state) do
    new_state = perform_service_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:perform_service_check, state) do
    new_state = perform_service_check(state)

    # Schedule next check
    timer_ref = Process.send_after(self(), :perform_service_check, @check_interval)
    final_state = %{new_state | timer_ref: timer_ref}

    {:noreply, final_state}
  end

  ## Internal Functions

  defp perform_service_check(state) do
    case safe_service_check(state) do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Service health check failed: #{inspect(error)}")
        %{state | health_status: :critical, last_check: DateTime.utc_now()}
    end
  end

  defp safe_service_check(state) do
    # Check all services
    service_statuses = check_all_services()

    # Update failure counts
    failure_counts = update_failure_counts(service_statuses, state.failure_counts)

    # Determine overall service health
    health_status = determine_service_health(service_statuses)

    # Emit telemetry
    emit_service_telemetry(health_status, service_statuses)

    result = %{
      state
      | health_status: health_status,
        last_check: DateTime.utc_now(),
        service_statuses: service_statuses,
        failure_counts: failure_counts
    }

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp check_all_services do
    %{
      pubsub: check_pubsub_service(),
      oban: check_oban_service(),
      skills_registry: check_skills_registry_service(),
      directives_engine: check_directives_engine_service(),
      instructions_processor: check_instructions_processor_service(),
      telemetry: check_telemetry_service(),
      web_endpoint: check_web_endpoint_service()
    }
  end

  defp check_pubsub_service do
    case safe_pubsub_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_pubsub_check do
    case GenServer.whereis(RubberDuck.PubSub) do
      nil ->
        {:ok, %{status: :critical, error: "PubSub process not running"}}

      pid when is_pid(pid) ->
        test_topic = "health_check_#{:rand.uniform(10_000)}"

        # Subscribe to test topic
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, test_topic)

        # Broadcast test message
        Phoenix.PubSub.broadcast(RubberDuck.PubSub, test_topic, :health_check)

        # Check if we receive the message
        result =
          receive do
            :health_check -> %{status: :healthy}
          after
            1000 -> %{status: :degraded, error: "PubSub message delivery timeout"}
          end

        {:ok, result}
    end
  rescue
    error -> {:error, error}
  end

  defp check_oban_service do
    case safe_oban_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_oban_check do
    case GenServer.whereis(Oban) do
      nil ->
        {:ok, %{status: :critical, error: "Oban process not running"}}

      _pid ->
        case Oban.check_queue(Oban, queue: :default) do
          :ok -> {:ok, %{status: :healthy}}
          error -> {:ok, %{status: :degraded, error: inspect(error)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_skills_registry_service do
    case safe_skills_registry_service_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_skills_registry_service_check do
    case GenServer.whereis(RubberDuck.SkillsRegistry) do
      nil ->
        {:ok, %{status: :critical, error: "Skills Registry not running"}}

      _pid ->
        case RubberDuck.SkillsRegistry.discover_skills() do
          {:ok, _skills} -> {:ok, %{status: :healthy}}
          {:error, reason} -> {:ok, %{status: :degraded, error: inspect(reason)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_directives_engine_service do
    case safe_directives_engine_service_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_directives_engine_service_check do
    case GenServer.whereis(RubberDuck.DirectivesEngine) do
      nil ->
        {:ok, %{status: :critical, error: "Directives Engine not running"}}

      _pid ->
        test_directive = %{
          type: :behavior_modification,
          target: :all,
          parameters: %{behavior_type: :test, modification_type: :test}
        }

        case RubberDuck.DirectivesEngine.validate_directive(test_directive) do
          :ok -> {:ok, %{status: :healthy}}
          {:error, reason} -> {:ok, %{status: :degraded, error: inspect(reason)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_instructions_processor_service do
    case safe_instructions_processor_service_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_instructions_processor_service_check do
    case GenServer.whereis(RubberDuck.InstructionsProcessor) do
      nil ->
        {:ok, %{status: :critical, error: "Instructions Processor not running"}}

      _pid ->
        test_instruction = %{
          type: :skill_invocation,
          action: "test_action",
          parameters: %{}
        }

        case RubberDuck.InstructionsProcessor.normalize_instruction(test_instruction) do
          {:ok, _normalized} -> {:ok, %{status: :healthy}}
          {:error, reason} -> {:ok, %{status: :degraded, error: inspect(reason)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_telemetry_service do
    case safe_telemetry_service_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :warning, error: inspect(error)}
    end
  end

  defp safe_telemetry_service_check do
    case GenServer.whereis(RubberDuck.Telemetry.VMMetrics) do
      nil ->
        {:ok, %{status: :warning, error: "VM Metrics collector not running"}}

      _pid ->
        case VMMetrics.get_current_metrics() do
          metrics when is_map(metrics) -> {:ok, %{status: :healthy}}
          _ -> {:ok, %{status: :degraded, error: "Telemetry data unavailable"}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_web_endpoint_service do
    case safe_web_endpoint_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_web_endpoint_check do
    case GenServer.whereis(RubberDuckWeb.Endpoint) do
      nil ->
        {:ok, %{status: :critical, error: "Web Endpoint not running"}}

      _pid ->
        port = RubberDuckWeb.Endpoint.config(:http)[:port]

        case :gen_tcp.connect(~c"localhost", port, [], 1000) do
          {:ok, socket} ->
            :gen_tcp.close(socket)
            {:ok, %{status: :healthy}}

          {:error, reason} ->
            {:ok,
             %{status: :degraded, error: "Port #{port} not accepting connections: #{reason}"}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp update_failure_counts(service_statuses, previous_counts) do
    Map.new(service_statuses, fn {service_name, service_status} ->
      previous_count = Map.get(previous_counts, service_name, 0)

      new_count =
        case service_status.status do
          # Reset counter on success
          :healthy -> 0
          # Increment on failure
          _ -> previous_count + 1
        end

      {service_name, new_count}
    end)
  end

  defp determine_service_health(service_statuses) do
    statuses =
      service_statuses
      |> Map.values()
      |> Enum.map(& &1.status)

    cond do
      :critical in statuses -> :critical
      :degraded in statuses -> :degraded
      :warning in statuses -> :warning
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      true -> :unknown
    end
  end

  defp emit_service_telemetry(overall_status, service_statuses) do
    # Emit individual service telemetries
    Enum.each(service_statuses, fn {service_name, status_data} ->
      :telemetry.execute(
        [:rubber_duck, :health_check, :services, service_name],
        %{status_numeric: status_to_numeric(status_data.status)},
        %{status: status_data.status, service: service_name}
      )
    end)

    # Emit overall services status
    :telemetry.execute(
      [:rubber_duck, :health_check, :services],
      %{status_numeric: status_to_numeric(overall_status)},
      %{status: overall_status, services: service_statuses}
    )
  end

  defp status_to_numeric(:healthy), do: 1
  defp status_to_numeric(:warning), do: 2
  defp status_to_numeric(:degraded), do: 3
  defp status_to_numeric(:critical), do: 4
  defp status_to_numeric(_), do: 0
end
