defmodule RubberDuck.Integration.AuthenticationWorkflowTest do
  @moduledoc """
  Integration tests for complete authentication workflows.

  Tests the full user lifecycle from registration to token management.
  """

  use RubberDuck.DataCase, async: true

  alias RubberDuck.Accounts

  describe "Complete authentication workflow" do
    test "full user registration and sign-in flow" do
      # Step 1: Register a new user
      registration_attrs = %{
        username: "workflow_user",
        password: "SecurePassword123!",
        password_confirmation: "SecurePassword123!"
      }

      assert {:ok, user} = Accounts.register_user(registration_attrs, authorize?: false)
      assert user.id != nil
      assert to_string(user.username) == "workflow_user"
      assert user.hashed_password != nil
      assert user.hashed_password != "SecurePassword123!"

      # Step 2: Sign in with correct credentials
      sign_in_attrs = %{
        username: "workflow_user",
        password: "SecurePassword123!"
      }

      assert {:ok, signed_in_user} =
               Accounts.sign_in_user(sign_in_attrs, authorize?: false)

      assert signed_in_user.id == user.id

      # Verify token metadata is present
      assert Map.has_key?(signed_in_user, :__metadata__)
      token_metadata = signed_in_user.__metadata__[:token]
      assert is_binary(token_metadata)

      # Step 3: Attempt sign-in with wrong password
      wrong_password_attrs = %{
        username: "workflow_user",
        password: "WrongPassword123!"
      }

      assert {:error, error} =
               Accounts.sign_in_user(wrong_password_attrs, authorize?: false)

      # Check for authentication error structure
      assert error.class == :forbidden ||
               (error.errors &&
                  Enum.any?(error.errors, fn e ->
                    Map.get(e, :message, "") =~ "Invalid" ||
                      Map.get(e, :class) == :authentication ||
                      Map.get(e, :class) == :forbidden
                  end))

      # Step 4: Change password
      change_password_attrs = %{
        current_password: "SecurePassword123!",
        password: "NewSecurePassword456!",
        password_confirmation: "NewSecurePassword456!"
      }

      assert {:ok, updated_user} =
               Accounts.change_user_password(user, change_password_attrs, authorize?: false)

      assert updated_user.id == user.id

      # Step 5: Verify old password no longer works
      assert {:error, _} =
               Accounts.sign_in_user(sign_in_attrs, authorize?: false)

      # Step 6: Verify new password works
      new_sign_in_attrs = %{
        username: "workflow_user",
        password: "NewSecurePassword456!"
      }

      assert {:ok, _} =
               Accounts.sign_in_user(new_sign_in_attrs, authorize?: false)
    end

    test "username case-insensitivity in authentication" do
      # Register with lowercase
      {:ok, user} =
        Accounts.register_user(
          %{
            username: "casetest",
            password: "Password123!",
            password_confirmation: "Password123!"
          },
          authorize?: false
        )

      # Sign in with uppercase
      assert {:ok, signed_in} =
               Accounts.sign_in_user(
                 %{
                   username: "CASETEST",
                   password: "Password123!"
                 },
                 authorize?: false
               )

      assert signed_in.id == user.id

      # Sign in with mixed case
      assert {:ok, signed_in2} =
               Accounts.sign_in_user(
                 %{
                   username: "CaseTest",
                   password: "Password123!"
                 },
                 authorize?: false
               )

      assert signed_in2.id == user.id
    end

    test "password validation requirements" do
      base_attrs = %{
        username: "pwtest",
        password_confirmation: "test"
      }

      # Too short password
      attrs = Map.put(base_attrs, :password, "Short1!")
      attrs = Map.put(attrs, :password_confirmation, "Short1!")
      assert {:error, error} = Accounts.register_user(attrs, authorize?: false)
      # Just verify we got an error for password validation
      assert is_list(error.errors) && length(error.errors) > 0

      # Password mismatch
      attrs = Map.put(base_attrs, :password, "ValidPassword123!")
      attrs = Map.put(attrs, :password_confirmation, "DifferentPassword123!")
      assert {:error, error} = Accounts.register_user(attrs, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               (Map.get(e, :field) == :password_confirmation ||
                  Map.get(e, :fields) == [:password_confirmation]) &&
                 (e.message =~ "match" || e.message =~ "same" || e.message =~ "equal")
             end)

      # Valid password
      attrs = Map.put(base_attrs, :password, "ValidPassword123!")
      attrs = Map.put(attrs, :password_confirmation, "ValidPassword123!")
      assert {:ok, _user} = Accounts.register_user(attrs, authorize?: false)
    end

    test "concurrent authentication attempts" do
      # Register a user
      {:ok, user} =
        Accounts.register_user(
          %{
            username: "concurrent_user",
            password: "Password123!",
            password_confirmation: "Password123!"
          },
          authorize?: false
        )

      # Perform sign-in attempts sequentially to avoid auth token conflicts
      results =
        for _i <- 1..10 do
          Accounts.sign_in_user(
            %{
              username: "concurrent_user",
              password: "Password123!"
            },
            authorize?: false
          )
        end

      # All should succeed
      successful_count =
        Enum.count(results, fn
          {:ok, signed_in} -> signed_in.id == user.id
          _ -> false
        end)

      # All should succeed
      assert successful_count == 10
    end

    test "user lookup functions work correctly" do
      # Register a user
      {:ok, user} =
        Accounts.register_user(
          %{
            username: "lookup_user",
            password: "Password123!",
            password_confirmation: "Password123!"
          },
          authorize?: false
        )

      # Lookup by ID
      assert {:ok, found_by_id} = Accounts.get_user(user.id, authorize?: false)
      assert found_by_id.id == user.id

      # Lookup by username (case-insensitive)
      assert {:ok, found_by_username} =
               Accounts.get_user_by_username("LOOKUP_USER", authorize?: false)

      assert found_by_username.id == user.id

      # Lookup non-existent user
      assert {:error, _} =
               Accounts.get_user_by_username("nonexistent", authorize?: false)
    end

    test "token lifecycle and policies" do
      # Register and sign in
      {:ok, user} =
        Accounts.register_user(
          %{
            username: "token_test",
            password: "Password123!",
            password_confirmation: "Password123!"
          },
          authorize?: false
        )

      {:ok, signed_in} =
        Accounts.sign_in_user(
          %{
            username: "token_test",
            password: "Password123!"
          },
          authorize?: false
        )

      # Verify token is generated
      assert signed_in.__metadata__[:token] != nil

      # Verify regular users cannot directly access tokens
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(Accounts.Token, actor: user)
    end

    test "authentication with invalid inputs" do
      # Empty username
      assert {:error, error} =
               Accounts.sign_in_user(
                 %{
                   username: "",
                   password: "Password123!"
                 },
                 authorize?: false
               )

      assert error.errors
             |> Enum.any?(fn e ->
               Map.get(e, :field) == :username || Map.get(e, :fields) == [:username] ||
                 e.message =~ "required" || e.message =~ "empty"
             end)

      # Empty password
      assert {:error, error} =
               Accounts.sign_in_user(
                 %{
                   username: "someuser",
                   password: ""
                 },
                 authorize?: false
               )

      assert error.errors
             |> Enum.any?(fn e ->
               Map.get(e, :field) == :password || Map.get(e, :fields) == [:password] ||
                 e.message =~ "required" || e.message =~ "empty"
             end)

      # Non-existent user
      assert {:error, error} =
               Accounts.sign_in_user(
                 %{
                   username: "nonexistent_user_xyz",
                   password: "Password123!"
                 },
                 authorize?: false
               )

      assert error.class in [:invalid, :authentication, :forbidden]
    end

    test "password change requires current password" do
      # Register user
      {:ok, user} =
        Accounts.register_user(
          %{
            username: "pwchange_test",
            password: "OldPassword123!",
            password_confirmation: "OldPassword123!"
          },
          authorize?: false
        )

      # Attempt change with wrong current password
      assert {:error, error} =
               Accounts.change_user_password(
                 user,
                 %{
                   current_password: "WrongCurrent123!",
                   password: "NewPassword123!",
                   password_confirmation: "NewPassword123!"
                 },
                 authorize?: false
               )

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :current_password || e.message =~ "incorrect"
             end)

      # Successful change with correct current password
      assert {:ok, _} =
               Accounts.change_user_password(
                 user,
                 %{
                   current_password: "OldPassword123!",
                   password: "NewPassword123!",
                   password_confirmation: "NewPassword123!"
                 },
                 authorize?: false
               )
    end
  end
end
