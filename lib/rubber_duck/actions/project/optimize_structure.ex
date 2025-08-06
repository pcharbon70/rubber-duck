defmodule RubberDuck.Actions.Project.OptimizeStructure do
  @moduledoc """
  Action to apply structure optimizations to a project.
  """

  use Jido.Action,
    name: "optimize_structure",
    description: "Applies recommended structure optimizations to a project",
    schema: [
      project_id: [type: :string, required: true],
      optimizations: [type: {:list, :map}, required: true],
      dry_run: [type: :boolean, default: false],
      backup: [type: :boolean, default: true],
      apply_filter: [type: {:list, :atom}, default: [:all]]
    ]

  alias RubberDuck.Projects
  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         :ok <- validate_optimizations(params.optimizations),
         {:ok, backup_id} <- create_backup(project, params),
         results <- apply_optimizations(project, params.optimizations, params) do
      {:ok,
       %{
         applied: count_successful(results),
         failed: count_failed(results),
         results: results,
         backup_id: backup_id,
         optimized_at: DateTime.utc_now()
       }}
    end
  end

  defp validate_optimizations(optimizations) do
    if Enum.all?(optimizations, &valid_optimization?/1) do
      :ok
    else
      {:error, :invalid_optimizations}
    end
  end

  defp valid_optimization?(opt) do
    required_keys = [:type, :target, :action]
    Enum.all?(required_keys, &Map.has_key?(opt, &1))
  end

  defp create_backup(project, params) do
    if params.backup && !params.dry_run do
      backup_id = generate_backup_id(project.id)

      case backup_project_state(project, backup_id) do
        :ok -> {:ok, backup_id}
        error -> error
      end
    else
      {:ok, nil}
    end
  end

  defp generate_backup_id(project_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "backup_#{project_id}_#{timestamp}"
  end

  defp backup_project_state(project, backup_id) do
    # In a real implementation, this would create a backup
    # For now, we'll simulate success
    Logger.info("Creating backup #{backup_id} for project #{project.id}")
    :ok
  end

  defp apply_optimizations(project, optimizations, params) do
    filtered_optimizations = filter_optimizations(optimizations, params.apply_filter)

    Enum.map(filtered_optimizations, fn opt ->
      if params.dry_run do
        simulate_optimization(project, opt)
      else
        execute_optimization(project, opt)
      end
    end)
  end

  defp filter_optimizations(optimizations, [:all]), do: optimizations

  defp filter_optimizations(optimizations, filters) do
    Enum.filter(optimizations, fn opt ->
      opt.type in filters
    end)
  end

  defp simulate_optimization(_project, optimization) do
    %{
      optimization: optimization,
      success: true,
      simulated: true,
      changes: describe_changes(optimization),
      impact: estimate_impact(optimization)
    }
  end

  defp execute_optimization(project, optimization) do
    case optimization.type do
      :flatten_structure -> flatten_directory_structure(project, optimization)
      :split_directory -> split_large_directory(project, optimization)
      :reorganize_modules -> reorganize_module_structure(project, optimization)
      :standardize_naming -> standardize_file_naming(project, optimization)
      _ -> {:error, :unknown_optimization_type}
    end
  end

  defp flatten_directory_structure(project, optimization) do
    directories = optimization.target.directories

    results =
      Enum.map(directories, fn dir ->
        flatten_single_directory(project, dir)
      end)

    %{
      optimization: optimization,
      success: Enum.all?(results, & &1.success),
      results: results,
      files_moved: Enum.sum(Enum.map(results, &Map.get(&1, :files_moved, 0)))
    }
  rescue
    e ->
      %{
        optimization: optimization,
        success: false,
        error: Exception.message(e)
      }
  end

  defp flatten_single_directory(project, directory) do
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        dir_files = Enum.filter(files, &String.starts_with?(&1.path, directory))

        moved =
          Enum.map(dir_files, fn file ->
            new_path = calculate_flattened_path(file.path, directory)
            move_file(file, new_path)
          end)

        %{
          directory: directory,
          success: true,
          files_moved: length(moved),
          new_structure: build_new_structure(moved)
        }

      _ ->
        %{directory: directory, success: false, error: "Failed to list files"}
    end
  end

  defp calculate_flattened_path(current_path, base_directory) do
    # Remove unnecessary nesting
    path_parts = Path.split(current_path)
    base_parts = Path.split(base_directory)

    relevant_parts = Enum.drop(path_parts, length(base_parts))

    # Keep only meaningful directory names
    flattened =
      relevant_parts
      |> Enum.reject(&redundant_directory?/1)
      |> Enum.join("/")

    Path.join(base_directory, flattened)
  end

  defp redundant_directory?(dir_name) do
    redundant = ["src", "source", "lib", "code", "impl", "internal"]
    String.downcase(dir_name) in redundant
  end

  defp move_file(file, new_path) do
    # Update the file record with new path
    case Projects.update_code_file(file, %{path: new_path}) do
      {:ok, _updated} ->
        %{
          original_path: file.path,
          new_path: new_path,
          success: true
        }

      error ->
        %{
          original_path: file.path,
          new_path: new_path,
          success: false,
          error: error
        }
    end
  end

  defp build_new_structure(moved_files) do
    moved_files
    |> Enum.map(& &1.new_path)
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp split_large_directory(project, optimization) do
    directory = optimization.target.directory
    file_count = optimization.target.file_count

    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        process_directory_split(files, directory, file_count, optimization)

      _ ->
        %{
          optimization: optimization,
          success: false,
          error: "Failed to list directory files"
        }
    end
  end

  defp process_directory_split(files, directory, file_count, optimization) do
    dir_files = Enum.filter(files, &String.starts_with?(&1.path, directory))
    grouped = group_files_for_splitting(dir_files)
    results = create_subdirectories_and_move(grouped, directory)

    %{
      optimization: optimization,
      success: Enum.all?(results, & &1.success),
      original_file_count: file_count,
      new_directories: length(results),
      details: results
    }
  end

  defp create_subdirectories_and_move(grouped_files, base_directory) do
    Enum.map(grouped_files, fn {subdir_name, group_files} ->
      move_files_to_subdirectory(subdir_name, group_files, base_directory)
    end)
  end

  defp move_files_to_subdirectory(subdir_name, files, base_directory) do
    new_subdir = Path.join(base_directory, subdir_name)

    moved =
      Enum.map(files, fn file ->
        new_path = Path.join(new_subdir, Path.basename(file.path))
        move_file(file, new_path)
      end)

    %{
      subdirectory: new_subdir,
      files_moved: length(moved),
      success: Enum.all?(moved, & &1.success)
    }
  end

  defp group_files_for_splitting(files) do
    files
    |> Enum.group_by(&categorize_file/1)
    |> Enum.reject(fn {_, group} -> length(group) < 3 end)
  end

  defp categorize_file(file) do
    file.path
    |> extract_basename()
    |> find_category()
  end

  defp extract_basename(path) do
    Path.basename(path, Path.extname(path))
  end

  defp find_category(basename) do
    suffix_categories = [
      {"_test", "tests"},
      {"_spec", "specs"}
    ]

    contains_categories = [
      {"controller", "controllers"},
      {"view", "views"},
      {"model", "models"},
      {"service", "services"},
      {"config", "config"}
    ]

    find_by_suffix(basename, suffix_categories) ||
      find_by_contains(basename, contains_categories) ||
      find_special_category(basename) ||
      "core"
  end

  defp find_by_suffix(basename, patterns) do
    Enum.find_value(patterns, fn {suffix, category} ->
      if String.ends_with?(basename, suffix), do: category
    end)
  end

  defp find_by_contains(basename, patterns) do
    Enum.find_value(patterns, fn {pattern, category} ->
      if String.contains?(basename, pattern), do: category
    end)
  end

  defp find_special_category(basename) do
    if category_is_helper?(basename), do: "helpers"
  end

  defp category_is_helper?(basename) do
    String.contains?(basename, "helper") || String.contains?(basename, "util")
  end

  defp reorganize_module_structure(project, optimization) do
    misplaced_modules = optimization.target.modules

    results =
      Enum.map(misplaced_modules, fn module_info ->
        relocate_module(project, module_info)
      end)

    %{
      optimization: optimization,
      success: Enum.all?(results, & &1.success),
      modules_reorganized: length(Enum.filter(results, & &1.success)),
      results: results
    }
  end

  defp relocate_module(project, module_info) do
    current_path = module_info.path
    expected_path = module_info.expected_path

    # Query for code file by project_id and path
    file =
      project.id
      |> Projects.list_code_files_by_project()
      |> Enum.find(fn f -> f.path == current_path end)

    case file do
      nil ->
        %{
          module: module_info.module,
          success: false,
          error: "File not found"
        }

      file ->
        # Update file path and module declaration
        updated_content = update_module_declaration(file.content, module_info.module)

        case Projects.update_code_file(file, %{
               path: expected_path,
               content: updated_content
             }) do
          {:ok, _} ->
            %{
              module: module_info.module,
              success: true,
              old_path: current_path,
              new_path: expected_path
            }

          error ->
            %{
              module: module_info.module,
              success: false,
              error: error
            }
        end
    end
  end

  defp update_module_declaration(content, correct_module_name) do
    # Update the defmodule declaration to match the new location
    Regex.replace(
      ~r/defmodule\s+[\w\.]+/,
      content,
      "defmodule #{correct_module_name}"
    )
  end

  defp standardize_file_naming(project, optimization) do
    files_to_rename = optimization.target.files
    naming_convention = optimization.action.convention || :snake_case

    results =
      Enum.map(files_to_rename, fn file_info ->
        rename_file(project, file_info, naming_convention)
      end)

    %{
      optimization: optimization,
      success: Enum.all?(results, & &1.success),
      files_renamed: length(Enum.filter(results, & &1.success)),
      convention_applied: naming_convention,
      results: results
    }
  end

  defp rename_file(project, file_info, convention) do
    current_path = file_info.path
    new_path = calculate_new_path(current_path, convention)

    if current_path == new_path do
      skip_rename_result(current_path)
    else
      perform_rename(project, current_path, new_path)
    end
  end

  defp calculate_new_path(current_path, convention) do
    basename = Path.basename(current_path, Path.extname(current_path))
    new_basename = apply_naming_convention(basename, convention)

    Path.join(
      Path.dirname(current_path),
      new_basename <> Path.extname(current_path)
    )
  end

  defp skip_rename_result(path) do
    %{
      file: path,
      success: true,
      skipped: true,
      reason: "Already follows convention"
    }
  end

  defp perform_rename(project, current_path, new_path) do
    # Query for code file by project_id and path
    file =
      project.id
      |> Projects.list_code_files_by_project()
      |> Enum.find(fn f -> f.path == current_path end)

    case file do
      nil ->
        {:error, "File not found at #{current_path}"}

      file ->
        update_file_path(file, current_path, new_path)
    end
  end

  defp update_file_path(file, current_path, new_path) do
    case Projects.update_code_file(file, %{path: new_path}) do
      {:ok, _} ->
        %{
          file: current_path,
          success: true,
          old_name: Path.basename(current_path),
          new_name: Path.basename(new_path)
        }

      error ->
        %{
          file: current_path,
          success: false,
          error: error
        }
    end
  end

  defp apply_naming_convention(name, :snake_case) do
    name
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    |> String.replace("-", "_")
    |> String.downcase()
  end

  defp apply_naming_convention(name, :kebab_case) do
    name
    |> apply_naming_convention(:snake_case)
    |> String.replace("_", "-")
  end

  defp apply_naming_convention(name, :camel_case) do
    name
    |> String.split(~r/[_-]/)
    |> Enum.with_index()
    |> Enum.map(fn
      {word, 0} -> String.downcase(word)
      {word, _} -> String.capitalize(word)
    end)
    |> Enum.join()
  end

  defp describe_changes(optimization) do
    case optimization.type do
      :flatten_structure ->
        "Flatten #{length(optimization.target.directories)} directories"

      :split_directory ->
        "Split directory with #{optimization.target.file_count} files"

      :reorganize_modules ->
        "Reorganize #{length(optimization.target.modules)} misplaced modules"

      :standardize_naming ->
        "Standardize naming for #{length(optimization.target.files)} files"

      _ ->
        "Unknown optimization"
    end
  end

  defp estimate_impact(optimization) do
    case optimization.type do
      :flatten_structure ->
        %{
          files_affected: estimate_files_in_directories(optimization.target.directories),
          complexity_reduction: :high,
          navigation_improvement: :high
        }

      :split_directory ->
        %{
          files_affected: optimization.target.file_count,
          organization_improvement: :high,
          maintainability_improvement: :medium
        }

      :reorganize_modules ->
        %{
          modules_affected: length(optimization.target.modules),
          consistency_improvement: :high,
          discoverability_improvement: :medium
        }

      :standardize_naming ->
        %{
          files_affected: length(optimization.target.files),
          consistency_improvement: :medium,
          readability_improvement: :low
        }

      _ ->
        %{}
    end
  end

  defp estimate_files_in_directories(directories) do
    # Estimate based on typical directory sizes
    length(directories) * 10
  end

  defp count_successful(results) do
    Enum.count(results, & &1.success)
  end

  defp count_failed(results) do
    Enum.count(results, &(not &1.success))
  end
end
