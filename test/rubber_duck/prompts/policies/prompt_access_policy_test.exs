defmodule RubberDuck.Prompts.Policies.PromptAccessPolicyTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Prompts.Policies.PromptAccessPolicy

  describe "system prompt access" do
    test "allows system admin access to system prompts" do
      actor = %{id: "admin-123", role: :system_admin, tenant_id: "tenant-1"}
      resource = %{prompt_type: :system, approval_status: "approved"}
      context = %{action: %{name: :read}}

      assert :authorized = PromptAccessPolicy.check(actor, resource, context, [])
    end

    test "denies regular users write access to system prompts" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}
      resource = %{prompt_type: :system, approval_status: "approved"}
      context = %{action: %{name: :update}}

      assert :forbidden = PromptAccessPolicy.check(actor, resource, context, [])
    end

    test "allows users to read approved standard system prompts" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}

      resource = %{
        prompt_type: :system,
        approval_status: "approved",
        security_level: "standard"
      }

      context = %{action: %{name: :read}}

      assert :authorized = PromptAccessPolicy.check(actor, resource, context, [])
    end

    test "denies users access to enhanced security system prompts" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}

      resource = %{
        prompt_type: :system,
        approval_status: "approved",
        security_level: "enhanced"
      }

      context = %{action: %{name: :read}}

      assert :forbidden = PromptAccessPolicy.check(actor, resource, context, [])
    end
  end

  describe "user prompt access" do
    test "allows users to access their own prompts" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}

      resource = %{
        prompt_type: :user,
        user_id: "user-123",
        approval_status: "approved"
      }

      context = %{action: %{name: :update}}

      assert :authorized = PromptAccessPolicy.check(actor, resource, context, [])
    end

    test "denies users access to other users' prompts" do
      actor = %{id: "user-123", role: :user, tenant_id: "tenant-1"}

      resource = %{
        prompt_type: :user,
        user_id: "user-456",
        approval_status: "approved"
      }

      context = %{action: %{name: :read}}

      assert :forbidden = PromptAccessPolicy.check(actor, resource, context, [])
    end

    test "allows admin users to access any user prompt" do
      actor = %{id: "admin-123", role: :admin, tenant_id: "tenant-1"}

      resource = %{
        prompt_type: :user,
        user_id: "user-123",
        approval_status: "approved"
      }

      context = %{action: %{name: :update}}

      assert :authorized = PromptAccessPolicy.check(actor, resource, context, [])
    end
  end

  describe "project prompt access" do
    test "allows project owners to access their project prompts" do
      actor = %{
        id: "user-123",
        role: :project_owner,
        tenant_id: "tenant-1",
        projects: ["project-456"]
      }

      resource = %{
        prompt_type: :project,
        project_id: "project-456",
        approval_status: "approved"
      }

      context = %{action: %{name: :update}}

      assert :authorized = PromptAccessPolicy.check(actor, resource, context, [])
    end

    test "denies users access to projects they don't belong to" do
      actor = %{
        id: "user-123",
        role: :user,
        tenant_id: "tenant-1",
        projects: ["project-789"]
      }

      resource = %{
        prompt_type: :project,
        project_id: "project-456",
        approval_status: "approved"
      }

      context = %{action: %{name: :read}}

      assert :forbidden = PromptAccessPolicy.check(actor, resource, context, [])
    end
  end
end
