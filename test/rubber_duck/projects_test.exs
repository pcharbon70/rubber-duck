defmodule RubberDuck.ProjectsTest do
  use RubberDuck.DataCase, async: true

  describe "Projects domain" do
    setup do
      # Create a test user to act as the project owner
      user_attrs = %{
        username: "testuser",
        password: "testpassword123",
        password_confirmation: "testpassword123"
      }

      {:ok, user} = RubberDuck.Accounts.register_user(user_attrs, authorize?: false)

      %{user: user}
    end

    test "can create a project with valid attributes", %{user: user} do
      project_attrs = %{
        name: "Test Project",
        description: "A test project for RubberDuck",
        language: "elixir"
      }

      assert {:ok, project} = RubberDuck.Projects.create_project(project_attrs, actor: user)
      assert project.name == "Test Project"
      assert project.description == "A test project for RubberDuck"
      assert project.language == "elixir"
      assert project.owner_id == user.id
    end

    test "can create a code file within a project", %{user: user} do
      project_attrs = %{
        name: "Test Project",
        description: "A test project",
        language: "elixir"
      }

      code_file_attrs = %{
        path: "lib/test.ex",
        content: "defmodule Test do\nend",
        language: "elixir",
        size_bytes: 20
      }

      assert {:ok, project} = RubberDuck.Projects.create_project(project_attrs, actor: user)

      code_file_attrs = Map.put(code_file_attrs, :project_id, project.id)
      assert {:ok, code_file} = RubberDuck.Projects.create_code_file(code_file_attrs, actor: user)

      assert code_file.path == "lib/test.ex"
      assert code_file.project_id == project.id
      assert code_file.size_bytes == 20
    end

    test "can list projects by owner", %{user: user} do
      project_attrs = %{
        name: "Test Project",
        description: "A test project",
        language: "elixir"
      }

      assert {:ok, _project} = RubberDuck.Projects.create_project(project_attrs, actor: user)

      projects = RubberDuck.Projects.list_projects_by_owner!(actor: user)
      assert length(projects) == 1
      assert hd(projects).name == "Test Project"
    end
  end
end