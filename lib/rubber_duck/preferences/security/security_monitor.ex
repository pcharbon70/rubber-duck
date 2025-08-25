defmodule RubberDuck.Preferences.Security.SecurityMonitor do
  @moduledoc """
  Security monitoring and anomaly detection for preference operations.

  Monitors preference access patterns, detects suspicious activities,
  and triggers security alerts for potential threats or policy violations.
  Integrates with the audit logging system for comprehensive security oversight.
  """

  use GenServer

  alias RubberDuck.Preferences.Security.AuditLogger

  require Logger

  # 5 minutes
  @monitoring_window 300_000
  @alert_thresholds %{
    failed_access_attempts: 5,
    rapid_preference_changes: 20,
    sensitive_access_frequency: 10,
    unusual_access_patterns: 3
  }

  defstruct [
    :user_activity,
    :alert_thresholds,
    :monitoring_config
  ]

  ## Public API

  @doc """
  Start the security monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Monitor a preference access event for security anomalies.
  """
  @spec monitor_access(event :: map()) :: :ok
  def monitor_access(event) do
    GenServer.cast(__MODULE__, {:monitor_access, event})
  end

  @doc """
  Monitor a preference change event for security anomalies.
  """
  @spec monitor_change(event :: map()) :: :ok
  def monitor_change(event) do
    GenServer.cast(__MODULE__, {:monitor_change, event})
  end

  @doc """
  Get current security monitoring statistics.
  """
  @spec get_security_stats() :: {:ok, map()} | {:error, term()}
  def get_security_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Get security alerts for a time period.
  """
  @spec get_alerts(since :: DateTime.t()) :: {:ok, [map()]} | {:error, term()}
  def get_alerts(since \\ DateTime.add(DateTime.utc_now(), -24 * 3600, :second)) do
    GenServer.call(__MODULE__, {:get_alerts, since})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = %{
      monitoring_window: Keyword.get(opts, :monitoring_window, @monitoring_window),
      alert_thresholds: Keyword.get(opts, :alert_thresholds, @alert_thresholds)
    }

    state = %__MODULE__{
      user_activity: %{},
      alert_thresholds: config.alert_thresholds,
      monitoring_config: config
    }

    # Schedule periodic cleanup of old activity data
    schedule_cleanup()

    {:ok, state}
  end

  @impl true
  def handle_cast({:monitor_access, event}, state) do
    new_state =
      state
      |> track_user_activity(event)
      |> check_access_anomalies(event)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:monitor_change, event}, state) do
    new_state =
      state
      |> track_user_activity(event)
      |> check_change_anomalies(event)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_security_stats(state)
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call({:get_alerts, since}, _from, state) do
    alerts = get_recent_alerts(since)
    {:reply, {:ok, alerts}, state}
  end

  @impl true
  def handle_info(:cleanup_activity, state) do
    new_state = cleanup_old_activity(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  ## Private Functions

  defp track_user_activity(state, event) do
    user_id = event.user_id || "anonymous"
    current_time = DateTime.utc_now()

    user_activity =
      Map.get(state.user_activity, user_id, %{
        access_events: [],
        change_events: [],
        last_activity: current_time
      })

    updated_activity =
      case event.action do
        action when action in ["read", "access"] ->
          %{
            user_activity
            | access_events: [event | user_activity.access_events] |> Enum.take(100),
              last_activity: current_time
          }

        action when action in ["create", "update", "delete"] ->
          %{
            user_activity
            | change_events: [event | user_activity.change_events] |> Enum.take(100),
              last_activity: current_time
          }

        _ ->
          %{user_activity | last_activity: current_time}
      end

    %{state | user_activity: Map.put(state.user_activity, user_id, updated_activity)}
  end

  defp check_access_anomalies(state, event) do
    user_id = event.user_id
    user_activity = Map.get(state.user_activity, user_id, %{access_events: []})

    # Check for rapid access attempts
    recent_access = get_recent_events(user_activity.access_events, @monitoring_window)

    if length(recent_access) > state.alert_thresholds.failed_access_attempts do
      trigger_security_alert(%{
        type: "rapid_access_attempts",
        user_id: user_id,
        event_count: length(recent_access),
        threshold: state.alert_thresholds.failed_access_attempts,
        timeframe: @monitoring_window,
        severity: "medium"
      })
    end

    # Check for sensitive preference access patterns
    if sensitive_preference?(event.preference_key) do
      check_sensitive_access_patterns(user_activity, event, state.alert_thresholds)
    end

    state
  end

  defp check_change_anomalies(state, event) do
    user_id = event.user_id
    user_activity = Map.get(state.user_activity, user_id, %{change_events: []})

    # Check for rapid preference changes
    recent_changes = get_recent_events(user_activity.change_events, @monitoring_window)

    if length(recent_changes) > state.alert_thresholds.rapid_preference_changes do
      trigger_security_alert(%{
        type: "rapid_preference_changes",
        user_id: user_id,
        change_count: length(recent_changes),
        threshold: state.alert_thresholds.rapid_preference_changes,
        timeframe: @monitoring_window,
        severity: "high"
      })
    end

    # Check for bulk sensitive preference changes
    sensitive_changes =
      Enum.filter(recent_changes, fn change_event ->
        sensitive_preference?(change_event.preference_key)
      end)

    if length(sensitive_changes) > 3 do
      trigger_security_alert(%{
        type: "bulk_sensitive_changes",
        user_id: user_id,
        sensitive_change_count: length(sensitive_changes),
        severity: "critical"
      })
    end

    state
  end

  defp check_sensitive_access_patterns(user_activity, event, thresholds) do
    sensitive_access =
      Enum.filter(user_activity.access_events, fn access_event ->
        sensitive_preference?(access_event.preference_key)
      end)

    recent_sensitive = get_recent_events(sensitive_access, @monitoring_window)

    if length(recent_sensitive) > thresholds.sensitive_access_frequency do
      trigger_security_alert(%{
        type: "excessive_sensitive_access",
        user_id: event.user_id,
        access_count: length(recent_sensitive),
        threshold: thresholds.sensitive_access_frequency,
        severity: "high"
      })
    end
  end

  defp get_recent_events(events, window_ms) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -window_ms, :millisecond)

    Enum.filter(events, fn event ->
      event_time = event.timestamp || DateTime.utc_now()
      DateTime.compare(event_time, cutoff_time) == :gt
    end)
  end

  defp sensitive_preference?(preference_key) do
    RubberDuck.Preferences.Security.EncryptionManager.sensitive_preference?(preference_key)
  end

  defp trigger_security_alert(alert_data) do
    Logger.warning("Security Alert: #{alert_data.type} - #{inspect(alert_data)}")

    # Log to audit system
    AuditLogger.log_security_event(
      Map.merge(alert_data, %{
        alert_triggered: true,
        timestamp: DateTime.utc_now()
      })
    )

    # In a full implementation, this would also:
    # 1. Send notifications to security team
    # 2. Update security dashboards
    # 3. Potentially trigger automatic responses
    # 4. Integrate with external security systems
  end

  defp calculate_security_stats(state) do
    total_users = map_size(state.user_activity)
    active_users = count_active_users(state.user_activity)

    %{
      total_monitored_users: total_users,
      active_users_last_hour: active_users,
      monitoring_window_ms: state.monitoring_config.monitoring_window,
      alert_thresholds: state.alert_thresholds,
      last_cleanup: DateTime.utc_now()
    }
  end

  defp count_active_users(user_activity) do
    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    Enum.count(user_activity, fn {_user_id, activity} ->
      DateTime.compare(activity.last_activity, one_hour_ago) == :gt
    end)
  end

  defp get_recent_alerts(_since) do
    # This would query the audit log for recent security events
    # For now, return empty list
    []
  end

  defp cleanup_old_activity(state) do
    # 24 hours
    cutoff_time = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)

    cleaned_activity =
      Enum.reduce(state.user_activity, %{}, fn {user_id, activity}, acc ->
        if DateTime.compare(activity.last_activity, cutoff_time) == :gt do
          Map.put(acc, user_id, activity)
        else
          acc
        end
      end)

    %{state | user_activity: cleaned_activity}
  end

  defp schedule_cleanup do
    # 1 hour
    Process.send_after(self(), :cleanup_activity, 3_600_000)
  end
end
