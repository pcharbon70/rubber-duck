defmodule RubberDuck.AccountsTest do
  use RubberDuck.DataCase, async: true

  describe "User registration" do
    test "can register a user with valid username and password" do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }

      # This should work with the existing authentication system
      assert {:ok, user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      assert to_string(user.username) == "testuser"
      assert user.hashed_password != nil
      # Should be hashed
      refute user.hashed_password == "validpassword123"
    end

    test "fails to register user with mismatched password confirmation" do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "wrongconfirmation"
      }

      assert {:error, error} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "fails to register user with short password" do
      user_attrs = %{
        username: "testuser",
        password: "short",
        password_confirmation: "short"
      }

      assert {:error, error} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "fails to register user with duplicate username" do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }

      # First registration should succeed
      assert {:ok, _user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)

      # Second registration with same username should fail
      assert {:error, error} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "generates JWT token on successful registration" do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }

      assert {:ok, _user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)

      # Registration action should have token metadata defined
      action = Ash.Resource.Info.action(RubberDuck.Accounts.User, :register_with_password)
      token_metadata = Enum.find(action.metadata, &(&1.name == :token))
      assert token_metadata != nil
    end
  end

  describe "User authentication" do
    setup do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }

      {:ok, user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      %{user: user}
    end

    test "can sign in with valid username and password", %{user: _user} do
      sign_in_attrs = %{
        username: "testuser",
        password: "validpassword123"
      }

      assert {:ok, signed_in_user} =
               RubberDuck.Accounts.sign_in_user(sign_in_attrs, authorize?: false)

      assert to_string(signed_in_user.username) == "testuser"
    end

    test "fails to sign in with wrong password", %{user: _user} do
      sign_in_attrs = %{
        username: "testuser",
        password: "wrongpassword"
      }

      assert {:error, error} = RubberDuck.Accounts.sign_in_user(sign_in_attrs, authorize?: false)
      assert %Ash.Error.Forbidden{} = error
    end

    test "fails to sign in with non-existent username" do
      sign_in_attrs = %{
        username: "nonexistent",
        password: "validpassword123"
      }

      assert {:error, error} = RubberDuck.Accounts.sign_in_user(sign_in_attrs, authorize?: false)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "Password management" do
    setup do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }

      {:ok, user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      %{user: user}
    end

    test "can change password with valid current password", %{user: user} do
      change_attrs = %{
        current_password: "validpassword123",
        password: "newvalidpassword456",
        password_confirmation: "newvalidpassword456"
      }

      assert {:ok, updated_user} =
               RubberDuck.Accounts.change_user_password(user, change_attrs, authorize?: false)

      assert updated_user.id == user.id
      refute updated_user.hashed_password == user.hashed_password
    end

    test "fails to change password with wrong current password", %{user: user} do
      change_attrs = %{
        current_password: "wrongcurrentpassword",
        password: "newvalidpassword456",
        password_confirmation: "newvalidpassword456"
      }

      assert {:error, error} =
               RubberDuck.Accounts.change_user_password(user, change_attrs, authorize?: false)

      assert %Ash.Error.Forbidden{} = error
    end

    test "fails to change password with mismatched confirmation", %{user: user} do
      change_attrs = %{
        current_password: "validpassword123",
        password: "newvalidpassword456",
        password_confirmation: "wrongconfirmation"
      }

      assert {:error, error} =
               RubberDuck.Accounts.change_user_password(user, change_attrs, authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "User lookup" do
    setup do
      user_attrs = %{
        username: "testuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }

      {:ok, user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      %{user: user}
    end

    test "can get user by id", %{user: user} do
      assert {:ok, found_user} = RubberDuck.Accounts.get_user(user.id, authorize?: false)
      assert found_user.id == user.id
      assert to_string(found_user.username) == to_string(user.username)
    end

    test "can get user by username", %{user: user} do
      assert {:ok, found_user} =
               RubberDuck.Accounts.get_user_by_username("testuser", authorize?: false)

      assert found_user.id == user.id
      assert to_string(found_user.username) == to_string(user.username)
    end

    test "returns error for non-existent user id" do
      non_existent_id = Ash.UUID.generate()

      assert {:error, %Ash.Error.Invalid{}} =
               RubberDuck.Accounts.get_user(non_existent_id, authorize?: false)
    end

    test "returns error for non-existent username" do
      assert {:error, %Ash.Error.Invalid{}} =
               RubberDuck.Accounts.get_user_by_username("nonexistent", authorize?: false)
    end
  end
end
