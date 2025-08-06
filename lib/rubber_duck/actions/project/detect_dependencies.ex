defmodule RubberDuck.Actions.Project.DetectDependencies do
  @moduledoc """
  Action to detect and analyze project dependencies.
  """

  use Jido.Action,
    name: "detect_dependencies",
    description: "Detects project dependencies and analyzes their relationships",
    schema: [
      project_id: [type: :string, required: true],
      scan_depth: [type: :atom, default: :full, values: [:shallow, :full]],
      include_dev: [type: :boolean, default: true],
      check_versions: [type: :boolean, default: true]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         {:ok, files} <- get_project_config_files(project),
         dependencies <- extract_dependencies(files, params),
         graph <- build_dependency_graph(dependencies),
         analysis <- analyze_dependencies(dependencies, graph, params) do

      {:ok, %{
        dependencies: dependencies,
        dependency_graph: graph,
        analysis: analysis,
        detected_at: DateTime.utc_now()
      }}
    end
  end

  defp get_project_config_files(project) do
    # Get mix.exs, package.json, requirements.txt etc based on language
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        config_files = files
          |> Enum.filter(&is_config_file?/1)
          |> Enum.map(&load_file_content/1)
        {:ok, config_files}
      error -> error
    end
  end

  defp is_config_file?(file) do
    config_patterns = [
      "mix.exs", "mix.lock",
      "package.json", "package-lock.json", "yarn.lock",
      "requirements.txt", "Pipfile", "Pipfile.lock",
      "Gemfile", "Gemfile.lock",
      "go.mod", "go.sum"
    ]

    Enum.any?(config_patterns, &String.ends_with?(file.path, &1))
  end

  defp load_file_content(file) do
    %{
      path: file.path,
      content: file.content,
      type: detect_file_type(file.path)
    }
  end

  defp detect_file_type(path) do
    cond do
      String.ends_with?(path, "mix.exs") -> :mix_config
      String.ends_with?(path, "mix.lock") -> :mix_lock
      String.ends_with?(path, "package.json") -> :npm_package
      String.ends_with?(path, "requirements.txt") -> :pip_requirements
      String.ends_with?(path, "Gemfile") -> :bundler_gemfile
      String.ends_with?(path, "go.mod") -> :go_mod
      true -> :unknown
    end
  end

  defp extract_dependencies(files, params) do
    files
    |> Enum.flat_map(&extract_from_file(&1, params))
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp extract_from_file(%{type: :mix_config, content: content}, params) do
    extract_mix_dependencies(content, params.include_dev)
  end

  defp extract_from_file(%{type: :npm_package, content: content}, params) do
    extract_npm_dependencies(content, params.include_dev)
  end

  defp extract_from_file(%{type: :pip_requirements, content: content}, _params) do
    extract_pip_dependencies(content)
  end

  defp extract_from_file(_, _params), do: []

  defp extract_mix_dependencies(content, include_dev) do
    # Parse mix.exs content to extract dependencies
    deps = []

    # Extract regular deps
    matches = Regex.scan(~r/{:(\w+),\s*"([^"]+)"/, content)
    deps = deps ++ Enum.map(matches, fn [_, name, version] ->
      %{
        name: name,
        version: version,
        type: :hex,
        scope: :runtime,
        source: :mix
      }
    end)

    # Extract git deps
    git_matches = Regex.scan(~r/{:(\w+),\s*git:\s*"([^"]+)"/, content)
    deps = deps ++ Enum.map(git_matches, fn [_, name, git_url] ->
      %{
        name: name,
        version: "git",
        type: :git,
        scope: :runtime,
        source: :mix,
        git_url: git_url
      }
    end)

    if include_dev do
      deps
    else
      Enum.filter(deps, & &1.scope != :dev)
    end
  end

  defp extract_npm_dependencies(content, include_dev) do
    case Jason.decode(content) do
      {:ok, package} ->
        deps = extract_npm_deps_from_section(package["dependencies"] || %{}, :runtime)

        if include_dev do
          dev_deps = extract_npm_deps_from_section(package["devDependencies"] || %{}, :dev)
          deps ++ dev_deps
        else
          deps
        end
      _ -> []
    end
  end

  defp extract_npm_deps_from_section(deps_map, scope) do
    Enum.map(deps_map, fn {name, version} ->
      %{
        name: name,
        version: version,
        type: :npm,
        scope: scope,
        source: :npm
      }
    end)
  end

  defp extract_pip_dependencies(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" || String.starts_with?(&1, "#")))
    |> Enum.map(&parse_pip_requirement/1)
    |> Enum.filter(& &1)
  end

  defp parse_pip_requirement(line) do
    case Regex.run(~r/^([a-zA-Z0-9\-_]+)(==|>=|<=|>|<|~=)(.+)$/, line) do
      [_, name, _op, version] ->
        %{
          name: name,
          version: version,
          type: :pip,
          scope: :runtime,
          source: :pip
        }
      _ -> nil
    end
  end

  defp build_dependency_graph(dependencies) do
    # Build a graph of dependencies
    # For now, return a simple adjacency list
    dependencies
    |> Enum.map(fn dep ->
      {dep.name, %{
        info: dep,
        depends_on: [],  # Would need to analyze each dep's dependencies
        depended_by: []
      }}
    end)
    |> Map.new()
  end

  defp analyze_dependencies(dependencies, graph, params) do
    analysis = %{
      total_count: length(dependencies),
      by_type: group_by_type(dependencies),
      by_scope: group_by_scope(dependencies),
      security_issues: if params.check_versions do
        check_security_issues(dependencies)
      else
        []
      end,
      outdated: if params.check_versions do
        check_outdated_versions(dependencies)
      else
        []
      end,
      duplicates: find_duplicate_dependencies(dependencies),
      unused: find_unused_dependencies(dependencies, graph),
      circular: detect_circular_dependencies(graph)
    }

    # Calculate health score
    Map.put(analysis, :health_score, calculate_dependency_health(analysis))
  end

  defp group_by_type(dependencies) do
    dependencies
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, deps} -> {type, length(deps)} end)
    |> Map.new()
  end

  defp group_by_scope(dependencies) do
    dependencies
    |> Enum.group_by(& &1.scope)
    |> Enum.map(fn {scope, deps} -> {scope, length(deps)} end)
    |> Map.new()
  end

  defp check_security_issues(_dependencies) do
    # In real implementation, would check against vulnerability databases
    # For now, return empty list
    []
  end

  defp check_outdated_versions(dependencies) do
    # In real implementation, would check against package registries
    # For now, simulate some outdated deps
    dependencies
    |> Enum.filter(fn dep ->
      # Simulate: deps with version < 1.0 are outdated
      case Version.parse(dep.version) do
        {:ok, version} -> Version.compare(version, "1.0.0") == :lt
        _ -> false
      end
    end)
    |> Enum.map(fn dep ->
      %{
        name: dep.name,
        current_version: dep.version,
        latest_version: "1.0.0", # Simulated
        severity: :minor
      }
    end)
  end

  defp find_duplicate_dependencies(dependencies) do
    dependencies
    |> Enum.group_by(& &1.name)
    |> Enum.filter(fn {_, deps} -> length(deps) > 1 end)
    |> Enum.map(fn {name, deps} ->
      %{
        name: name,
        versions: Enum.map(deps, & &1.version),
        sources: Enum.map(deps, & &1.source)
      }
    end)
  end

  defp find_unused_dependencies(_dependencies, _graph) do
    # Would need to analyze code usage to find truly unused deps
    # For now, return empty
    []
  end

  defp detect_circular_dependencies(graph) do
    # Simple DFS to detect cycles
    graph
    |> Map.keys()
    |> Enum.flat_map(fn node ->
      case dfs_detect_cycle(graph, node, [], MapSet.new()) do
        {:cycle, path} -> [path]
        :no_cycle -> []
      end
    end)
    |> Enum.uniq()
  end

  defp dfs_detect_cycle(graph, node, path, visited) do
    cond do
      node in path ->
        {:cycle, Enum.reverse([node | Enum.reverse(path)])}

      MapSet.member?(visited, node) ->
        :no_cycle

      true ->
        new_path = Enum.reverse([node | Enum.reverse(path)])
        new_visited = MapSet.put(visited, node)
        check_node_dependencies(graph, node, new_path, new_visited)
    end
  end

  defp check_node_dependencies(graph, node, path, visited) do
    case Map.get(graph, node) do
      nil ->
        :no_cycle

      %{depends_on: deps} ->
        Enum.find_value(deps, :no_cycle, fn dep ->
          dfs_detect_cycle(graph, dep, path, visited)
        end)
    end
  end

  defp calculate_dependency_health(analysis) do
    score = 100

    # Deduct points for issues
    score = score - length(analysis.security_issues) * 10
    score = score - length(analysis.outdated) * 2
    score = score - length(analysis.duplicates) * 5
    score = score - length(analysis.unused) * 3
    score = score - length(analysis.circular) * 15

    # Deduct for too many dependencies
    score = if analysis.total_count > 100 do
      score - 10
    else
      score
    end

    max(0, score)
  end
end
