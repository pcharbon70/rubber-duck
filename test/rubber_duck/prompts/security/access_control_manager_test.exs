defmodule RubberDuck.Prompts.Security.AccessControlManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Prompts.Security.AccessControlManager

  describe "access control validation" do
    test "authorizes admin users for all operations" do
      actor = %{id: "admin-123", role: :admin, tenant_id: "tenant-1"}
      resource = %{id: "prompt-123", prompt_type: :user, user_id: "user-123"}
      context = %{action: %{name: :read}}

      assert {:ok, :authorized} = AccessControlManager.check_access(actor, resource, context)
    end

    test "denies unauthorized access" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}
      resource = %{id: "prompt-456", prompt_type: :system, user_id: "admin-123"}
      context = %{action: %{name: :update}}

      assert {:ok, :forbidden} = AccessControlManager.check_access(actor, resource, context)
    end

    test "allows users to access their own prompts" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}
      resource = %{id: "prompt-123", prompt_type: :user, user_id: "user-123"}
      context = %{action: %{name: :read}}

      assert {:ok, :authorized} = AccessControlManager.check_access(actor, resource, context)
    end
  end

  describe "sharing access validation" do
    test "allows sharing for resource owners" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}

      resource = %{
        id: "prompt-123",
        prompt_type: :user,
        user_id: "user-123",
        access_policy: %{"collaboration_level" => "private"}
      }

      context = %{action: %{name: :share_prompt}}

      assert {:ok, :authorized} =
               AccessControlManager.check_sharing_access(actor, resource, context)
    end

    test "denies sharing for non-owners without permissions" do
      actor = %{id: "user-456", role: :user, tenant_id: "tenant-1"}

      resource = %{
        id: "prompt-123",
        prompt_type: :user,
        user_id: "user-123",
        access_policy: %{"collaboration_level" => "private"}
      }

      context = %{action: %{name: :share_prompt}}

      assert {:ok, :forbidden} =
               AccessControlManager.check_sharing_access(actor, resource, context)
    end
  end

  describe "approval access validation" do
    test "allows approval for admin users" do
      actor = %{id: "admin-123", role: :admin, tenant_id: "tenant-1"}

      resource = %{
        id: "prompt-123",
        prompt_type: :user,
        approval_status: "pending",
        user_id: "user-123"
      }

      context = %{action: %{name: :approve_prompt}}

      assert {:ok, :authorized} =
               AccessControlManager.check_approval_access(actor, resource, context)
    end

    test "denies approval for regular users" do
      actor = %{id: "user-456", role: :user, tenant_id: "tenant-1"}

      resource = %{
        id: "prompt-123",
        prompt_type: :user,
        approval_status: "pending",
        user_id: "user-123"
      }

      context = %{action: %{name: :approve_prompt}}

      assert {:ok, :forbidden} =
               AccessControlManager.check_approval_access(actor, resource, context)
    end
  end
end
