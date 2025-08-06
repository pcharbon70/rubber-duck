defmodule RubberDuck.Actions.Project.DetectDependenciesTest do
  use RubberDuck.DataCase
  alias RubberDuck.Actions.Project.DetectDependencies
  alias RubberDuck.Projects

  setup do
    {:ok, project} = Projects.create_project(%{
      name: "Dependency Test Project",
      language: "elixir",
      status: :active
    })

    %{project: project}
  end

  describe "run/2 - Elixir projects" do
    test "detects Mix dependencies", %{project: project} do
      # Create mix.exs file
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "mix.exs",
        content: """
        defmodule MyApp.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_app,
              deps: deps()
            ]
          end

          defp deps do
            [
              {:phoenix, "~> 1.7.0"},
              {:ecto_sql, "~> 3.10"},
              {:jason, "~> 1.4"},
              {:plug_cowboy, "~> 2.5", only: :dev}
            ]
          end
        end
        """,
        language: "elixir",
        size_bytes: 300
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      assert {:ok, result} = DetectDependencies.run(params, %{})

      assert length(result.dependencies) == 4
      assert Enum.any?(result.dependencies, & &1.name == "phoenix")
      assert Enum.any?(result.dependencies, & &1.name == "ecto_sql")
    end

    test "excludes dev dependencies when requested", %{project: project} do
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "mix.exs",
        content: """
        defmodule MyApp.MixProject do
          use Mix.Project

          defp deps do
            [
              {:phoenix, "~> 1.7.0"},
              {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
            ]
          end
        end
        """,
        language: "elixir",
        size_bytes: 200
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: false,
        check_versions: false
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      # Should only include phoenix, not credo
      assert length(result.dependencies) == 1
      assert hd(result.dependencies).name == "phoenix"
    end

    test "detects git dependencies", %{project: project} do
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "mix.exs",
        content: """
        defmodule MyApp.MixProject do
          use Mix.Project

          defp deps do
            [
              {:my_dep, git: "https://github.com/example/my_dep.git"},
              {:another_dep, git: "https://github.com/example/another.git", tag: "v1.0"}
            ]
          end
        end
        """,
        language: "elixir",
        size_bytes: 250
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: false
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      git_deps = Enum.filter(result.dependencies, & &1.type == :git)
      assert length(git_deps) == 2
      assert Enum.all?(git_deps, & &1.git_url != nil)
    end
  end

  describe "run/2 - JavaScript projects" do
    test "detects npm dependencies", %{project: project} do
      # Update project language
      Projects.update_project(project, %{language: "javascript"})

      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "package.json",
        content: """
        {
          "name": "my-app",
          "version": "1.0.0",
          "dependencies": {
            "react": "^18.2.0",
            "react-dom": "^18.2.0",
            "axios": "^1.4.0"
          },
          "devDependencies": {
            "webpack": "^5.88.0",
            "jest": "^29.5.0"
          }
        }
        """,
        language: "json",
        size_bytes: 300
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      assert length(result.dependencies) == 5

      prod_deps = Enum.filter(result.dependencies, & &1.scope == :runtime)
      assert length(prod_deps) == 3

      dev_deps = Enum.filter(result.dependencies, & &1.scope == :dev)
      assert length(dev_deps) == 2
    end
  end

  describe "run/2 - Python projects" do
    test "detects pip dependencies", %{project: project} do
      Projects.update_project(project, %{language: "python"})

      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "requirements.txt",
        content: """
        Django==4.2.0
        requests>=2.28.0
        numpy~=1.24.0
        pandas>1.5.0,<2.0.0
        # This is a comment
        pytest==7.3.0
        """,
        language: "text",
        size_bytes: 150
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      assert length(result.dependencies) == 5
      assert Enum.any?(result.dependencies, & &1.name == "Django")
      assert Enum.any?(result.dependencies, & &1.name == "pytest")
    end
  end

  describe "dependency analysis" do
    test "calculates dependency health score", %{project: project} do
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "mix.exs",
        content: """
        defmodule MyApp.MixProject do
          use Mix.Project

          defp deps do
            [
              {:phoenix, "~> 1.7.0"},
              {:old_dep, "~> 0.1.0"},
              {:another_old, "~> 0.2.0"}
            ]
          end
        end
        """,
        language: "elixir",
        size_bytes: 200
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      # Health score should be reduced due to old dependencies
      assert result.analysis.health_score < 100
      assert length(result.analysis.outdated) > 0
    end

    test "detects duplicate dependencies", %{project: project} do
      # Create multiple config files that might have duplicates
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "mix.exs",
        content: """
        defmodule MyApp.MixProject do
          defp deps do
            [{:phoenix, "~> 1.7.0"}]
          end
        end
        """,
        language: "elixir",
        size_bytes: 100
      })

      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "other_mix.exs",
        content: """
        defmodule Other.MixProject do
          defp deps do
            [{:phoenix, "~> 1.6.0"}]
          end
        end
        """,
        language: "elixir",
        size_bytes: 100
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      # Should detect phoenix appears with different versions
      assert length(result.analysis.duplicates) > 0
    end

    test "builds dependency graph", %{project: project} do
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "mix.exs",
        content: """
        defmodule MyApp.MixProject do
          defp deps do
            [
              {:phoenix, "~> 1.7.0"},
              {:ecto, "~> 3.10"},
              {:postgrex, "~> 0.17"}
            ]
          end
        end
        """,
        language: "elixir",
        size_bytes: 200
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: false
      }

      {:ok, result} = DetectDependencies.run(params, %{})

      assert map_size(result.dependency_graph) == 3
      assert Map.has_key?(result.dependency_graph, "phoenix")
      assert Map.has_key?(result.dependency_graph, "ecto")
    end
  end

  describe "error handling" do
    test "handles missing project gracefully" do
      params = %{
        project_id: Ecto.UUID.generate(),
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      assert {:error, _} = DetectDependencies.run(params, %{})
    end

    test "handles malformed dependency files", %{project: project} do
      {:ok, _} = Projects.create_code_file(%{
        project_id: project.id,
        path: "package.json",
        content: "{ invalid json }",
        language: "json",
        size_bytes: 20
      })

      params = %{
        project_id: project.id,
        scan_depth: :full,
        include_dev: true,
        check_versions: true
      }

      # Should still succeed but with no dependencies from the malformed file
      assert {:ok, result} = DetectDependencies.run(params, %{})
      assert result.dependencies == []
    end
  end
end
