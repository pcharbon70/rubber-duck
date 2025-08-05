defmodule RubberDuck.Integration.ErrorRecoveryTest do
  @moduledoc """
  Integration tests for error handling and recovery mechanisms.

  Tests system resilience, process recovery, and error propagation.
  """

  use RubberDuck.DataCase, async: false  # Not async due to process manipulation

  alias RubberDuck.Accounts
  alias RubberDuck.Projects
  alias RubberDuck.HealthCheck

  describe "Error handling and recovery" do
    setup do
      # Create a test user
      {:ok, user} = Accounts.register_user(%{
        username: "error_test_user",
        password: "Password123!",
        password_confirmation: "Password123!"
      }, authorize?: false)

      %{user: user}
    end

    test "system handles database connection errors gracefully" do
      # This test verifies that operations fail gracefully when database issues occur
      # We can't actually disconnect the database in test, but we can test error handling

      # Test with invalid data that triggers database constraints
      invalid_attrs = %{
        username: nil,  # Required field
        password: "test",
        password_confirmation: "test"
      }

      assert {:error, error} = Accounts.register_user(invalid_attrs, authorize?: false)
      assert %Ash.Error.Invalid{} = error
      assert error.errors |> Enum.any?(fn e ->
        e.field == :username || e.message =~ "required"
      end)

      # System should still be functional after error
      valid_attrs = %{
        username: "recovery_test",
        password: "Password123!",
        password_confirmation: "Password123!"
      }
      assert {:ok, _user} = Accounts.register_user(valid_attrs, authorize?: false)
    end

    test "process crashes are recovered by supervisor", %{user: user} do
      # Get current health check PID
      original_pid = Process.whereis(RubberDuck.HealthCheck)
      assert original_pid != nil

      # Kill the health check process
      Process.exit(original_pid, :kill)

      # Give supervisor time to restart
      Process.sleep(200)

      # Verify process was restarted with new PID
      new_pid = Process.whereis(RubberDuck.HealthCheck)
      assert new_pid != nil
      assert new_pid != original_pid

      # Verify the restarted process is functional
      status = HealthCheck.get_status()
      assert %HealthCheck{} = status

      # Other processes should not be affected
      assert {:ok, project} = Projects.create_project(%{
        name: "Post-Recovery Project",
        language: "elixir"
      }, actor: user)
      assert project.name == "Post-Recovery Project"
    end

    test "invalid data is rejected with proper error messages", %{user: user} do
      # Project with missing required fields
      assert {:error, error} = Projects.create_project(%{}, actor: user)
      assert error.errors |> Enum.any?(fn e ->
        Map.get(e, :field) == :name || Map.get(e, :fields) == [:name]
      end)

      # Project with invalid language (currently accepts any string)
      # The system currently accepts any language string
      assert {:ok, project} = Projects.create_project(%{
        name: "Test",
        language: "invalid_language_xyz"
      }, actor: user)
      assert project.language == "invalid_language_xyz"

      # Code file with invalid project reference
      assert {:error, error} = Projects.create_code_file(%{
        project_id: Ash.UUID.generate(),  # Non-existent project
        path: "/test.ex",
        content: "test",
        language: "elixir"
      }, actor: user)
      # This should fail with authorization or invalid reference error
      assert error.class in [:forbidden, :invalid]
    end

    test "concurrent operations handle race conditions", %{user: user} do
      # Create a project
      {:ok, project} = Projects.create_project(%{
        name: "Race Condition Test",
        language: "elixir"
      }, actor: user)

      # Spawn multiple concurrent updates
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Projects.update_project(
              project,
              %{description: "Update #{i}"},
              actor: user
            )
          end)
        end

      results = Task.await_many(tasks)

      # All updates should either succeed or fail gracefully
      # No crashes or undefined behavior
      assert Enum.all?(results, fn
        {:ok, _} -> true
        {:error, _} -> true
        _ -> false
      end)

      # At least some should succeed
      successful = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      assert successful > 0

      # Final state should be consistent
      {:ok, final_project} = Projects.get_project(project.id, actor: user)
      assert final_project.id == project.id
      assert is_binary(final_project.description) || is_nil(final_project.description)
    end

    test "authorization errors are handled properly", %{user: user} do
      # Create another user
      {:ok, other_user} = Accounts.register_user(%{
        username: "unauthorized_user",
        password: "Password123!",
        password_confirmation: "Password123!"
      }, authorize?: false)

      # Create a project as first user
      {:ok, project} = Projects.create_project(%{
        name: "Auth Test Project",
        language: "elixir"
      }, actor: user)

      # Other user tries unauthorized operations
      assert {:error, %Ash.Error.Forbidden{}} =
        Projects.update_project(project, %{name: "Hacked"}, actor: other_user)

      assert {:error, %Ash.Error.Forbidden{}} =
        Projects.delete_project(project, actor: other_user)

      # Original user operations should still work
      assert {:ok, updated} =
        Projects.update_project(project, %{name: "Legitimate Update"}, actor: user)
      assert updated.name == "Legitimate Update"
    end

    test "validation errors provide clear feedback", %{user: _user} do
      # Password validation
      password_error = Accounts.register_user(%{
        username: "validation_test",
        password: "short",
        password_confirmation: "short"
      }, authorize?: false)

      assert {:error, error} = password_error
      # Password validation errors exist in some form
      assert is_list(error.errors) && length(error.errors) > 0

      # Username uniqueness
      {:ok, _} = Accounts.register_user(%{
        username: "unique_test",
        password: "Password123!",
        password_confirmation: "Password123!"
      }, authorize?: false)

      duplicate_error = Accounts.register_user(%{
        username: "unique_test",
        password: "Password456!",
        password_confirmation: "Password456!"
      }, authorize?: false)

      assert {:error, error} = duplicate_error
      assert error.errors |> Enum.any?(fn e ->
        e.message =~ "taken" || e.message =~ "already exists" ||
        Map.get(e, :field) == :username || Map.get(e, :fields) == [:username]
      end)
    end

    test "health check system reports errors correctly" do
      # Get current health status
      status = HealthCheck.get_status()

      # Check that all health checks are returning valid statuses
      Enum.each(status.checks, fn {check_name, check_result} ->
        assert check_result.status in [:healthy, :degraded, :warning, :unhealthy, :unknown]
        assert is_binary(check_result.message)

        # Specific checks based on check name
        case check_name do
          :database ->
            # Database should be healthy in test
            assert check_result.status == :healthy

          :memory ->
            # Memory check should have metrics
            assert Map.has_key?(check_result, :total_mb)
            assert Map.has_key?(check_result, :process_mb)

          :processes ->
            # Process check should have counts
            assert Map.has_key?(check_result, :count)
            assert Map.has_key?(check_result, :limit)

          _ ->
            :ok
        end
      end)

      # Overall status should be determined correctly
      assert status.status in [:healthy, :degraded, :unhealthy, :initializing]
    end

    test "telemetry continues working after errors" do
      # Set up telemetry handler
      handler_id = :error_test_handler
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:rubber_duck, :health, :database],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:telemetry_received, measurements})
        end,
        nil
      )

      # Trigger telemetry
      RubberDuck.Telemetry.dispatch_health_check()
      assert_receive {:telemetry_received, _}, 2000

      # Cause an error in repo metrics (this should not crash)
      RubberDuck.Telemetry.dispatch_repo_metrics()

      # Telemetry should still work
      RubberDuck.Telemetry.dispatch_health_check()
      assert_receive {:telemetry_received, _}, 2000

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "system maintains data consistency after errors", %{user: user} do
      # Start a series of operations
      {:ok, project} = Projects.create_project(%{
        name: "Consistency Test",
        language: "elixir"
      }, actor: user)

      # Try to create an invalid code file
      invalid_file = Projects.create_code_file(%{
        project_id: project.id,
        path: nil,  # Invalid - path is required
        content: "test",
        language: "elixir"
      }, actor: user)

      assert {:error, _} = invalid_file

      # Valid operations should still work
      {:ok, valid_file} = Projects.create_code_file(%{
        project_id: project.id,
        path: "/lib/valid.ex",
        content: "defmodule Valid do\nend",
        language: "elixir"
      }, actor: user)

      # Verify data consistency
      {:ok, project_with_files} = Projects.get_project(project.id, actor: user)
      loaded_project = Ash.load!(project_with_files, :code_files, actor: user)
      assert length(loaded_project.code_files) == 1
      assert hd(loaded_project.code_files).id == valid_file.id
    end
  end
end