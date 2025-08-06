defmodule RubberDuck.Actions.Project.UpdateDependencies do
  @moduledoc """
  Action to update project dependencies based on recommendations.
  """

  use Jido.Action,
    name: "update_dependencies",
    description: "Updates project dependencies to newer versions",
    schema: [
      project_id: [type: :string, required: true],
      dependencies: [type: {:list, :map}, required: true],
      update_strategy: [type: :atom, default: :conservative, values: [:conservative, :moderate, :aggressive]],
      test_updates: [type: :boolean, default: true],
      create_pr: [type: :boolean, default: false]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         {:ok, update_result} <- execute_update_process(project, params) do
      {:ok, build_result(update_result)}
    end
  end

  defp execute_update_process(project, params) do
    with {:ok, config_files} <- load_config_files(project),
         update_plan <- create_update_plan(params.dependencies, params.update_strategy),
         {:ok, updated_files} <- apply_updates(config_files, update_plan),
         {:ok, test_results} <- run_tests_if_enabled(project, params),
         {:ok, pr_info} <- create_pr_if_enabled(project, updated_files, update_plan, params) do
      {:ok, %{
        update_plan: update_plan,
        test_results: test_results,
        pull_request: pr_info
      }}
    end
  end

  defp build_result(update_result) do
    %{
      updated_dependencies: length(update_result.update_plan),
      update_plan: update_result.update_plan,
      test_results: update_result.test_results,
      pull_request: update_result.pull_request,
      updated_at: DateTime.utc_now()
    }
  end

  defp load_config_files(project) do
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        config_files = files
          |> Enum.filter(&is_dependency_file?/1)
          |> Enum.map(fn file ->
            %{
              path: file.path,
              content: file.content,
              type: detect_dependency_file_type(file.path),
              file_id: file.id
            }
          end)
        {:ok, config_files}
      error -> error
    end
  end

  defp is_dependency_file?(file) do
    dependency_files = [
      "mix.exs", "mix.lock",
      "package.json", "package-lock.json", "yarn.lock",
      "requirements.txt", "Pipfile", "Pipfile.lock",
      "Gemfile", "Gemfile.lock",
      "go.mod", "go.sum"
    ]

    Enum.any?(dependency_files, &String.ends_with?(file.path, &1))
  end

  defp detect_dependency_file_type(path) do
    file_type_mappings = [
      {"mix.exs", :mix_config},
      {"mix.lock", :mix_lock},
      {"package.json", :npm_package},
      {"package-lock.json", :npm_lock},
      {"yarn.lock", :yarn_lock},
      {"requirements.txt", :pip_requirements},
      {"Pipfile", :pipfile},
      {"Gemfile", :gemfile},
      {"go.mod", :go_mod}
    ]

    Enum.find_value(file_type_mappings, :unknown, fn {suffix, type} ->
      if String.ends_with?(path, suffix), do: type
    end)
  end

  defp create_update_plan(dependencies, strategy) do
    dependencies
    |> Enum.map(fn dep ->
      determine_update_version(dep, strategy)
    end)
    |> Enum.filter(& &1.should_update)
  end

  defp determine_update_version(dep, strategy) do
    current = dep.current_version
    latest = dep.latest_version
    available = dep.available_versions || []

    target_version = case strategy do
      :conservative -> find_patch_update(current, available)
      :moderate -> find_minor_update(current, available)
      :aggressive -> latest
    end

    %{
      name: dep.name,
      current_version: current,
      target_version: target_version || current,
      latest_version: latest,
      update_type: categorize_update(current, target_version || current),
      should_update: target_version != nil && target_version != current,
      breaking_changes: check_breaking_changes(dep, current, target_version),
      security_fixes: dep.security_fixes || false
    }
  end

  defp find_patch_update(current, available) do
    case Version.parse(current) do
      {:ok, current_version} ->
        find_matching_version(available, current_version, :patch)
      _ ->
        nil
    end
  end

  defp find_matching_version(available, current_version, :patch) do
    available
    |> Enum.filter(&is_valid_patch_update?(&1, current_version))
    |> Enum.sort(&version_sort/2)
    |> List.last()
  end

  defp is_valid_patch_update?(version_string, current_version) do
    case Version.parse(version_string) do
      {:ok, version} ->
        Version.match?(version, "~> #{current_version.major}.#{current_version.minor}.0") &&
        Version.compare(version, current_version) == :gt
      _ ->
        false
    end
  end

  defp find_minor_update(current, available) do
    case Version.parse(current) do
      {:ok, current_version} ->
        find_matching_minor_version(available, current_version)
      _ ->
        nil
    end
  end

  defp find_matching_minor_version(available, current_version) do
    available
    |> Enum.filter(&is_valid_minor_update?(&1, current_version))
    |> Enum.sort(&version_sort/2)
    |> List.last()
  end

  defp is_valid_minor_update?(version_string, current_version) do
    case Version.parse(version_string) do
      {:ok, version} ->
        version.major == current_version.major &&
        Version.compare(version, current_version) == :gt
      _ ->
        false
    end
  end

  defp version_sort(a, b) do
    case {Version.parse(a), Version.parse(b)} do
      {{:ok, va}, {:ok, vb}} -> Version.compare(va, vb) == :lt
      _ -> a < b
    end
  end

  defp categorize_update(current, target) do
    case {Version.parse(current), Version.parse(target)} do
      {{:ok, cv}, {:ok, tv}} ->
        cond do
          cv.major != tv.major -> :major
          cv.minor != tv.minor -> :minor
          cv.patch != tv.patch -> :patch
          true -> :none
        end
      _ -> :unknown
    end
  end

  defp check_breaking_changes(_dep, current, target) do
    # In a real implementation, this would check changelog or version notes
    case categorize_update(current, target) do
      :major -> %{likely: true, confidence: 0.9}
      :minor -> %{likely: false, confidence: 0.7}
      :patch -> %{likely: false, confidence: 0.95}
      _ -> %{likely: false, confidence: 1.0}
    end
  end

  defp apply_updates(config_files, update_plan) do
    results = Enum.map(config_files, fn file ->
      updates_for_file = find_updates_for_file(file, update_plan)

      if length(updates_for_file) > 0 do
        updated_content = apply_updates_to_file(file, updates_for_file)

        %{
          file: file,
          original_content: file.content,
          updated_content: updated_content,
          updates_applied: updates_for_file,
          changed: true
        }
      else
        %{
          file: file,
          changed: false
        }
      end
    end)

    {:ok, Enum.filter(results, & &1.changed)}
  end

  defp find_updates_for_file(file, update_plan) do
    case file.type do
      :mix_config -> find_mix_updates(file.content, update_plan)
      :npm_package -> find_npm_updates(file.content, update_plan)
      :pip_requirements -> find_pip_updates(file.content, update_plan)
      _ -> []
    end
  end

  defp find_mix_updates(content, update_plan) do
    # Parse dependencies from mix.exs
    deps = extract_mix_dependencies(content)

    Enum.filter(update_plan, fn update ->
      Enum.any?(deps, & &1.name == update.name)
    end)
  end

  defp extract_mix_dependencies(content) do
    # Simple regex-based extraction
    content
    |> then(&Regex.scan(~r/{:([\w_]+),\s*"([^"]+)"/, &1))
    |> Enum.map(fn [_, name, version] ->
      %{name: name, version: version}
    end)
  end

  defp find_npm_updates(content, update_plan) do
    case Jason.decode(content) do
      {:ok, package} ->
        deps = Map.get(package, "dependencies", %{})
        dev_deps = Map.get(package, "devDependencies", %{})
        all_deps = Map.merge(deps, dev_deps)

        Enum.filter(update_plan, fn update ->
          Map.has_key?(all_deps, update.name)
        end)
      _ -> []
    end
  end

  defp find_pip_updates(content, update_plan) do
    lines = String.split(content, "\n")

    deps = lines
      |> Enum.map(&parse_pip_requirement/1)
      |> Enum.filter(& &1)

    Enum.filter(update_plan, fn update ->
      Enum.any?(deps, & &1.name == update.name)
    end)
  end

  defp parse_pip_requirement(line) do
    case Regex.run(~r/^([a-zA-Z0-9\-_]+)==(.+)$/, String.trim(line)) do
      [_, name, version] -> %{name: name, version: version}
      _ -> nil
    end
  end

  defp apply_updates_to_file(file, updates) do
    case file.type do
      :mix_config -> update_mix_file(file.content, updates)
      :npm_package -> update_npm_file(file.content, updates)
      :pip_requirements -> update_pip_file(file.content, updates)
      _ -> file.content
    end
  end

  defp update_mix_file(content, updates) do
    Enum.reduce(updates, content, fn update, acc ->
      # Update version in mix.exs
      pattern = ~r/({:#{update.name},\s*)"[^"]+"/
      replacement = "\\1\"#{update.target_version}\""
      Regex.replace(pattern, acc, replacement)
    end)
  end

  defp update_npm_file(content, updates) do
    case Jason.decode(content) do
      {:ok, package} ->
        updated_package = apply_npm_updates(package, updates)
        Jason.encode!(updated_package, pretty: true)
      _ ->
        content
    end
  end

  defp apply_npm_updates(package, updates) do
    Enum.reduce(updates, package, &apply_single_npm_update/2)
  end

  defp apply_single_npm_update(update, package) do
    package
    |> update_if_exists(["dependencies", update.name], update.target_version)
    |> update_if_exists(["devDependencies", update.name], update.target_version)
  end

  defp update_if_exists(package, path, value) do
    if get_in(package, path) do
      put_in(package, path, value)
    else
      package
    end
  end

  defp update_pip_file(content, updates) do
    content
    |> String.split("\n")
    |> Enum.map(&update_pip_line(&1, updates))
    |> Enum.join("\n")
  end

  defp update_pip_line(line, updates) do
    find_pip_update(line, updates) || line
  end

  defp find_pip_update(line, updates) do
    trimmed = String.trim(line)

    Enum.find_value(updates, fn update ->
      if String.starts_with?(trimmed, "#{update.name}==") do
        "#{update.name}==#{update.target_version}"
      end
    end)
  end

  defp run_tests_if_enabled(project, params) do
    if params.test_updates do
      run_project_tests(project)
    else
      {:ok, %{skipped: true}}
    end
  end

  defp run_project_tests(project) do
    # Determine test command based on project language
    test_command = case project.language do
      "elixir" -> "mix test"
      "javascript" -> "npm test"
      "python" -> "python -m pytest"
      _ -> nil
    end

    if test_command do
      case System.cmd(test_command, [], cd: project_directory(project)) do
        {output, 0} ->
          {:ok, %{
            success: true,
            command: test_command,
            output: output
          }}
        {output, exit_code} ->
          {:ok, %{
            success: false,
            command: test_command,
            exit_code: exit_code,
            output: output
          }}
      end
    else
      {:ok, %{skipped: true, reason: "Unknown project language"}}
    end
  end

  defp project_directory(_project) do
    # In a real implementation, this would return the project's directory
    "."
  end

  defp create_pr_if_enabled(project, updated_files, update_plan, params) do
    if params.create_pr do
      create_pull_request(project, updated_files, update_plan)
    else
      {:ok, nil}
    end
  end

  defp create_pull_request(_project, updated_files, update_plan) do
    # Save updated files
    Enum.each(updated_files, fn result ->
      file = result.file
      # Use the standard update_code_file function with the file record
      Projects.update_code_file(file, %{
        content: result.updated_content
      })
    end)

    # Create PR description
    pr_title = "Update #{length(update_plan)} dependencies"
    pr_body = generate_pr_description(update_plan)

    {:ok, %{
      title: pr_title,
      body: pr_body,
      branch: "dependency-updates-#{Date.utc_today()}",
      files_changed: length(updated_files)
    }}
  end

  defp generate_pr_description(update_plan) do
    """
    ## Dependency Updates

    This PR updates the following dependencies:

    #{Enum.map_join(update_plan, "\n", &format_update_line/1)}

    ### Update Summary

    - **Total updates**: #{length(update_plan)}
    - **Security fixes**: #{count_security_fixes(update_plan)}
    - **Major updates**: #{count_by_type(update_plan, :major)}
    - **Minor updates**: #{count_by_type(update_plan, :minor)}
    - **Patch updates**: #{count_by_type(update_plan, :patch)}

    ### Breaking Changes

    #{format_breaking_changes(update_plan)}

    Please review the changes and ensure all tests pass before merging.
    """
  end

  defp format_update_line(update) do
    security_badge = if update.security_fixes, do: " 🔒", else: ""
    breaking_badge = if update.breaking_changes.likely, do: " ⚠️", else: ""

    "- **#{update.name}**: #{update.current_version} → #{update.target_version}#{security_badge}#{breaking_badge}"
  end

  defp count_security_fixes(update_plan) do
    Enum.count(update_plan, & &1.security_fixes)
  end

  defp count_by_type(update_plan, type) do
    Enum.count(update_plan, & &1.update_type == type)
  end

  defp format_breaking_changes(update_plan) do
    breaking = Enum.filter(update_plan, & &1.breaking_changes.likely)

    if length(breaking) > 0 do
      """
      The following updates may contain breaking changes:

      #{Enum.map_join(breaking, "\n", fn update ->
        "- **#{update.name}** (#{update.update_type} update)"
      end)}

      Please review the changelogs for these packages.
      """
    else
      "No breaking changes expected based on semantic versioning."
    end
  end
end
