defmodule RubberDuck.Actions.Project.AnalyzeImpact do
  @moduledoc """
  Action to analyze the impact of proposed changes on a project.
  """

  use Jido.Action,
    name: "analyze_impact",
    description: "Analyzes the potential impact of proposed changes",
    schema: [
      project_id: [type: :string, required: true],
      changes: [type: {:list, :map}, required: true],
      analysis_depth: [type: :atom, default: :moderate, values: [:shallow, :moderate, :deep]],
      include_dependencies: [type: :boolean, default: true],
      risk_threshold: [type: :float, default: 0.7]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         {:ok, project_context} <- load_project_context(project, params),
         impact_analysis <- analyze_changes(params.changes, project_context, params),
         risk_assessment <- assess_risks(impact_analysis, params.risk_threshold),
         recommendations <- generate_recommendations(impact_analysis, risk_assessment) do

      {:ok, %{
        impact_analysis: impact_analysis,
        risk_assessment: risk_assessment,
        recommendations: recommendations,
        overall_risk: calculate_overall_risk(risk_assessment),
        analyzed_at: DateTime.utc_now()
      }}
    end
  end

  defp load_project_context(project, params) do
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        context = %{
          project: project,
          files: files,
          file_map: build_file_map(files),
          dependency_graph: if params.include_dependencies do
            build_dependency_graph(files)
          else
            %{}
          end,
          module_map: build_module_map(files),
          function_map: build_function_map(files)
        }
        {:ok, context}
      error -> error
    end
  end

  defp build_file_map(files) do
    files
    |> Enum.map(fn file -> {file.path, file} end)
    |> Map.new()
  end

  defp build_dependency_graph(files) do
    files
    |> Enum.filter(& &1.language == "elixir")
    |> Enum.reduce(%{}, fn file, acc ->
      deps = extract_file_dependencies(file)
      Map.put(acc, file.path, deps)
    end)
  end

  defp extract_file_dependencies(file) do
    if file.content do
      imports = extract_imports(file.content)
      aliases = extract_aliases(file.content)
      uses = extract_uses(file.content)

      %{
        imports: imports,
        aliases: aliases,
        uses: uses,
        all: Enum.uniq(imports ++ aliases ++ uses)
      }
    else
      %{imports: [], aliases: [], uses: [], all: []}
    end
  end

  defp extract_imports(content) do
    content
    |> then(&Regex.scan(~r/import\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp extract_aliases(content) do
    content
    |> then(&Regex.scan(~r/alias\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp extract_uses(content) do
    content
    |> then(&Regex.scan(~r/use\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp build_module_map(files) do
    files
    |> Enum.filter(& &1.language == "elixir" && &1.content)
    |> Enum.reduce(%{}, fn file, acc ->
      case extract_module_name(file.content) do
        nil -> acc
        module_name -> Map.put(acc, module_name, file.path)
      end
    end)
  end

  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, module] -> module
      _ -> nil
    end
  end

  defp build_function_map(files) do
    files
    |> Enum.filter(& &1.language == "elixir" && &1.content)
    |> Enum.reduce(%{}, fn file, acc ->
      process_file_functions(file, acc)
    end)
  end

  defp process_file_functions(file, acc) do
    functions = extract_functions(file.content)
    module_name = extract_module_name(file.content)

    if module_name do
      add_module_functions(functions, module_name, file.path, acc)
    else
      acc
    end
  end

  defp add_module_functions(functions, module_name, file_path, acc) do
    Enum.reduce(functions, acc, fn func, inner_acc ->
      key = "#{module_name}.#{func.name}/#{func.arity}"
      Map.put(inner_acc, key, %{
        file: file_path,
        function: func,
        module: module_name
      })
    end)
  end

  defp extract_functions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+(\w+)(?:\(([^)]*)\))?/, &1))
    |> Enum.map(fn
      [_, name, args] ->
        arity = if args && args != "" do
          length(String.split(args, ","))
        else
          0
        end
        %{name: name, arity: arity}
      [_, name] ->
        %{name: name, arity: 0}
    end)
  end

  defp analyze_changes(changes, context, params) do
    Enum.map(changes, fn change ->
      analyze_single_change(change, context, params.analysis_depth)
    end)
  end

  defp analyze_single_change(change, context, depth) do
    base_impact = analyze_direct_impact(change, context)

    enhanced_impact = case depth do
      :shallow -> base_impact
      :moderate -> enhance_with_dependencies(base_impact, context)
      :deep -> deep_analysis(base_impact, context)
    end

    %{
      change: change,
      direct_impact: base_impact,
      ripple_effects: enhanced_impact.ripple_effects || [],
      affected_files: enhanced_impact.affected_files || base_impact.affected_files,
      affected_modules: enhanced_impact.affected_modules || [],
      affected_functions: enhanced_impact.affected_functions || [],
      complexity_score: calculate_complexity_score(enhanced_impact),
      confidence: calculate_confidence(enhanced_impact, depth)
    }
  end

  defp analyze_direct_impact(change, context) do
    case change.type do
      :file_modification -> analyze_file_modification(change, context)
      :function_change -> analyze_function_change(change, context)
      :module_refactor -> analyze_module_refactor(change, context)
      :dependency_update -> analyze_dependency_update(change, context)
      :structure_change -> analyze_structure_change(change, context)
      _ -> %{affected_files: [], impact_type: :unknown}
    end
  end

  defp analyze_file_modification(change, context) do
    file_path = change.target.file_path
    file = Map.get(context.file_map, file_path)

    if file do
      %{
        affected_files: [file_path],
        impact_type: :direct_modification,
        file_details: %{
          size: file.size_bytes,
          language: file.language,
          has_tests: has_associated_tests?(file_path, context)
        }
      }
    else
      %{
        affected_files: [file_path],
        impact_type: :new_file
      }
    end
  end

  defp analyze_function_change(change, context) do
    function_key = "#{change.target.module}.#{change.target.function}/#{change.target.arity}"
    function_info = Map.get(context.function_map, function_key)

    if function_info do
      callers = find_function_callers(function_key, context)

      %{
        affected_files: [function_info.file | Enum.map(callers, & &1.file)] |> Enum.uniq(),
        affected_functions: [function_key | Enum.map(callers, & &1.function)],
        impact_type: :function_modification,
        caller_count: length(callers)
      }
    else
      %{
        affected_files: [],
        impact_type: :function_not_found
      }
    end
  end

  defp analyze_module_refactor(change, context) do
    module_name = change.target.module
    module_file = Map.get(context.module_map, module_name)

    if module_file do
      dependents = find_module_dependents(module_name, context)

      %{
        affected_files: [module_file | dependents] |> Enum.uniq(),
        affected_modules: [module_name],
        impact_type: :module_refactor,
        dependent_count: length(dependents)
      }
    else
      %{
        affected_files: [],
        impact_type: :module_not_found
      }
    end
  end

  defp analyze_dependency_update(change, context) do
    dep_name = change.target.dependency
    affected = find_files_using_dependency(dep_name, context)

    %{
      affected_files: affected,
      impact_type: :dependency_change,
      dependency_usage_count: length(affected),
      version_change: %{
        from: change.target.current_version,
        to: change.target.new_version
      }
    }
  end

  defp analyze_structure_change(change, context) do
    case change.target.structure_type do
      :directory_move ->
        files_in_dir = find_files_in_directory(change.target.from, context)
        %{
          affected_files: files_in_dir,
          impact_type: :structure_reorganization,
          files_to_move: length(files_in_dir)
        }

      :file_rename ->
        old_path = change.target.from
        importers = find_file_importers(old_path, context)
        %{
          affected_files: [old_path | importers] |> Enum.uniq(),
          impact_type: :file_rename,
          import_updates_needed: length(importers)
        }

      _ ->
        %{affected_files: [], impact_type: :unknown_structure_change}
    end
  end

  defp has_associated_tests?(file_path, context) do
    test_path = file_path
      |> String.replace("lib/", "test/")
      |> String.replace(".ex", "_test.exs")

    Map.has_key?(context.file_map, test_path)
  end

  defp find_function_callers(function_key, context) do
    # In a real implementation, this would parse and analyze all files
    # For now, return empty list
    []
  end

  defp find_module_dependents(module_name, context) do
    context.dependency_graph
    |> Enum.filter(fn {_, deps} ->
      module_name in deps.all
    end)
    |> Enum.map(fn {file, _} -> file end)
  end

  defp find_files_using_dependency(dep_name, context) do
    # Simple heuristic: files that might use the dependency
    context.files
    |> Enum.filter(fn file ->
      file.content && String.contains?(file.content, dep_name)
    end)
    |> Enum.map(& &1.path)
  end

  defp find_files_in_directory(dir, context) do
    context.files
    |> Enum.filter(&String.starts_with?(&1.path, dir))
    |> Enum.map(& &1.path)
  end

  defp find_file_importers(file_path, context) do
    module_name = case Map.get(context.file_map, file_path) do
      nil -> nil
      file -> extract_module_name(file.content)
    end

    if module_name do
      find_module_dependents(module_name, context)
    else
      []
    end
  end

  defp enhance_with_dependencies(base_impact, context) do
    ripple_effects = calculate_ripple_effects(base_impact, context)

    Map.merge(base_impact, %{
      ripple_effects: ripple_effects,
      affected_files: Enum.uniq(base_impact.affected_files ++ extract_ripple_files(ripple_effects)),
      affected_modules: extract_affected_modules(ripple_effects)
    })
  end

  defp calculate_ripple_effects(impact, context) do
    # Analyze how changes propagate through the dependency graph
    affected_files = impact.affected_files || []

    affected_files
    |> Enum.flat_map(fn file ->
      deps = Map.get(context.dependency_graph, file, %{all: []})
      dependents = find_module_dependents_for_file(file, context)

      [
        %{
          type: :dependencies,
          file: file,
          affected: deps.all
        },
        %{
          type: :dependents,
          file: file,
          affected: dependents
        }
      ]
    end)
    |> Enum.filter(& length(&1.affected) > 0)
  end

  defp find_module_dependents_for_file(file_path, context) do
    case Map.get(context.file_map, file_path) do
      nil -> []
      file ->
        case extract_module_name(file.content) do
          nil -> []
          module_name -> find_module_dependents(module_name, context)
        end
    end
  end

  defp extract_ripple_files(ripple_effects) do
    ripple_effects
    |> Enum.flat_map(& &1.affected)
    |> Enum.uniq()
  end

  defp extract_affected_modules(ripple_effects) do
    ripple_effects
    |> Enum.flat_map(& &1.affected)
    |> Enum.filter(&is_module_name?/1)
    |> Enum.uniq()
  end

  defp is_module_name?(string) do
    string =~ ~r/^[A-Z]\w*(\.[A-Z]\w*)*$/
  end

  defp deep_analysis(base_impact, context) do
    enhanced = enhance_with_dependencies(base_impact, context)

    # Add test coverage analysis
    test_coverage = analyze_test_coverage(enhanced.affected_files, context)

    # Add performance implications
    performance_impact = analyze_performance_impact(enhanced, context)

    Map.merge(enhanced, %{
      test_coverage: test_coverage,
      performance_impact: performance_impact,
      api_changes: detect_api_changes(enhanced, context),
      database_impact: detect_database_impact(enhanced, context)
    })
  end

  defp analyze_test_coverage(affected_files, context) do
    files_with_tests = Enum.filter(affected_files, &has_associated_tests?(&1, context))

    %{
      covered_files: length(files_with_tests),
      total_files: length(affected_files),
      coverage_ratio: if length(affected_files) > 0 do
        length(files_with_tests) / length(affected_files)
      else
        0.0
      end
    }
  end

  defp analyze_performance_impact(impact, _context) do
    # Heuristic-based performance impact
    cond do
      impact[:impact_type] == :dependency_change -> :high
      length(Map.get(impact, :affected_files, [])) > 10 -> :medium
      Map.get(impact, :caller_count, 0) > 5 -> :medium
      true -> :low
    end
  end

  defp detect_api_changes(impact, context) do
    # Check if any affected files are controllers or API modules
    api_files = Enum.filter(impact.affected_files, fn file ->
      String.contains?(file, "controller") ||
      String.contains?(file, "api") ||
      String.contains?(file, "endpoint")
    end)

    %{
      has_api_changes: length(api_files) > 0,
      affected_endpoints: api_files
    }
  end

  defp detect_database_impact(impact, context) do
    # Check for migration or schema changes
    db_files = Enum.filter(impact.affected_files, fn file ->
      String.contains?(file, "migration") ||
      String.contains?(file, "schema") ||
      String.contains?(file, "ecto")
    end)

    %{
      has_database_changes: length(db_files) > 0,
      migration_required: Enum.any?(db_files, &String.contains?(&1, "migration"))
    }
  end

  defp calculate_complexity_score(impact) do
    base_score = length(Map.get(impact, :affected_files, []))

    multipliers = [
      {Map.get(impact, :caller_count, 0) > 10, 2.0},
      {Map.get(impact, :dependent_count, 0) > 5, 1.5},
      {length(Map.get(impact, :ripple_effects, [])) > 10, 1.8},
      {get_in(impact, [:api_changes, :has_api_changes]) == true, 2.5},
      {get_in(impact, [:database_impact, :migration_required]) == true, 3.0}
    ]

    Enum.reduce(multipliers, base_score * 1.0, fn {condition, mult}, acc ->
      if condition, do: acc * mult, else: acc
    end)
  end

  defp calculate_confidence(impact, depth) do
    base_confidence = case depth do
      :shallow -> 0.6
      :moderate -> 0.8
      :deep -> 0.9
    end

    # Adjust based on analysis completeness
    adjustments = [
      {Map.has_key?(impact, :ripple_effects), 0.05},
      {Map.has_key?(impact, :test_coverage), 0.05},
      {Map.get(impact, :impact_type) != :unknown, 0.05}
    ]

    Enum.reduce(adjustments, base_confidence, fn {condition, adj}, acc ->
      if condition, do: min(1.0, acc + adj), else: acc
    end)
  end

  defp assess_risks(impact_analysis, risk_threshold) do
    Enum.map(impact_analysis, fn analysis ->
      risk_factors = identify_risk_factors(analysis)
      risk_score = calculate_risk_score(risk_factors)

      %{
        change: analysis.change,
        risk_score: risk_score,
        risk_level: categorize_risk_level(risk_score),
        risk_factors: risk_factors,
        high_risk: risk_score >= risk_threshold,
        mitigation_required: risk_score >= risk_threshold
      }
    end)
  end

  defp identify_risk_factors(analysis) do
    factors = []

    # File count risk
    factors = if length(analysis.affected_files) > 20 do
      [{:high_file_count, %{
        count: length(analysis.affected_files),
        severity: :high
      }} | factors]
    else
      factors
    end

    # Complexity risk
    factors = if analysis.complexity_score > 50 do
      [{:high_complexity, %{
        score: analysis.complexity_score,
        severity: :high
      }} | factors]
    else
      factors
    end

    # Test coverage risk
    factors = if get_in(analysis, [:direct_impact, :test_coverage, :coverage_ratio]) < 0.5 do
      [{:low_test_coverage, %{
        ratio: get_in(analysis, [:direct_impact, :test_coverage, :coverage_ratio]),
        severity: :medium
      }} | factors]
    else
      factors
    end

    # API change risk
    factors = if get_in(analysis, [:direct_impact, :api_changes, :has_api_changes]) do
      [{:api_changes, %{
        endpoints: get_in(analysis, [:direct_impact, :api_changes, :affected_endpoints]),
        severity: :high
      }} | factors]
    else
      factors
    end

    # Database risk
    factors = if get_in(analysis, [:direct_impact, :database_impact, :migration_required]) do
      [{:database_migration, %{
        severity: :high
      }} | factors]
    else
      factors
    end

    factors
  end

  defp calculate_risk_score(risk_factors) do
    severity_scores = %{
      low: 0.2,
      medium: 0.5,
      high: 0.8
    }

    if Enum.empty?(risk_factors) do
      0.1
    else
      total_score = Enum.sum(Enum.map(risk_factors, fn {_, details} ->
        Map.get(severity_scores, details.severity, 0.5)
      end))

      min(1.0, total_score / length(risk_factors) * 1.5)
    end
  end

  defp categorize_risk_level(score) do
    cond do
      score >= 0.8 -> :critical
      score >= 0.6 -> :high
      score >= 0.4 -> :medium
      score >= 0.2 -> :low
      true -> :minimal
    end
  end

  defp generate_recommendations(impact_analysis, risk_assessment) do
    impact_analysis
    |> Enum.zip(risk_assessment)
    |> Enum.map(fn {impact, risk} ->
      %{
        change: impact.change,
        recommendations: build_recommendations(impact, risk),
        priority: determine_priority(impact, risk),
        estimated_effort: estimate_effort(impact, risk)
      }
    end)
  end

  defp build_recommendations(impact, risk) do
    recs = []

    # High risk recommendations
    recs = if risk.high_risk do
      [
        "Consider breaking this change into smaller, incremental updates",
        "Ensure comprehensive testing before deployment",
        "Plan for rollback strategy"
        | recs
      ]
    else
      recs
    end

    # Test coverage recommendations
    recs = if get_in(impact, [:direct_impact, :test_coverage, :coverage_ratio], 1.0) < 0.8 do
      ["Add or improve test coverage for affected files" | recs]
    else
      recs
    end

    # API change recommendations
    recs = if get_in(impact, [:direct_impact, :api_changes, :has_api_changes]) do
      [
        "Update API documentation",
        "Version the API if breaking changes are introduced",
        "Notify API consumers of changes"
        | recs
      ]
    else
      recs
    end

    # Database recommendations
    recs = if get_in(impact, [:direct_impact, :database_impact, :migration_required]) do
      [
        "Test database migration on staging environment",
        "Plan for migration rollback",
        "Consider migration performance impact"
        | recs
      ]
    else
      recs
    end

    # Performance recommendations
    recs = if impact[:performance_impact] == :high do
      ["Monitor performance metrics after deployment" | recs]
    else
      recs
    end

    Enum.reverse(recs)
  end

  defp determine_priority(impact, risk) do
    cond do
      risk.risk_level == :critical -> :immediate
      risk.risk_level == :high && length(impact.affected_files) > 10 -> :high
      risk.risk_level == :medium || length(impact.affected_files) > 5 -> :medium
      true -> :low
    end
  end

  defp estimate_effort(impact, risk) do
    base_hours = length(impact.affected_files) * 0.5

    multipliers = [
      {risk.risk_level == :critical, 3.0},
      {risk.risk_level == :high, 2.0},
      {get_in(impact, [:direct_impact, :api_changes, :has_api_changes]), 1.5},
      {get_in(impact, [:direct_impact, :database_impact, :migration_required]), 2.0},
      {length(Map.get(impact, :ripple_effects, [])) > 10, 1.5}
    ]

    estimated_hours = Enum.reduce(multipliers, base_hours, fn {condition, mult}, acc ->
      if condition, do: acc * mult, else: acc
    end)

    %{
      hours: Float.round(estimated_hours, 1),
      confidence: if(risk.risk_level in [:critical, :high], do: :low, else: :medium)
    }
  end

  defp calculate_overall_risk(risk_assessment) do
    risk_scores = Enum.map(risk_assessment, & &1.risk_score)

    %{
      average_risk: Enum.sum(risk_scores) / max(length(risk_scores), 1),
      max_risk: Enum.max(risk_scores, fn -> 0 end),
      critical_count: Enum.count(risk_assessment, & &1.risk_level == :critical),
      high_risk_count: Enum.count(risk_assessment, & &1.high_risk)
    }
  end
end
