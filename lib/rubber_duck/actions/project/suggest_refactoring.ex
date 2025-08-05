defmodule RubberDuck.Actions.Project.SuggestRefactoring do
  @moduledoc """
  Action to suggest refactoring opportunities based on code analysis.
  """

  use Jido.Action,
    name: "suggest_refactoring",
    description: "Analyzes code and suggests refactoring opportunities",
    schema: [
      project_id: [type: :string, required: true],
      quality_metrics: [type: :map, required: false],
      focus_areas: [type: {:list, :atom}, default: [:all]],
      max_suggestions: [type: :pos_integer, default: 10],
      confidence_threshold: [type: :float, default: 0.7]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         {:ok, files} <- get_analyzable_files(project),
         suggestions <- generate_suggestions(files, params),
         prioritized <- prioritize_suggestions(suggestions, params.max_suggestions) do

      {:ok, %{
        suggestions: prioritized,
        total_found: length(suggestions),
        suggested_at: DateTime.utc_now()
      }}
    end
  end

  defp get_analyzable_files(project) do
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        filtered = files
          |> Enum.filter(& &1.content && &1.language == "elixir")
        {:ok, filtered}
      error -> error
    end
  end

  defp generate_suggestions(files, params) do
    files
    |> Enum.flat_map(fn file ->
      analyze_file_for_refactoring(file, params)
    end)
    |> Enum.filter(& &1.confidence >= params.confidence_threshold)
  end

  defp analyze_file_for_refactoring(file, params) do
    suggestions = []

    # Analyze based on focus areas
    focus_areas = if :all in params.focus_areas do
      [:complexity, :duplication, :naming, :structure, :patterns]
    else
      params.focus_areas
    end

    suggestions = if :complexity in focus_areas do
      suggestions ++ analyze_complexity_refactorings(file)
    else
      suggestions
    end

    suggestions = if :duplication in focus_areas do
      suggestions ++ analyze_duplication_refactorings(file)
    else
      suggestions
    end

    suggestions = if :naming in focus_areas do
      suggestions ++ analyze_naming_refactorings(file)
    else
      suggestions
    end

    suggestions = if :structure in focus_areas do
      suggestions ++ analyze_structure_refactorings(file)
    else
      suggestions
    end

    suggestions = if :patterns in focus_areas do
      suggestions ++ analyze_pattern_refactorings(file)
    else
      suggestions
    end

    suggestions
  end

  defp analyze_complexity_refactorings(file) do
    content = file.content
    suggestions = []

    # Find complex functions
    functions = extract_functions(content)

    complex_functions = functions
      |> Enum.filter(& &1.complexity > 10)
      |> Enum.map(fn func ->
        %{
          type: :extract_function,
          file_path: file.path,
          location: func.location,
          function_name: func.name,
          current_complexity: func.complexity,
          title: "Extract sub-functions from #{func.name}/#{func.arity}",
          description: "Function has cyclomatic complexity of #{func.complexity}. Consider extracting helper functions.",
          confidence: calculate_complexity_confidence(func.complexity),
          impact: :high,
          effort: :medium,
          suggested_changes: suggest_function_extraction(func)
        }
      end)

    # Find deeply nested code
    nested_blocks = find_nested_blocks(content)

    deep_nesting = nested_blocks
      |> Enum.filter(& &1.depth > 4)
      |> Enum.map(fn block ->
        %{
          type: :reduce_nesting,
          file_path: file.path,
          location: block.location,
          current_depth: block.depth,
          title: "Reduce nesting depth",
          description: "Code block has nesting depth of #{block.depth}. Consider using guard clauses or extracting functions.",
          confidence: 0.8,
          impact: :medium,
          effort: :low,
          suggested_changes: suggest_nesting_reduction(block)
        }
      end)

    suggestions ++ complex_functions ++ deep_nesting
  end

  defp analyze_duplication_refactorings(file) do
    content = file.content
    duplicates = find_duplicate_code(content)

    duplicates
    |> Enum.map(fn dup ->
      %{
        type: :remove_duplication,
        file_path: file.path,
        locations: dup.locations,
        duplicate_lines: dup.line_count,
        title: "Extract duplicate code",
        description: "Found #{dup.line_count} lines of duplicate code in #{length(dup.locations)} locations",
        confidence: calculate_duplication_confidence(dup),
        impact: :medium,
        effort: :low,
        suggested_changes: suggest_duplication_fix(dup)
      }
    end)
  end

  defp analyze_naming_refactorings(file) do
    content = file.content
    suggestions = []

    # Check module naming
    module_issues = check_module_naming(file.path, content)
    suggestions = suggestions ++ module_issues

    # Check function naming
    function_issues = check_function_naming(content)
    suggestions = suggestions ++ function_issues

    # Check variable naming
    variable_issues = check_variable_naming(content)
    suggestions = suggestions ++ variable_issues

    suggestions
  end

  defp analyze_structure_refactorings(file) do
    content = file.content
    suggestions = []

    # Check for large modules
    module_size = count_module_lines(content)
    if module_size > 300 do
      suggestions = [%{
        type: :split_module,
        file_path: file.path,
        current_size: module_size,
        title: "Split large module",
        description: "Module has #{module_size} lines. Consider splitting into smaller, focused modules.",
        confidence: 0.9,
        impact: :high,
        effort: :high,
        suggested_changes: suggest_module_split(file, content)
      } | suggestions]
    end

    # Check for misplaced functions
    misplaced = find_misplaced_functions(content)
    suggestions = suggestions ++ Enum.map(misplaced, fn func ->
      %{
        type: :move_function,
        file_path: file.path,
        function_name: func.name,
        title: "Move #{func.name}/#{func.arity} to appropriate module",
        description: "Function appears to belong in a different module based on its responsibilities",
        confidence: func.confidence,
        impact: :medium,
        effort: :low,
        suggested_changes: %{suggested_module: func.suggested_module}
      }
    end)

    suggestions
  end

  defp analyze_pattern_refactorings(file) do
    content = file.content
    suggestions = []

    # Check for pattern matching opportunities
    pattern_opportunities = find_pattern_matching_opportunities(content)
    suggestions = suggestions ++ pattern_opportunities

    # Check for pipeline opportunities
    pipeline_opportunities = find_pipeline_opportunities(content)
    suggestions = suggestions ++ pipeline_opportunities

    # Check for with statement opportunities
    with_opportunities = find_with_opportunities(content)
    suggestions = suggestions ++ with_opportunities

    suggestions
  end

  defp extract_functions(content) do
    # Extract function definitions with their complexity
    lines = String.split(content, "\n")

    content
    |> then(&Regex.scan(~r/def(?:p?)\s+(\w+)(?:\(([^)]*)\))?/, &1))
    |> Enum.map(&build_function_info(&1, lines, content))
  end

  defp build_function_info([full, name, args], lines, content) do
    build_function_map(name, calculate_arity(args), full, lines, content)
  end

  defp build_function_info([full, name], lines, content) do
    build_function_map(name, 0, full, lines, content)
  end

  defp calculate_arity(nil), do: 0
  defp calculate_arity(""), do: 0
  defp calculate_arity(args), do: length(String.split(args, ","))

  defp build_function_map(name, arity, full_match, lines, content) do
    body = extract_function_body(content, name)

    %{
      name: name,
      arity: arity,
      location: find_line_number(lines, full_match),
      complexity: calculate_function_complexity(body),
      length: count_function_lines(body)
    }
  end

  defp find_line_number(lines, text) do
    Enum.find_index(lines, &String.contains?(&1, text)) || 0
  end

  defp extract_function_body(content, function_name) do
    # Extract the body of a specific function
    case Regex.run(~r/def(?:p?)\s+#{function_name}.*?do(.*?)(\n\s*end|\n\s*def)/ms, content) do
      [_, body, _] -> body
      _ -> ""
    end
  end

  defp calculate_function_complexity(body) do
    # Count decision points
    patterns = [
      ~r/\bif\b/, ~r/\bunless\b/, ~r/\bcase\b/, ~r/\bcond\b/,
      ~r/\bwith\b/, ~r/\band\b/, ~r/\bor\b/, ~r/->/, ~r/\&\&/, ~r/\|\|/
    ]

    1 + Enum.sum(Enum.map(patterns, fn pattern ->
      length(Regex.scan(pattern, body))
    end))
  end

  defp count_function_lines(body) do
    body
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end

  defp calculate_complexity_confidence(complexity) do
    cond do
      complexity > 20 -> 0.95
      complexity > 15 -> 0.85
      complexity > 10 -> 0.75
      true -> 0.65
    end
  end

  defp suggest_function_extraction(func) do
    %{
      extract_count: div(func.complexity, 5),
      suggested_names: generate_helper_function_names(func.name, div(func.complexity, 5)),
      refactoring_approach: "Extract conditional logic into separate functions"
    }
  end

  defp generate_helper_function_names(base_name, count) do
    1..count
    |> Enum.map(fn i ->
      "#{base_name}_helper_#{i}"
    end)
  end

  defp find_nested_blocks(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      depth = calculate_nesting_depth(line, lines, index)
      %{
        location: index + 1,
        depth: depth,
        line: line
      }
    end)
    |> Enum.filter(& &1.depth > 0)
    |> Enum.group_by(& &1.depth)
    |> Enum.flat_map(fn {depth, blocks} ->
      if depth > 4 do
        [%{
          location: hd(blocks).location,
          depth: depth,
          block_size: length(blocks)
        }]
      else
        []
      end
    end)
  end

  defp calculate_nesting_depth(line, _lines, _index) do
    # Simple nesting calculation based on indentation
    indent = String.length(line) - String.length(String.trim_leading(line))
    div(indent, 2) # Assuming 2-space indentation
  end

  defp suggest_nesting_reduction(block) do
    %{
      techniques: [
        "Use guard clauses to exit early",
        "Extract nested logic into separate functions",
        "Consider using 'with' for sequential operations",
        "Flatten conditional logic using pattern matching"
      ],
      example: generate_guard_clause_example()
    }
  end

  defp generate_guard_clause_example do
    """
    # Instead of:
    def process(data) do
      if valid?(data) do
        if authorized?(data) do
          # nested logic
        end
      end
    end

    # Use:
    def process(data) do
      with :ok <- validate(data),
           :ok <- authorize(data) do
        # main logic
      end
    end
    """
  end

  defp find_duplicate_code(content) do
    lines = String.split(content, "\n")

    # Find sequences of similar lines
    sequences = find_similar_sequences(lines, 3) # Min 3 lines

    sequences
    |> Enum.map(fn seq ->
      %{
        locations: seq.locations,
        line_count: seq.length,
        content: seq.content
      }
    end)
  end

  defp find_similar_sequences(lines, min_length) do
    # Simple duplicate detection - find exact matches
    indexed_lines = Enum.with_index(lines)

    indexed_lines
    |> Enum.chunk_every(min_length, 1, :discard)
    |> Enum.group_by(fn chunk ->
      chunk
      |> Enum.map(fn {line, _} -> String.trim(line) end)
      |> Enum.join("\n")
    end)
    |> Enum.filter(fn {_, occurrences} -> length(occurrences) > 1 end)
    |> Enum.map(fn {content, occurrences} ->
      %{
        content: content,
        length: min_length,
        locations: Enum.map(occurrences, fn chunk ->
          {_, index} = hd(chunk)
          index + 1
        end)
      }
    end)
  end

  defp calculate_duplication_confidence(dup) do
    base = 0.7
    length_bonus = min(0.2, dup.line_count * 0.02)
    occurrence_bonus = min(0.1, (length(dup.locations) - 2) * 0.05)

    base + length_bonus + occurrence_bonus
  end

  defp suggest_duplication_fix(dup) do
    %{
      approach: "Extract to shared function",
      suggested_function_name: "extracted_common_logic",
      estimated_loc_saved: dup.line_count * (length(dup.locations) - 1)
    }
  end

  defp check_module_naming(file_path, content) do
    expected_module = path_to_module_name(file_path)

    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, actual_module] ->
        if actual_module != expected_module do
          [%{
            type: :rename_module,
            file_path: file_path,
            current_name: actual_module,
            suggested_name: expected_module,
            title: "Rename module to match file path",
            description: "Module name doesn't match file path convention",
            confidence: 0.9,
            impact: :low,
            effort: :low,
            suggested_changes: %{
              from: actual_module,
              to: expected_module
            }
          }]
        else
          []
        end
      _ -> []
    end
  end

  defp path_to_module_name(path) do
    path
    |> String.replace(~r/^lib\//, "")
    |> String.replace(~r/\.ex$/, "")
    |> String.split("/")
    |> Enum.map(&Macro.camelize/1)
    |> Enum.join(".")
  end

  defp check_function_naming(content) do
    functions = Regex.scan(~r/def(?:p?)\s+(\w+)/, content)

    functions
    |> Enum.flat_map(fn [_, name] ->
      issues = []

      # Check for non-snake_case
      if name =~ ~r/[A-Z]/ do
        issues = [%{
          type: :rename_function,
          current_name: name,
          suggested_name: Macro.underscore(name),
          title: "Use snake_case for function names",
          description: "Function '#{name}' should use snake_case naming",
          confidence: 0.95,
          impact: :low,
          effort: :low
        } | issues]
      end

      # Check for unclear abbreviations
      if has_unclear_abbreviation?(name) do
        issues = [%{
          type: :clarify_naming,
          current_name: name,
          title: "Expand unclear abbreviation in '#{name}'",
          description: "Consider using more descriptive names",
          confidence: 0.7,
          impact: :low,
          effort: :low
        } | issues]
      end

      issues
    end)
  end

  defp has_unclear_abbreviation?(name) do
    unclear_abbrevs = ["tmp", "var", "val", "obj", "ctx", "res", "req", "msg"]
    Enum.any?(unclear_abbrevs, &String.contains?(name, &1))
  end

  defp check_variable_naming(content) do
    # Find variable assignments
    variables = Regex.scan(~r/(\w+)\s*=/, content)

    variables
    |> Enum.flat_map(fn [_, var_name] ->
      if String.length(var_name) == 1 && var_name != "_" do
        [%{
          type: :rename_variable,
          current_name: var_name,
          title: "Use descriptive variable name instead of '#{var_name}'",
          description: "Single letter variables reduce code readability",
          confidence: 0.8,
          impact: :low,
          effort: :low
        }]
      else
        []
      end
    end)
  end

  defp count_module_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp suggest_module_split(file, content) do
    functions = extract_functions(content)

    # Group functions by potential responsibility
    grouped = group_functions_by_responsibility(functions)

    %{
      suggested_modules: Enum.map(grouped, fn {group_name, funcs} ->
        %{
          name: "#{Path.basename(file.path, ".ex")}_#{group_name}",
          functions: Enum.map(funcs, & &1.name),
          estimated_size: Enum.sum(Enum.map(funcs, & &1.length))
        }
      end),
      splitting_strategy: "Group by responsibility/feature"
    }
  end

  defp group_functions_by_responsibility(functions) do
    # Simple grouping by name patterns
    functions
    |> Enum.group_by(&categorize_function_responsibility/1)
    |> Enum.filter(fn {_, funcs} -> length(funcs) > 2 end)
  end

  defp categorize_function_responsibility(func) do
    name = func.name

    responsibility_patterns = [
      {["create", "new"], "creation"},
      {["update", "change"], "modification"},
      {["delete", "remove"], "deletion"},
      {["get", "find"], "queries"},
      {["validate", "check"], "validation"}
    ]

    Enum.find_value(responsibility_patterns, "core", fn {patterns, category} ->
      if Enum.any?(patterns, &String.contains?(name, &1)), do: category
    end)
  end

  defp find_misplaced_functions(content) do
    # This would require more context about the codebase
    # For now, return empty list
    []
  end

  defp find_pattern_matching_opportunities(content) do
    opportunities = []

    # Find if-else chains that could be pattern matching
    if_else_chains = Regex.scan(~r/if\s+.*?do.*?else.*?end/s, content)

    opportunities = opportunities ++ Enum.map(if_else_chains, fn [chain] ->
      %{
        type: :use_pattern_matching,
        title: "Replace if-else with pattern matching",
        description: "Consider using case or function heads with pattern matching",
        confidence: 0.7,
        impact: :low,
        effort: :low,
        example: generate_pattern_matching_example()
      }
    end)

    opportunities
  end

  defp generate_pattern_matching_example do
    """
    # Instead of:
    if result == :ok do
      handle_success()
    else
      handle_error()
    end

    # Use:
    case result do
      :ok -> handle_success()
      _ -> handle_error()
    end
    """
  end

  defp find_pipeline_opportunities(content) do
    # Find nested function calls that could be pipelines
    nested_calls = Regex.scan(~r/(\w+\(.*\w+\(.*\).*\))/, content)

    Enum.map(nested_calls, fn [call] ->
      %{
        type: :use_pipeline,
        title: "Convert nested calls to pipeline",
        description: "Use |> operator for better readability",
        confidence: 0.8,
        impact: :low,
        effort: :low,
        code_snippet: call
      }
    end)
  end

  defp find_with_opportunities(content) do
    # Find sequential error handling that could use 'with'
    case_sequences = Regex.scan(~r/case\s+.*?do.*?{:ok.*?case\s+.*?do/s, content)

    Enum.map(case_sequences, fn [sequence] ->
      %{
        type: :use_with,
        title: "Use 'with' for sequential operations",
        description: "Replace nested case statements with 'with' expression",
        confidence: 0.85,
        impact: :medium,
        effort: :low,
        example: generate_with_example()
      }
    end)
  end

  defp generate_with_example do
    """
    # Instead of nested cases:
    case fetch_user(id) do
      {:ok, user} ->
        case authorize(user) do
          {:ok, _} -> perform_action(user)
          error -> error
        end
      error -> error
    end

    # Use with:
    with {:ok, user} <- fetch_user(id),
         {:ok, _} <- authorize(user) do
      perform_action(user)
    end
    """
  end

  defp prioritize_suggestions(suggestions, max_count) do
    suggestions
    |> Enum.sort_by(&calculate_priority_score/1, :desc)
    |> Enum.take(max_count)
  end

  defp calculate_priority_score(suggestion) do
    impact_scores = %{high: 3, medium: 2, low: 1}
    effort_scores = %{low: 3, medium: 2, high: 1}

    impact_score = Map.get(impact_scores, suggestion.impact, 1)
    effort_score = Map.get(effort_scores, suggestion.effort, 1)
    confidence_score = suggestion.confidence

    # Weighted score: high impact + low effort + high confidence = high priority
    (impact_score * 0.4) + (effort_score * 0.3) + (confidence_score * 0.3)
  end
end
