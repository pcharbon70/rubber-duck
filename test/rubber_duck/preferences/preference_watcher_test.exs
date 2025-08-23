defmodule RubberDuck.Preferences.PreferenceWatcherTest do
  # PubSub tests need to be synchronous
  use RubberDuck.DataCase, async: false

  alias RubberDuck.Preferences.PreferenceWatcher

  describe "subscription management" do
    test "subscribes to user preference changes" do
      user_id = generate_uuid()

      assert :ok = PreferenceWatcher.subscribe_user_changes(user_id)

      # Trigger a change notification
      PreferenceWatcher.notify_preference_change(user_id, nil, "test.key", "old", "new")

      # Should receive the notification
      assert_receive {:user_preference_changed, change_event}
      assert change_event.user_id == user_id
      assert change_event.preference_key == "test.key"
      assert change_event.old_value == "old"
      assert change_event.new_value == "new"
    end

    test "subscribes to project preference changes" do
      project_id = generate_uuid()

      assert :ok = PreferenceWatcher.subscribe_project_changes(project_id)

      # Trigger a change notification
      PreferenceWatcher.notify_preference_change(nil, project_id, "test.key", "old", "new")

      # Should receive the notification
      assert_receive {:project_preference_changed, change_event}
      assert change_event.project_id == project_id
      assert change_event.preference_key == "test.key"
    end

    test "subscribes to specific preference key changes" do
      preference_key = "specific.test.key"

      assert :ok = PreferenceWatcher.subscribe_preference_changes(preference_key)

      # Trigger a change notification
      PreferenceWatcher.notify_preference_change("user123", nil, preference_key, "old", "new")

      # Should receive the notification
      assert_receive {:preference_key_changed, change_event}
      assert change_event.preference_key == preference_key
    end

    test "subscribes to all preference changes" do
      assert :ok = PreferenceWatcher.subscribe_all_changes()

      # Trigger a change notification
      PreferenceWatcher.notify_preference_change("user123", "project456", "any.key", "old", "new")

      # Should receive the notification
      assert_receive {:preference_changed, change_event}
      assert change_event.user_id == "user123"
      assert change_event.project_id == "project456"
      assert change_event.preference_key == "any.key"
    end
  end

  describe "project override toggle notifications" do
    test "notifies when project overrides are enabled" do
      project_id = generate_uuid()

      PreferenceWatcher.subscribe_project_changes(project_id)

      PreferenceWatcher.notify_project_overrides_toggled(project_id, true)

      assert_receive {:project_overrides_toggled, event}
      assert event.project_id == project_id
      assert event.enabled == true
    end

    test "notifies when project overrides are disabled" do
      project_id = generate_uuid()

      PreferenceWatcher.subscribe_project_changes(project_id)

      PreferenceWatcher.notify_project_overrides_toggled(project_id, false)

      assert_receive {:project_overrides_toggled, event}
      assert event.project_id == project_id
      assert event.enabled == false
    end
  end

  describe "callback system" do
    test "registers and executes callbacks" do
      test_pid = self()

      callback_fun = fn change_event ->
        send(test_pid, {:callback_executed, change_event})
      end

      assert :ok = PreferenceWatcher.register_callback(:test_callback, callback_fun)

      # Subscribe to all changes to trigger callback
      PreferenceWatcher.subscribe_all_changes()

      # Trigger a change
      PreferenceWatcher.notify_preference_change("user123", nil, "callback.test", "old", "new")

      # Should receive both the PubSub message and callback execution
      assert_receive {:preference_changed, _}
      assert_receive {:callback_executed, change_event}
      assert change_event.preference_key == "callback.test"
    end

    test "unregisters callbacks" do
      test_pid = self()

      callback_fun = fn change_event ->
        send(test_pid, {:callback_executed, change_event})
      end

      PreferenceWatcher.register_callback(:test_callback, callback_fun)
      assert :ok = PreferenceWatcher.unregister_callback(:test_callback)

      # Subscribe to trigger any remaining callbacks
      PreferenceWatcher.subscribe_all_changes()

      # Trigger a change
      PreferenceWatcher.notify_preference_change("user123", nil, "unregister.test", "old", "new")

      # Should only receive PubSub message, not callback
      assert_receive {:preference_changed, _}
      refute_receive {:callback_executed, _}, 100
    end

    test "handles callback errors gracefully" do
      failing_callback = fn _change_event ->
        raise "Intentional test error"
      end

      assert :ok = PreferenceWatcher.register_callback(:failing_callback, failing_callback)

      PreferenceWatcher.subscribe_all_changes()

      # Should not crash when callback fails
      PreferenceWatcher.notify_preference_change("user123", nil, "error.test", "old", "new")

      assert_receive {:preference_changed, _}
      # Process should still be alive
      assert Process.alive?(Process.whereis(PreferenceWatcher))
    end
  end

  describe "debug information" do
    setup do
      user = create_test_user()
      project_id = generate_uuid()

      # Create some test preferences
      {:ok, _} = create_system_default("debug.test1", "default1", "string")
      {:ok, _} = create_system_default("debug.test2", "default2", "string")

      {:ok, _} =
        Preferences.UserPreference.set_preference(
          user.id,
          "debug.test1",
          Jason.encode!("user_override"),
          "User override"
        )

      %{user: user, project_id: project_id}
    end

    test "provides debug information", %{user: user, project_id: project_id} do
      debug_info = PreferenceWatcher.get_debug_info(user.id, project_id)

      assert debug_info.user_id == user.id
      assert debug_info.project_id == project_id
      assert is_boolean(debug_info.project_overrides_enabled)
      assert is_integer(debug_info.user_preference_count)
      assert is_integer(debug_info.project_preference_count)
      assert is_map(debug_info.inheritance_analysis)
      assert %DateTime{} = debug_info.generated_at
    end
  end

  # Helper functions

  defp create_test_user do
    {:ok, user} =
      RubberDuck.Accounts.User.register_with_password(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "password123"
      })

    user
  end

  defp create_system_default(key, value, data_type) do
    Preferences.SystemDefault.seed_default(%{
      preference_key: key,
      default_value: Jason.encode!(value),
      data_type: String.to_atom(data_type),
      category: "test",
      description: "Test preference for #{key}"
    })
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
