defmodule RubberDuck.Actions.CreateEntityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Actions.CreateEntity

  describe "CreateEntity action" do
    test "creates user entity successfully" do
      params = %{
        entity_type: :user,
        entity_data: %{email: "test@example.com", name: "Test User"}
      }

      context = %{agent_id: "test_agent"}

      assert {:ok, created_entity} = CreateEntity.run(params, context)
      assert created_entity.type == :user
      assert created_entity.email == "test@example.com"
      assert Map.has_key?(created_entity, :id)
      assert Map.has_key?(created_entity, :created_at)
    end

    test "creates project entity successfully" do
      params = %{
        entity_type: :project,
        entity_data: %{name: "Test Project", path: "/test/project"}
      }

      context = %{agent_id: "test_agent"}

      assert {:ok, created_entity} = CreateEntity.run(params, context)
      assert created_entity.type == :project
      assert created_entity.name == "Test Project"
      assert created_entity.status == :active
    end

    test "validates entity type" do
      params = %{
        entity_type: :invalid_type,
        entity_data: %{name: "Test"}
      }

      context = %{agent_id: "test_agent"}

      assert {:error, {:invalid_entity_type, :invalid_type}} = CreateEntity.run(params, context)
    end

    test "validates entity data" do
      params = %{
        entity_type: :user,
        entity_data: %{}
      }

      context = %{agent_id: "test_agent"}

      assert {:error, :entity_data_cannot_be_empty} = CreateEntity.run(params, context)
    end

    test "validates entity type must be atom" do
      params = %{
        entity_type: "invalid",
        entity_data: %{name: "Test"}
      }

      context = %{agent_id: "test_agent"}

      assert {:error, :entity_type_must_be_atom} = CreateEntity.run(params, context)
    end
  end
end
