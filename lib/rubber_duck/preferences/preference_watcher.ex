defmodule RubberDuck.Preferences.PreferenceWatcher do
  @moduledoc """
  Real-time preference change monitoring and notification system.

  Provides reactive preference updates through Phoenix.PubSub, enabling
  systems to respond immediately to preference changes without polling.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  alias RubberDuck.Preferences.Resources.{
    ProjectPreference,
    ProjectPreferenceEnabled,
    SystemDefault,
    UserPreference
  }

  @pubsub_module RubberDuck.PubSub
  @preference_topic "preference_changes"

  # Public API

  @doc """
  Subscribe to preference changes for a specific user.
  """
  @spec subscribe_user_changes(user_id :: binary()) :: :ok | {:error, term()}
  def subscribe_user_changes(user_id) do
    PubSub.subscribe(@pubsub_module, "#{@preference_topic}:user:#{user_id}")
  end

  @doc """
  Subscribe to preference changes for a specific project.
  """
  @spec subscribe_project_changes(project_id :: binary()) :: :ok | {:error, term()}
  def subscribe_project_changes(project_id) do
    PubSub.subscribe(@pubsub_module, "#{@preference_topic}:project:#{project_id}")
  end

  @doc """
  Subscribe to all preference changes.
  """
  @spec subscribe_all_changes() :: :ok | {:error, term()}
  def subscribe_all_changes do
    PubSub.subscribe(@pubsub_module, @preference_topic)
  end

  @doc """
  Subscribe to changes for a specific preference key.
  """
  @spec subscribe_preference_changes(preference_key :: String.t()) :: :ok | {:error, term()}
  def subscribe_preference_changes(preference_key) do
    PubSub.subscribe(@pubsub_module, "#{@preference_topic}:key:#{preference_key}")
  end

  @doc """
  Notify subscribers that project overrides have been enabled/disabled.
  """
  @spec notify_project_overrides_toggled(project_id :: binary(), enabled :: boolean()) :: :ok
  def notify_project_overrides_toggled(project_id, enabled) do
    event = %{
      project_id: project_id,
      enabled: enabled,
      changed_at: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      @pubsub_module,
      "#{@preference_topic}:project:#{project_id}",
      {:project_overrides_toggled, event}
    )

    Logger.info(
      "Project overrides #{if enabled, do: "enabled", else: "disabled"} for project #{project_id}"
    )

    :ok
  end

  @doc """
  Notify subscribers of a preference change.
  """
  @spec notify_preference_change(
          user_id :: binary() | nil,
          project_id :: binary() | nil,
          preference_key :: String.t(),
          old_value :: any(),
          new_value :: any()
        ) :: :ok
  def notify_preference_change(user_id, project_id, preference_key, old_value, new_value) do
    change_event = %{
      user_id: user_id,
      project_id: project_id,
      preference_key: preference_key,
      old_value: old_value,
      new_value: new_value,
      changed_at: DateTime.utc_now()
    }

    # Broadcast to all preference change subscribers
    PubSub.broadcast(@pubsub_module, @preference_topic, {:preference_changed, change_event})

    # Broadcast to user-specific subscribers
    if user_id do
      PubSub.broadcast(
        @pubsub_module,
        "#{@preference_topic}:user:#{user_id}",
        {:user_preference_changed, change_event}
      )
    end

    # Broadcast to project-specific subscribers
    if project_id do
      PubSub.broadcast(
        @pubsub_module,
        "#{@preference_topic}:project:#{project_id}",
        {:project_preference_changed, change_event}
      )
    end

    # Broadcast to preference-key-specific subscribers
    PubSub.broadcast(
      @pubsub_module,
      "#{@preference_topic}:key:#{preference_key}",
      {:preference_key_changed, change_event}
    )

    # Emit telemetry event
    :telemetry.execute(
      [:rubber_duck, :preferences, :change_notified],
      %{count: 1},
      change_event
    )

    :ok
  end

  @doc """
  Register a callback function to be called on preference changes.
  """
  @spec register_callback(callback_id :: atom(), callback_fun :: function()) :: :ok
  def register_callback(callback_id, callback_fun) when is_function(callback_fun, 1) do
    GenServer.call(__MODULE__, {:register_callback, callback_id, callback_fun})
  end

  @doc """
  Unregister a preference change callback.
  """
  @spec unregister_callback(callback_id :: atom()) :: :ok
  def unregister_callback(callback_id) do
    GenServer.call(__MODULE__, {:unregister_callback, callback_id})
  end

  @doc """
  Get debug information about preference resolution for a user/project.
  """
  @spec get_debug_info(user_id :: binary(), project_id :: binary() | nil) :: map()
  def get_debug_info(user_id, project_id \\ nil) do
    %{
      user_id: user_id,
      project_id: project_id,
      project_overrides_enabled: project_id && project_overrides_enabled?(project_id),
      user_preference_count: count_user_preferences(user_id),
      project_preference_count:
        if(project_id, do: count_project_preferences(project_id), else: 0),
      inheritance_analysis: analyze_user_inheritance(user_id, project_id),
      generated_at: DateTime.utc_now()
    }
  end

  # GenServer implementation

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to our own preference change events to trigger callbacks
    PubSub.subscribe(@pubsub_module, @preference_topic)

    Logger.info("PreferenceWatcher started")

    {:ok, %{callbacks: %{}}}
  end

  @impl true
  def handle_call({:register_callback, callback_id, callback_fun}, _from, state) do
    new_callbacks = Map.put(state.callbacks, callback_id, callback_fun)
    Logger.debug("Registered preference change callback: #{callback_id}")
    {:reply, :ok, %{state | callbacks: new_callbacks}}
  end

  @impl true
  def handle_call({:unregister_callback, callback_id}, _from, state) do
    new_callbacks = Map.delete(state.callbacks, callback_id)
    Logger.debug("Unregistered preference change callback: #{callback_id}")
    {:reply, :ok, %{state | callbacks: new_callbacks}}
  end

  @impl true
  def handle_info({:preference_changed, change_event}, state) do
    # Execute all registered callbacks
    Enum.each(state.callbacks, fn {callback_id, callback_fun} ->
      try do
        callback_fun.(change_event)
      rescue
        error ->
          Logger.error(
            "Preference change callback failed: #{callback_id}, error: #{inspect(error)}"
          )
      end
    end)

    {:noreply, state}
  end

  # Private functions

  defp project_overrides_enabled?(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [%{enabled: true}]} -> true
      _ -> false
    end
  end

  defp count_user_preferences(user_id) do
    case UserPreference.by_user(user_id) do
      {:ok, preferences} -> length(Enum.filter(preferences, & &1.active))
      {:error, _} -> 0
    end
  end

  defp count_project_preferences(project_id) do
    case ProjectPreference.active_for_project(project_id) do
      {:ok, preferences} -> length(preferences)
      {:error, _} -> 0
    end
  end

  # These functions are moved from InheritanceTracker for analyze_user_inheritance
  defp analyze_user_inheritance(user_id, project_id) do
    # Get all system defaults as baseline
    all_preference_keys = get_all_preference_keys()

    # Count preferences by source

    # Count user preferences
    user_override_count = count_user_preferences(user_id)

    # Count project preferences if applicable
    project_override_count =
      if project_id && project_overrides_enabled?(project_id) do
        count_project_preferences(project_id)
      else
        0
      end

    total_preferences = length(all_preference_keys)
    system_default_count = total_preferences - user_override_count - project_override_count

    %{
      total_preferences: total_preferences,
      system_defaults: max(0, system_default_count),
      user_overrides: user_override_count,
      project_overrides: project_override_count,
      override_percentage:
        if(total_preferences > 0,
          do: (user_override_count + project_override_count) / total_preferences * 100,
          else: 0.0
        )
    }
  end

  defp get_all_preference_keys do
    case SystemDefault.non_deprecated() do
      {:ok, defaults} -> Enum.map(defaults, & &1.preference_key)
      {:error, _} -> []
    end
  end
end
