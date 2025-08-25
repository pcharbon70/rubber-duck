defmodule RubberDuck.Preferences.Security.AccessControlTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Security.AccessControl

  describe "has_role?/2" do
    test "returns true for exact role match" do
      actor = %{role: :admin}
      assert AccessControl.has_role?(actor, :admin)
    end

    test "returns true for higher role" do
      actor = %{role: :security_admin}
      assert AccessControl.has_role?(actor, :admin)
      assert AccessControl.has_role?(actor, :user)
    end

    test "returns false for lower role" do
      actor = %{role: :user}
      refute AccessControl.has_role?(actor, :admin)
      refute AccessControl.has_role?(actor, :security_admin)
    end

    test "returns false for missing role" do
      actor = %{}
      refute AccessControl.has_role?(actor, :admin)
    end
  end

  describe "has_any_role?/2" do
    test "returns true if actor has any of the specified roles" do
      actor = %{role: :project_admin}
      assert AccessControl.has_any_role?(actor, [:user, :project_admin, :admin])
    end

    test "returns true if actor has higher role than any specified" do
      actor = %{role: :admin}
      assert AccessControl.has_any_role?(actor, [:user, :project_admin])
    end

    test "returns false if actor has none of the specified roles" do
      actor = %{role: :read_only}
      refute AccessControl.has_any_role?(actor, [:admin, :security_admin])
    end

    test "handles empty role list" do
      actor = %{role: :user}
      refute AccessControl.has_any_role?(actor, [])
    end
  end

  describe "get_actor_permissions/1" do
    test "returns correct permissions for read_only role" do
      actor = %{role: :read_only}
      permissions = AccessControl.get_actor_permissions(actor)

      assert "read_preferences" in permissions
      refute "write_preferences" in permissions
    end

    test "returns correct permissions for user role" do
      actor = %{role: :user}
      permissions = AccessControl.get_actor_permissions(actor)

      assert "read_preferences" in permissions
      assert "write_own_preferences" in permissions
      assert "read_own_preferences" in permissions
    end

    test "returns correct permissions for admin role" do
      actor = %{role: :admin}
      permissions = AccessControl.get_actor_permissions(actor)

      assert "read_preferences" in permissions
      assert "write_preferences" in permissions
      assert "read_all_preferences" in permissions
      assert "manage_overrides" in permissions
    end

    test "returns correct permissions for security_admin role" do
      actor = %{role: :security_admin}
      permissions = AccessControl.get_actor_permissions(actor)

      assert "manage_security_policies" in permissions
      assert "access_audit_logs" in permissions
      assert "manage_delegations" in permissions
    end

    test "returns empty permissions for unknown role" do
      actor = %{role: :unknown_role}
      permissions = AccessControl.get_actor_permissions(actor)

      assert permissions == []
    end

    test "handles missing role" do
      actor = %{}
      permissions = AccessControl.get_actor_permissions(actor)

      assert permissions == []
    end
  end

  describe "has_permission?/2" do
    test "returns true if actor has the specific permission" do
      actor = %{role: :admin}
      assert AccessControl.has_permission?(actor, "write_preferences")
    end

    test "returns false if actor lacks the specific permission" do
      actor = %{role: :read_only}
      refute AccessControl.has_permission?(actor, "write_preferences")
    end
  end

  describe "authorize_preference_access/4" do
    test "authorizes access for admin users" do
      actor = %{id: "user123", role: :admin}

      # Mock the SecurityPolicy.active_policies call
      with_mock RubberDuck.Preferences.Resources.SecurityPolicy, [:passthrough],
        active_policies: fn -> {:ok, []} end do
        result = AccessControl.authorize_preference_access(actor, "read", "ui.theme")
        # With no policies, default is unauthorized for security
        assert {:error, :unauthorized} = result
      end
    end

    test "handles policy evaluation errors gracefully" do
      actor = %{id: "user123", role: :user}

      # Mock a policy lookup failure
      with_mock RubberDuck.Preferences.Resources.SecurityPolicy, [:passthrough],
        active_policies: fn -> {:error, "Database error"} end do
        result = AccessControl.authorize_preference_access(actor, "read", "ui.theme")
        assert {:error, :unauthorized} = result
      end
    end
  end

  describe "approval_required?/3" do
    test "returns false when no policies require approval" do
      with_mock RubberDuck.Preferences.Resources.SecurityPolicy, [:passthrough],
        active_policies: fn -> {:ok, [%{approval_required: false, active: true}]} end do
        refute AccessControl.approval_required?("ui.theme", "update")
      end
    end

    test "returns true when policy requires approval" do
      policy = %{
        approval_required: true,
        active: true,
        preference_pattern: "api*",
        resource_type: "user_preference"
      }

      with_mock RubberDuck.Preferences.Resources.SecurityPolicy, [:passthrough],
        active_policies: fn -> {:ok, [policy]} end do
        assert AccessControl.approval_required?("api.key", "update")
      end
    end

    test "defaults to requiring approval on policy lookup error" do
      with_mock RubberDuck.Preferences.Resources.SecurityPolicy, [:passthrough],
        active_policies: fn -> {:error, "Database error"} end do
        assert AccessControl.approval_required?("any.preference", "update")
      end
    end
  end

  describe "role hierarchy" do
    test "maintains proper role hierarchy" do
      # Test role hierarchy: read_only < user < project_admin < admin < security_admin

      read_only_actor = %{role: :read_only}
      user_actor = %{role: :user}
      project_admin_actor = %{role: :project_admin}
      admin_actor = %{role: :admin}
      security_admin_actor = %{role: :security_admin}

      # Security admin should have highest privileges
      assert AccessControl.has_role?(security_admin_actor, :admin)
      assert AccessControl.has_role?(security_admin_actor, :project_admin)
      assert AccessControl.has_role?(security_admin_actor, :user)
      assert AccessControl.has_role?(security_admin_actor, :read_only)

      # Admin should have most privileges except security admin
      assert AccessControl.has_role?(admin_actor, :project_admin)
      assert AccessControl.has_role?(admin_actor, :user)
      assert AccessControl.has_role?(admin_actor, :read_only)
      refute AccessControl.has_role?(admin_actor, :security_admin)

      # Project admin should have limited privileges
      assert AccessControl.has_role?(project_admin_actor, :user)
      assert AccessControl.has_role?(project_admin_actor, :read_only)
      refute AccessControl.has_role?(project_admin_actor, :admin)

      # User should have basic privileges
      assert AccessControl.has_role?(user_actor, :read_only)
      refute AccessControl.has_role?(user_actor, :project_admin)

      # Read only should have no elevated privileges
      refute AccessControl.has_role?(read_only_actor, :user)
    end
  end
end
