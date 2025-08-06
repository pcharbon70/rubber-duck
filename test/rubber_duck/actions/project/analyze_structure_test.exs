defmodule RubberDuck.Actions.Project.AnalyzeStructureTest do
  use RubberDuck.DataCase
  alias RubberDuck.Actions.Project.AnalyzeStructure
  alias RubberDuck.Projects

  setup do
    # Create test project with files
    {:ok, project} =
      Projects.create_project(%{
        name: "Structure Test Project",
        language: "elixir",
        status: :active
      })

    # Create a variety of files to test structure analysis
    files = [
      %{
        path: "lib/my_app.ex",
        content: "defmodule MyApp do\nend",
        size_bytes: 25
      },
      %{
        path: "lib/my_app/user.ex",
        content: "defmodule MyApp.User do\nend",
        size_bytes: 30
      },
      %{
        path: "lib/my_app/deeply/nested/module.ex",
        content: "defmodule MyApp.Deeply.Nested.Module do\nend",
        size_bytes: 45
      },
      %{
        path: "lib/my_app/controllers/user_controller.ex",
        content: "defmodule MyApp.UserController do\nend",
        size_bytes: 40
      },
      %{
        path: "test/my_app_test.exs",
        content: "defmodule MyAppTest do\nend",
        size_bytes: 28
      }
    ]

    created_files =
      Enum.map(files, fn file_attrs ->
        {:ok, file} =
          Projects.create_code_file(
            Map.merge(file_attrs, %{
              project_id: project.id,
              language: "elixir"
            })
          )

        file
      end)

    %{project: project, files: created_files}
  end

  describe "run/2" do
    test "analyzes project structure successfully", %{project: project} do
      params = %{
        project_id: project.id,
        include_files: ["**/*.ex", "**/*.exs"],
        exclude_patterns: ["deps/", "_build/"],
        depth_limit: 10
      }

      assert {:ok, result} = AnalyzeStructure.run(params, %{})

      assert Map.has_key?(result, :structure)
      assert Map.has_key?(result, :metrics)
      assert Map.has_key?(result, :optimizations)
      assert result.analyzed_at != nil
    end

    test "excludes files based on patterns", %{project: project} do
      params = %{
        project_id: project.id,
        include_files: ["lib/**/*.ex"],
        exclude_patterns: ["test/"],
        depth_limit: 10
      }

      {:ok, result} = AnalyzeStructure.run(params, %{})

      # Should not include test files
      file_paths =
        result.structure.tree
        |> Enum.flat_map(& &1.files)
        |> Enum.map(& &1.path)

      refute Enum.any?(file_paths, &String.starts_with?(&1, "test/"))
    end

    test "detects deep nesting", %{project: project} do
      params = %{
        project_id: project.id,
        include_files: ["**/*.ex"],
        exclude_patterns: [],
        depth_limit: 10
      }

      {:ok, result} = AnalyzeStructure.run(params, %{})

      deep_nesting = result.structure.patterns.deep_nesting
      assert "lib/my_app/deeply/nested" in deep_nesting
    end

    test "suggests optimizations for structure issues", %{project: project} do
      # Add many files to trigger large directory detection
      Enum.each(1..25, fn i ->
        Projects.create_code_file(%{
          project_id: project.id,
          path: "lib/crowded/file_#{i}.ex",
          content: "defmodule File#{i} do\nend",
          language: "elixir",
          size_bytes: 30
        })
      end)

      params = %{
        project_id: project.id,
        include_files: ["**/*.ex"],
        exclude_patterns: [],
        depth_limit: 10
      }

      {:ok, result} = AnalyzeStructure.run(params, %{})

      assert length(result.optimizations) > 0

      # Should suggest splitting the crowded directory
      split_suggestions =
        Enum.filter(result.optimizations, fn {type, _} ->
          type == :split_directory
        end)

      assert length(split_suggestions) > 0
    end

    test "calculates structure metrics", %{project: project} do
      params = %{
        project_id: project.id,
        include_files: ["**/*.ex", "**/*.exs"],
        exclude_patterns: [],
        depth_limit: 10
      }

      {:ok, result} = AnalyzeStructure.run(params, %{})

      metrics = result.metrics
      assert metrics.total_files == 5
      assert metrics.total_directories > 0
      assert metrics.average_depth > 0
      # deeply/nested/module
      assert metrics.max_depth >= 4
      assert metrics.complexity_score >= 0
    end

    test "detects module organization issues", %{project: project} do
      # Create a misplaced module
      Projects.create_code_file(%{
        project_id: project.id,
        path: "lib/wrong_place.ex",
        content: "defmodule MyApp.Auth.User do\nend",
        language: "elixir",
        size_bytes: 35
      })

      params = %{
        project_id: project.id,
        include_files: ["**/*.ex"],
        exclude_patterns: [],
        depth_limit: 10
      }

      {:ok, result} = AnalyzeStructure.run(params, %{})

      misplaced = result.structure.patterns.module_organization.misplaced_modules
      assert length(misplaced) > 0

      # Should detect the Auth.User module is in wrong place
      assert Enum.any?(misplaced, &(&1.module == "MyApp.Auth.User"))
    end

    test "handles empty project gracefully", %{} do
      {:ok, empty_project} =
        Projects.create_project(%{
          name: "Empty Project",
          language: "elixir",
          status: :active
        })

      params = %{
        project_id: empty_project.id,
        include_files: ["**/*.ex"],
        exclude_patterns: [],
        depth_limit: 10
      }

      assert {:ok, result} = AnalyzeStructure.run(params, %{})
      assert result.metrics.total_files == 0
      assert result.optimizations == []
    end
  end
end
