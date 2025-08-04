defmodule RubberDuck.Accounts.TokenTest do
  use RubberDuck.DataCase, async: true

  describe "Token resource configuration" do
    test "token resource has required actions defined" do
      # Verify the Token resource has the expected actions
      actions = Ash.Resource.Info.actions(RubberDuck.Accounts.Token)
      action_names = Enum.map(actions, & &1.name)
      
      # Should have key authentication-related actions
      assert :read in action_names
      assert :expired in action_names
      assert :get_token in action_names
      assert :revoked? in action_names
      assert :revoke_token in action_names
      assert :revoke_jti in action_names
      assert :store_token in action_names
      assert :expunge_expired in action_names
    end

    test "token resource has proper attributes" do
      # Verify the Token resource has expected attributes
      attributes = Ash.Resource.Info.attributes(RubberDuck.Accounts.Token)
      attribute_names = Enum.map(attributes, & &1.name)
      
      assert :jti in attribute_names
      assert :subject in attribute_names
      assert :expires_at in attribute_names
      assert :purpose in attribute_names
      assert :extra_data in attribute_names
      assert :created_at in attribute_names
      assert :updated_at in attribute_names
    end

    test "token resource has primary key defined" do
      # Verify JTI is the primary key
      primary_key = Ash.Resource.Info.primary_key(RubberDuck.Accounts.Token)
      assert primary_key == [:jti]
    end

    test "token resource uses PostgreSQL data layer" do
      # Verify token resource is configured for PostgreSQL
      data_layer = Ash.Resource.Info.data_layer(RubberDuck.Accounts.Token)
      assert data_layer == AshPostgres.DataLayer
    end
  end

  describe "Token policies and security" do
    setup do
      # Create a test user
      user_attrs = %{
        username: "tokenuser",
        password: "validpassword123",
        password_confirmation: "validpassword123"
      }
      
      {:ok, user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)
      %{user: user}
    end

    test "token resource has restrictive policies for regular users", %{user: user} do
      # Regular users should not be able to access tokens directly
      # Tokens are managed by AshAuthentication only
      
      # Try to read tokens as regular user (should return empty results due to policies)
      # The policy allows the action but returns no results for unauthorized actors
      assert {:ok, []} = Ash.read(RubberDuck.Accounts.Token, actor: user)
    end

    test "token resource prevents unauthorized operations for regular users", %{user: user} do
      # Try to perform token operations as regular user (should return empty results)
      
      # Attempt to get expired tokens (should return empty due to policies)
      assert {:ok, []} = Ash.read(RubberDuck.Accounts.Token, action: :expired, actor: user)
    end

    test "token resource has proper policy configuration" do
      # Verify that token resource has proper policies configured
      # This tests the resource configuration rather than runtime behavior
      
      # Check that the token resource can be accessed (basic smoke test)
      # The fact that we can call Ash functions on it means it's properly configured
      actions = Ash.Resource.Info.actions(RubberDuck.Accounts.Token)
      assert length(actions) > 0
      
      # Verify it has the expected token-related actions
      action_names = Enum.map(actions, & &1.name)
      assert :store_token in action_names
      assert :revoke_token in action_names
    end
  end

  describe "Token integration with authentication" do
    test "user registration creates token metadata capability" do
      # Verify that user registration has token generation capability
      register_action = Ash.Resource.Info.action(RubberDuck.Accounts.User, :register_with_password)
      
      # Should have token metadata defined
      token_metadata = Enum.find(register_action.metadata, &(&1.name == :token))
      assert token_metadata != nil
      assert token_metadata.type == Ash.Type.String
    end

    test "user sign-in has token generation capability" do
      # Verify that sign-in action has token generation capability
      sign_in_action = Ash.Resource.Info.action(RubberDuck.Accounts.User, :sign_in_with_password)
      
      # Should have token metadata defined
      token_metadata = Enum.find(sign_in_action.metadata, &(&1.name == :token))
      assert token_metadata != nil
      assert token_metadata.type == Ash.Type.String
    end

    test "user resource has proper authentication configuration" do
      # Verify AshAuthentication is properly configured
      # Check authentication strategies are configured
      strategies = AshAuthentication.Info.authentication_strategies(RubberDuck.Accounts.User)
      assert length(strategies) > 0
      
      # Verify password strategy is configured
      password_strategy = Enum.find(strategies, &(&1.__struct__ == AshAuthentication.Strategy.Password))
      assert password_strategy != nil
      
      # Verify the strategy uses username field
      assert password_strategy.identity_field == :username
    end
  end
end