defmodule RubberDuck.Actions.Project.AnalyzeStructure do
  @moduledoc """
  Action to analyze project structure and suggest optimizations.
  """

  use Jido.Action,
    name: "analyze_structure",
    description: "Analyzes project structure for optimization opportunities",
    schema: [
      project_id: [type: :string, required: true],
      include_files: [type: {:list, :string}, default: ["**/*.ex", "**/*.exs"]],
      exclude_patterns: [type: {:list, :string}, default: ["deps/", "_build/", "node_modules/"]],
      depth_limit: [type: :pos_integer, default: 10]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         {:ok, files} <- get_project_files(project, params),
         structure <- analyze_file_structure(files, params.depth_limit),
         metrics <- calculate_structure_metrics(structure),
         optimizations <- suggest_structure_optimizations(structure, metrics) do
      
      {:ok, %{
        structure: structure,
        metrics: metrics,
        optimizations: optimizations,
        analyzed_at: DateTime.utc_now()
      }}
    end
  end

  defp get_project_files(project, params) do
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} -> 
        filtered = files
          |> Enum.filter(&matches_patterns?(&1.path, params.include_files))
          |> Enum.reject(&matches_patterns?(&1.path, params.exclude_patterns))
        {:ok, filtered}
      error -> error
    end
  end

  defp matches_patterns?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      PathGlob.match?(path, pattern)
    end)
  end

  defp analyze_file_structure(files, depth_limit) do
    files
    |> Enum.map(&parse_file_structure/1)
    |> build_directory_tree(depth_limit)
    |> detect_structure_patterns()
  end

  defp parse_file_structure(file) do
    path_parts = Path.split(file.path)
    
    %{
      path: file.path,
      directory: Path.dirname(file.path),
      filename: Path.basename(file.path),
      extension: Path.extname(file.path),
      depth: length(path_parts) - 1,
      module_name: extract_module_name(file),
      size: file.size_bytes || 0,
      language: file.language
    }
  end

  defp extract_module_name(file) do
    # Extract module name from file content if Elixir file
    if file.language == "elixir" && file.content do
      case Regex.run(~r/defmodule\s+([\w\.]+)/, file.content) do
        [_, module_name] -> module_name
        _ -> nil
      end
    end
  end

  defp build_directory_tree(file_structures, depth_limit) do
    file_structures
    |> Enum.group_by(& &1.directory)
    |> Enum.map(fn {dir, files} ->
      %{
        directory: dir,
        depth: length(Path.split(dir)),
        file_count: length(files),
        total_size: Enum.sum(Enum.map(files, & &1.size)),
        files: files,
        subdirectories: count_subdirectories(dir, file_structures)
      }
    end)
    |> Enum.filter(& &1.depth <= depth_limit)
  end

  defp count_subdirectories(dir, all_structures) do
    all_structures
    |> Enum.map(& &1.directory)
    |> Enum.uniq()
    |> Enum.count(fn other_dir ->
      other_dir != dir && String.starts_with?(other_dir, dir <> "/")
    end)
  end

  defp detect_structure_patterns(tree) do
    %{
      tree: tree,
      patterns: %{
        deep_nesting: detect_deep_nesting(tree),
        large_directories: detect_large_directories(tree),
        naming_inconsistencies: detect_naming_inconsistencies(tree),
        module_organization: analyze_module_organization(tree)
      }
    }
  end

  defp detect_deep_nesting(tree) do
    tree
    |> Enum.filter(& &1.depth > 5)
    |> Enum.map(& &1.directory)
  end

  defp detect_large_directories(tree) do
    tree
    |> Enum.filter(& &1.file_count > 20)
    |> Enum.map(fn dir ->
      %{
        directory: dir.directory,
        file_count: dir.file_count,
        suggestion: "Consider breaking into subdirectories"
      }
    end)
  end

  defp detect_naming_inconsistencies(tree) do
    tree
    |> Enum.flat_map(& &1.files)
    |> Enum.group_by(& &1.extension)
    |> Enum.map(fn {ext, files} ->
      naming_styles = detect_naming_styles(files)
      if map_size(naming_styles) > 1 do
        %{
          extension: ext,
          styles: naming_styles,
          suggestion: "Standardize naming convention"
        }
      end
    end)
    |> Enum.filter(& &1)
  end

  defp detect_naming_styles(files) do
    files
    |> Enum.map(& Path.basename(&1.filename, Path.extname(&1.filename)))
    |> Enum.group_by(&categorize_naming_style/1)
    |> Enum.map(fn {style, names} -> {style, length(names)} end)
    |> Map.new()
  end

  defp categorize_naming_style(name) do
    cond do
      name =~ ~r/^[a-z]+(_[a-z]+)*$/ -> :snake_case
      name =~ ~r/^[a-z]+([A-Z][a-z]+)*$/ -> :camelCase
      name =~ ~r/^[A-Z][a-z]+([A-Z][a-z]+)*$/ -> :PascalCase
      name =~ ~r/^[a-z]+(-[a-z]+)*$/ -> :kebab_case
      true -> :other
    end
  end

  defp analyze_module_organization(tree) do
    modules = tree
      |> Enum.flat_map(& &1.files)
      |> Enum.filter(& &1.module_name)
      |> Enum.map(fn file ->
        %{
          module: file.module_name,
          path: file.path,
          expected_path: module_to_expected_path(file.module_name)
        }
      end)

    misplaced = Enum.filter(modules, fn m ->
      !String.ends_with?(m.path, m.expected_path)
    end)

    %{
      total_modules: length(modules),
      misplaced_modules: misplaced
    }
  end

  defp module_to_expected_path(module_name) do
    module_name
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    |> Kernel.<>(".ex")
  end

  defp calculate_structure_metrics(structure) do
    tree = structure.tree
    
    %{
      total_files: Enum.sum(Enum.map(tree, & &1.file_count)),
      total_directories: length(tree),
      average_depth: calculate_average_depth(tree),
      max_depth: Enum.max_by(tree, & &1.depth, fn -> 0 end).depth,
      average_files_per_directory: calculate_average_files_per_dir(tree),
      total_size_bytes: Enum.sum(Enum.map(tree, & &1.total_size)),
      complexity_score: calculate_complexity_score(structure)
    }
  end

  defp calculate_average_depth(tree) do
    if length(tree) > 0 do
      Enum.sum(Enum.map(tree, & &1.depth)) / length(tree)
    else
      0
    end
  end

  defp calculate_average_files_per_dir(tree) do
    dirs_with_files = Enum.filter(tree, & &1.file_count > 0)
    if length(dirs_with_files) > 0 do
      Enum.sum(Enum.map(dirs_with_files, & &1.file_count)) / length(dirs_with_files)
    else
      0
    end
  end

  defp calculate_complexity_score(structure) do
    patterns = structure.patterns
    
    deep_nesting_score = length(patterns.deep_nesting) * 2
    large_dir_score = length(patterns.large_directories) * 3
    naming_score = length(patterns.naming_inconsistencies)
    module_score = length(patterns.module_organization.misplaced_modules) * 2
    
    deep_nesting_score + large_dir_score + naming_score + module_score
  end

  defp suggest_structure_optimizations(structure, metrics) do
    optimizations = []

    # Suggest based on deep nesting
    if length(structure.patterns.deep_nesting) > 0 do
      optimizations = [{:flatten_structure, %{
        directories: structure.patterns.deep_nesting,
        reason: "Deep nesting makes navigation difficult",
        impact: :medium
      }} | optimizations]
    end

    # Suggest based on large directories
    optimizations = optimizations ++ Enum.map(structure.patterns.large_directories, fn dir ->
      {:split_directory, %{
        directory: dir.directory,
        file_count: dir.file_count,
        suggestion: dir.suggestion,
        impact: :high
      }}
    end)

    # Suggest module reorganization
    if length(structure.patterns.module_organization.misplaced_modules) > 0 do
      optimizations = [{:reorganize_modules, %{
        modules: structure.patterns.module_organization.misplaced_modules,
        reason: "Module paths don't match module names",
        impact: :medium
      }} | optimizations]
    end

    # Suggest naming standardization
    optimizations = optimizations ++ Enum.map(structure.patterns.naming_inconsistencies, fn issue ->
      {:standardize_naming, %{
        extension: issue.extension,
        current_styles: issue.styles,
        suggestion: issue.suggestion,
        impact: :low
      }}
    end)

    optimizations
  end
end