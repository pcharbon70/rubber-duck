defmodule RubberDuck.Actions.CodeFile.AnalyzeDependencies do
  @moduledoc """
  Action to analyze dependency relationships and their impact on code files.
  """

  use Jido.Action,
    name: "analyze_dependencies",
    description: "Analyzes dependencies and detects impact of changes",
    schema: [
      file_id: [type: :string, required: true],
      content: [type: :string, required: true],
      file_path: [type: :string, required: true],
      project_files: [type: {:list, :map}, default: []],
      depth: [type: :integer, default: 2]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, imports} <- extract_imports(params.content),
         {:ok, exports} <- extract_exports(params.content),
         {:ok, dependencies} <- analyze_dependencies(imports, params),
         {:ok, dependents} <- find_dependents(exports, params),
         {:ok, impact} <- calculate_change_impact(dependencies, dependents),
         {:ok, result} <- build_analysis_result(imports, exports, dependencies, dependents, impact, params) do
      {:ok, result}
    end
  end

  defp build_analysis_result(imports, exports, dependencies, dependents, impact, params) do
    {:ok, %{
      imports: imports,
      exports: exports,
      dependencies: dependencies,
      dependents: dependents,
      dependency_graph: build_dependency_graph(dependencies, dependents),
      impact_analysis: impact,
      circular_dependencies: detect_circular_dependencies(dependencies, params.file_path),
      unused_imports: detect_unused_imports(imports, params.content)
    }}
  end

  defp extract_imports(content) do
    imports = content
      |> extract_import_statements()
      |> extract_alias_statements()
      |> extract_use_statements()
      |> extract_require_statements()
      |> Enum.uniq()

    {:ok, imports}
  end

  defp extract_exports(content) do
    exports = %{
      functions: extract_public_functions(content),
      macros: extract_public_macros(content),
      types: extract_public_types(content),
      callbacks: extract_callbacks(content)
    }

    {:ok, exports}
  end

  defp analyze_dependencies(imports, params) do
    dependencies = Enum.map(imports, fn import_module ->
      %{
        module: import_module,
        type: categorize_dependency(import_module),
        version: get_dependency_version(import_module),
        usage_count: count_usage_in_file(import_module, params.content),
        is_external: is_external_dependency?(import_module),
        health: check_dependency_health(import_module)
      }
    end)

    {:ok, dependencies}
  end

  defp find_dependents(exports, params) do
    dependents = params.project_files
      |> Enum.filter(&file_depends_on_exports?(&1, exports, params.file_path))
      |> Enum.map(fn file ->
        %{
          file_path: file.path,
          file_id: file.id,
          dependency_type: :direct,
          used_exports: find_used_exports(file.content, exports)
        }
      end)

    {:ok, dependents}
  end

  defp calculate_change_impact(dependencies, dependents) do
    impact = %{
      affected_files_count: length(dependents),
      affected_files: Enum.map(dependents, & &1.file_path),
      external_impact: count_external_impact(dependencies),
      risk_level: assess_risk_level(dependencies, dependents),
      breaking_change_probability: calculate_breaking_change_probability(dependents),
      suggested_actions: generate_impact_suggestions(dependencies, dependents)
    }

    {:ok, impact}
  end

  defp extract_import_statements(content) do
    content
    |> then(&Regex.scan(~r/import\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp extract_alias_statements(content) do
    content
    |> then(&Regex.scan(~r/alias\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp extract_use_statements(content) do
    content
    |> then(&Regex.scan(~r/use\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp extract_require_statements(content) do
    content
    |> then(&Regex.scan(~r/require\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp extract_public_functions(content) do
    content
    |> then(&Regex.scan(~r/def\s+(\w+)/, &1))
    |> Enum.map(fn [_, name] -> name end)
  end

  defp extract_public_macros(content) do
    content
    |> then(&Regex.scan(~r/defmacro\s+(\w+)/, &1))
    |> Enum.map(fn [_, name] -> name end)
  end

  defp extract_public_types(content) do
    content
    |> then(&Regex.scan(~r/@type\s+(\w+)/, &1))
    |> Enum.map(fn [_, name] -> name end)
  end

  defp extract_callbacks(content) do
    content
    |> then(&Regex.scan(~r/@callback\s+(\w+)/, &1))
    |> Enum.map(fn [_, name] -> name end)
  end

  defp categorize_dependency(module) do
    cond do
      String.starts_with?(module, "Elixir.") -> :core
      String.starts_with?(module, "RubberDuck.") -> :internal
      String.contains?(module, ".") -> :external
      true -> :standard
    end
  end

  defp get_dependency_version(_module) do
    # Would integrate with mix.exs or package manager
    "unknown"
  end

  defp count_usage_in_file(module, content) do
    # Count how many times the module is referenced
    short_name = module |> String.split(".") |> List.last()

    content
    |> String.split()
    |> Enum.count(&String.contains?(&1, short_name))
  end

  defp is_external_dependency?(module) do
    not String.starts_with?(module, "RubberDuck.") and
    not String.starts_with?(module, "Elixir.")
  end

  defp check_dependency_health(_module) do
    # Would check for deprecated modules, security issues, etc.
    %{
      status: :healthy,
      issues: [],
      last_updated: nil,
      deprecation_warnings: []
    }
  end

  defp file_depends_on_exports?(file, exports, current_path) do
    # Don't check the current file itself
    if file.path == current_path do
      false
    else
      content = file.content || ""

      # Check if file uses any of the exported functions/macros
      Enum.any?(exports.functions ++ exports.macros, fn export ->
        String.contains?(content, export)
      end)
    end
  end

  defp find_used_exports(content, exports) do
    all_exports = exports.functions ++ exports.macros ++ exports.types

    Enum.filter(all_exports, fn export ->
      String.contains?(content, export)
    end)
  end

  defp count_external_impact(dependencies) do
    dependencies
    |> Enum.filter(& &1.is_external)
    |> length()
  end

  defp assess_risk_level(dependencies, dependents) do
    external_count = count_external_impact(dependencies)
    dependent_count = length(dependents)

    cond do
      dependent_count > 10 or external_count > 5 -> :high
      dependent_count > 5 or external_count > 2 -> :medium
      dependent_count > 0 or external_count > 0 -> :low
      true -> :minimal
    end
  end

  defp calculate_breaking_change_probability(dependents) do
    base_probability = length(dependents) * 0.1
    min(1.0, base_probability)
  end

  defp generate_impact_suggestions(dependencies, dependents) do
    suggestions = []

    suggestions = if length(dependents) > 5 do
      ["Consider creating an interface module to reduce coupling" | suggestions]
    else
      suggestions
    end

    external_deps = Enum.filter(dependencies, & &1.is_external)
    suggestions = if length(external_deps) > 3 do
      ["Review external dependencies for potential consolidation" | suggestions]
    else
      suggestions
    end

    suggestions
  end

  defp build_dependency_graph(dependencies, dependents) do
    %{
      nodes: build_graph_nodes(dependencies, dependents),
      edges: build_graph_edges(dependencies, dependents),
      metrics: %{
        in_degree: length(dependencies),
        out_degree: length(dependents),
        coupling_factor: calculate_coupling_factor(dependencies, dependents)
      }
    }
  end

  defp build_graph_nodes(dependencies, dependents) do
    dep_nodes = Enum.map(dependencies, fn dep ->
      %{id: dep.module, type: :dependency}
    end)

    dependent_nodes = Enum.map(dependents, fn dep ->
      %{id: dep.file_path, type: :dependent}
    end)

    dep_nodes ++ dependent_nodes
  end

  defp build_graph_edges(dependencies, dependents) do
    dep_edges = Enum.map(dependencies, fn dep ->
      %{from: dep.module, to: :current_file, type: :imports}
    end)

    dependent_edges = Enum.map(dependents, fn dep ->
      %{from: :current_file, to: dep.file_path, type: :exports_to}
    end)

    dep_edges ++ dependent_edges
  end

  defp calculate_coupling_factor(dependencies, dependents) do
    total = length(dependencies) + length(dependents)
    if total > 0 do
      total / 10.0
    else
      0.0
    end
  end

  defp detect_circular_dependencies(dependencies, current_path) do
    # Simplified circular dependency detection
    Enum.filter(dependencies, fn dep ->
      # Check if any dependency also depends on the current module
      String.contains?(dep.module, Path.basename(current_path, ".ex"))
    end)
  end

  defp detect_unused_imports(imports, content) do
    Enum.filter(imports, fn import_module ->
      short_name = import_module |> String.split(".") |> List.last()

      # Check if the import is actually used in the code
      usage_count = content
        |> String.replace(~r/import\s+#{Regex.escape(import_module)}/, "")
        |> String.replace(~r/alias\s+#{Regex.escape(import_module)}/, "")
        |> then(&Regex.scan(~r/\b#{short_name}\b/, &1))
        |> length()

      usage_count == 0
    end)
  end
end
