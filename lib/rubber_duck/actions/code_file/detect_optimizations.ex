defmodule RubberDuck.Actions.CodeFile.DetectOptimizations do
  @moduledoc """
  Action to detect performance optimization opportunities in code files.
  """

  use Jido.Action,
    name: "detect_optimizations",
    description: "Detects performance optimizations and provides recommendations",
    schema: [
      file_id: [type: :string, required: true],
      content: [type: :string, required: true],
      language: [type: :string, default: "elixir"],
      optimization_level: [type: :atom, default: :balanced, values: [:conservative, :balanced, :aggressive]]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, analysis} <- analyze_performance_patterns(params),
         {:ok, optimizations} <- detect_optimization_opportunities(analysis, params),
         {:ok, benchmarks} <- estimate_performance_gains(optimizations),
         {:ok, recommendations} <- generate_recommendations(optimizations, benchmarks, params) do

      {:ok, %{
        optimizations: optimizations,
        performance_metrics: analysis.metrics,
        estimated_gains: benchmarks,
        recommendations: recommendations,
        optimization_score: calculate_optimization_score(optimizations, benchmarks),
        priority_order: prioritize_optimizations(optimizations, benchmarks)
      }}
    end
  end

  defp analyze_performance_patterns(params) do
    content = params.content

    analysis = %{
      metrics: %{
        algorithm_complexity: analyze_algorithm_complexity(content),
        memory_patterns: analyze_memory_patterns(content),
        io_operations: count_io_operations(content),
        database_queries: count_database_queries(content),
        loop_depth: analyze_loop_depth(content)
      },
      patterns: detect_code_patterns(content),
      hotspots: identify_performance_hotspots(content)
    }

    {:ok, analysis}
  end

  defp detect_optimization_opportunities(_analysis, params) do
    optimizations = []

    # Check for common optimization opportunities
    optimizations = optimizations ++ detect_enum_optimizations(params.content)
    optimizations = optimizations ++ detect_pattern_matching_optimizations(params.content)
    optimizations = optimizations ++ detect_memory_optimizations(params.content)
    optimizations = optimizations ++ detect_query_optimizations(params.content)
    optimizations = optimizations ++ detect_concurrency_optimizations(params.content)

    # Filter based on optimization level
    filtered = filter_by_optimization_level(optimizations, params.optimization_level)

    {:ok, filtered}
  end

  defp estimate_performance_gains(optimizations) do
    benchmarks = Enum.map(optimizations, fn opt ->
      %{
        optimization_id: opt.id,
        estimated_speedup: estimate_speedup(opt),
        memory_reduction: estimate_memory_reduction(opt),
        complexity_improvement: estimate_complexity_improvement(opt),
        confidence: calculate_confidence(opt)
      }
    end)

    {:ok, benchmarks}
  end

  defp generate_recommendations(optimizations, benchmarks, _params) do
    recommendations = optimizations
      |> Enum.zip(benchmarks)
      |> Enum.map(fn {opt, bench} ->
        %{
          title: opt.title,
          description: opt.description,
          code_before: opt.current_code,
          code_after: opt.optimized_code,
          estimated_improvement: format_improvement(bench),
          implementation_effort: opt.effort,
          risk_level: opt.risk,
          auto_applicable: opt.auto_applicable
        }
      end)

    {:ok, recommendations}
  end

  defp analyze_algorithm_complexity(content) do
    # Analyze Big-O complexity patterns
    nested_loops = count_nested_loops(content)
    recursive_calls = count_recursive_patterns(content)

    cond do
      nested_loops >= 3 -> :exponential
      nested_loops == 2 -> :quadratic
      recursive_calls > 0 -> :logarithmic
      nested_loops == 1 -> :linear
      true -> :constant
    end
  end

  defp analyze_memory_patterns(content) do
    %{
      list_operations: count_list_operations(content),
      map_operations: count_map_operations(content),
      string_concatenations: count_string_concatenations(content),
      large_data_structures: detect_large_data_structures(content)
    }
  end

  defp count_io_operations(content) do
    io_patterns = ["IO.", "File.", "Logger.", "puts", "inspect"]

    Enum.reduce(io_patterns, 0, fn pattern, acc ->
      acc + count_pattern_occurrences(content, pattern)
    end)
  end

  defp count_database_queries(content) do
    query_patterns = ["Repo.", "from(", "Ecto.Query", "select:", "where:"]

    Enum.reduce(query_patterns, 0, fn pattern, acc ->
      acc + count_pattern_occurrences(content, pattern)
    end)
  end

  defp analyze_loop_depth(content) do
    lines = String.split(content, "\n")
    max_depth = 0

    lines
    |> Enum.reduce({0, max_depth}, fn line, {current_depth, max} ->
      new_depth = if String.contains?(line, "Enum.") or String.contains?(line, "for ") do
        current_depth + 1
      else
        max(0, current_depth - count_block_ends(line))
      end

      {new_depth, max(max, new_depth)}
    end)
    |> elem(1)
  end

  defp detect_code_patterns(content) do
    %{
      has_enum_chains: String.contains?(content, "|> Enum."),
      has_list_comprehensions: String.contains?(content, "for "),
      has_with_statements: String.contains?(content, "with "),
      has_pattern_matching: Regex.match?(~r/case .+ do/, content),
      has_tail_recursion: detect_tail_recursion(content)
    }
  end

  defp identify_performance_hotspots(content) do
    # Identify functions that are likely performance bottlenecks
    functions = extract_functions(content)

    Enum.filter(functions, fn func ->
      is_performance_hotspot?(func.body)
    end)
  end

  defp detect_enum_optimizations(content) do
    optimizations = []

    # Detect Enum chains that could use Stream
    optimizations = if Regex.match?(~r/Enum\.\w+.*\|>\s*Enum\.\w+/, content) do
      [%{
        id: "enum_to_stream",
        type: :algorithm,
        title: "Replace Enum chains with Stream",
        description: "Use Stream for lazy evaluation in chained operations",
        current_code: extract_enum_chains(content),
        optimized_code: convert_enum_to_stream(extract_enum_chains(content)),
        effort: :low,
        risk: :low,
        auto_applicable: true
      } | optimizations]
    else
      optimizations
    end

    # Detect multiple passes over same collection
    optimizations = if detect_multiple_enum_passes(content) do
      [%{
        id: "combine_enum_passes",
        type: :algorithm,
        title: "Combine multiple Enum operations",
        description: "Reduce iterations by combining operations",
        current_code: "Multiple Enum operations detected",
        optimized_code: "Combined operation suggested",
        effort: :medium,
        risk: :low,
        auto_applicable: false
      } | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp detect_pattern_matching_optimizations(content) do
    optimizations = []

    # Detect if-else chains that could be pattern matching
    optimizations = if Regex.match?(~r/if .+ do.*else.*end/s, content) do
      [%{
        id: "if_to_pattern_match",
        type: :code_quality,
        title: "Replace if-else with pattern matching",
        description: "Use pattern matching for cleaner, faster code",
        current_code: "if-else chain detected",
        optimized_code: "case or function heads suggested",
        effort: :low,
        risk: :low,
        auto_applicable: false
      } | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp detect_memory_optimizations(content) do
    optimizations = []

    # Detect string concatenation in loops
    optimizations = if Regex.match?(~r/Enum\..+<>/, content) do
      [%{
        id: "string_concat_optimization",
        type: :memory,
        title: "Optimize string concatenation",
        description: "Use iolist instead of string concatenation in loops",
        current_code: "String concatenation in loop",
        optimized_code: "Use iolist pattern",
        effort: :medium,
        risk: :low,
        auto_applicable: false
      } | optimizations]
    else
      optimizations
    end

    # Detect large list operations
    optimizations = if detect_large_list_operations(content) do
      [%{
        id: "list_optimization",
        type: :memory,
        title: "Optimize list operations",
        description: "Consider using :ets or Stream for large lists",
        current_code: "Large list operations detected",
        optimized_code: "Alternative data structure suggested",
        effort: :high,
        risk: :medium,
        auto_applicable: false
      } | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp detect_query_optimizations(content) do
    optimizations = []

    # Detect N+1 query patterns
    optimizations = if detect_n_plus_one_pattern(content) do
      [%{
        id: "n_plus_one",
        type: :database,
        title: "Fix N+1 query problem",
        description: "Use preloading to reduce database queries",
        current_code: "Potential N+1 pattern",
        optimized_code: "Use Repo.preload or join",
        effort: :medium,
        risk: :low,
        auto_applicable: false
      } | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp detect_concurrency_optimizations(content) do
    optimizations = []

    # Detect synchronous operations that could be concurrent
    optimizations = if detect_parallelizable_operations(content) do
      [%{
        id: "add_concurrency",
        type: :concurrency,
        title: "Add concurrent processing",
        description: "Use Task.async/await for parallel operations",
        current_code: "Sequential operations detected",
        optimized_code: "Concurrent processing suggested",
        effort: :medium,
        risk: :medium,
        auto_applicable: false
      } | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp filter_by_optimization_level(optimizations, level) do
    case level do
      :conservative ->
        Enum.filter(optimizations, fn opt -> opt.risk == :low end)

      :aggressive ->
        optimizations

      :balanced ->
        Enum.filter(optimizations, fn opt -> opt.risk in [:low, :medium] end)
    end
  end

  defp estimate_speedup(optimization) do
    case optimization.type do
      :algorithm -> 2.0
      :database -> 5.0
      :memory -> 1.5
      :concurrency -> 3.0
      _ -> 1.2
    end
  end

  defp estimate_memory_reduction(optimization) do
    case optimization.type do
      :memory -> 0.5
      :algorithm -> 0.2
      _ -> 0.1
    end
  end

  defp estimate_complexity_improvement(optimization) do
    case optimization.type do
      :algorithm -> :significant
      :database -> :moderate
      _ -> :minor
    end
  end

  defp calculate_confidence(optimization) do
    case optimization.auto_applicable do
      true -> 0.9
      false -> 0.7
    end
  end

  defp format_improvement(benchmark) do
    "#{round(benchmark.estimated_speedup * 100)}% faster, " <>
    "#{round(benchmark.memory_reduction * 100)}% less memory"
  end

  defp calculate_optimization_score(optimizations, benchmarks) do
    if Enum.empty?(optimizations) do
      1.0
    else
      total_speedup = Enum.reduce(benchmarks, 0, fn b, acc ->
        acc + b.estimated_speedup
      end)

      min(1.0, total_speedup / (length(optimizations) * 2))
    end
  end

  defp prioritize_optimizations(optimizations, benchmarks) do
    optimizations
    |> Enum.zip(benchmarks)
    |> Enum.sort_by(fn {opt, bench} ->
      score = bench.estimated_speedup * 10
      score = score + (1.0 - risk_to_number(opt.risk)) * 5
      score = score + (1.0 - effort_to_number(opt.effort)) * 3
      -score
    end)
    |> Enum.map(fn {opt, _} -> opt.id end)
  end

  defp risk_to_number(:low), do: 0.2
  defp risk_to_number(:medium), do: 0.5
  defp risk_to_number(:high), do: 0.8

  defp effort_to_number(:low), do: 0.2
  defp effort_to_number(:medium), do: 0.5
  defp effort_to_number(:high), do: 0.8

  # Helper functions

  defp count_pattern_occurrences(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  defp count_nested_loops(content) do
    # Simplified nested loop detection
    lines = String.split(content, "\n")

    lines
    |> Enum.reduce({0, 0}, fn line, {current, max_n} ->
      new_current = if String.contains?(line, "Enum.") or String.contains?(line, "for ") do
        current + 1
      else
        current
      end

      new_current = if String.contains?(line, "end") do
        max(0, new_current - 1)
      else
        new_current
      end

      {new_current, max(max_n, new_current)}
    end)
    |> elem(1)
  end

  defp count_recursive_patterns(content) do
    functions = extract_functions(content)

    Enum.count(functions, fn func ->
      String.contains?(func.body, func.name <> "(")
    end)
  end

  defp count_list_operations(content) do
    list_ops = ["++", "[", "|", "List."]
    Enum.reduce(list_ops, 0, fn op, acc ->
      acc + count_pattern_occurrences(content, op)
    end)
  end

  defp count_map_operations(content) do
    map_ops = ["%{", "Map.", "put_in", "get_in", "update_in"]
    Enum.reduce(map_ops, 0, fn op, acc ->
      acc + count_pattern_occurrences(content, op)
    end)
  end

  defp count_string_concatenations(content) do
    count_pattern_occurrences(content, "<>")
  end

  defp detect_large_data_structures(content) do
    # Detect indicators of large data structures
    String.contains?(content, "Enum.take") or
    String.contains?(content, "Stream.") or
    String.contains?(content, ":ets")
  end

  defp count_block_ends(line) do
    line
    |> String.graphemes()
    |> Enum.count(fn char -> char == "end" end)
  end

  defp detect_tail_recursion(content) do
    functions = extract_functions(content)

    Enum.any?(functions, fn func ->
      # Check if function calls itself as last operation
      lines = String.split(func.body, "\n")
      last_line = List.last(lines) || ""
      String.contains?(last_line, func.name <> "(")
    end)
  end

  defp extract_functions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+(\w+).*?do(.*?)end/s, &1))
    |> Enum.map(fn [_, name, body] ->
      %{name: name, body: body}
    end)
  end

  defp is_performance_hotspot?(function_body) do
    String.contains?(function_body, "Enum.") or
    String.contains?(function_body, "Repo.") or
    String.contains?(function_body, "for ") or
    count_pattern_occurrences(function_body, "|>") > 3
  end

  defp extract_enum_chains(content) do
    case Regex.run(~r/(Enum\.\w+.*(?:\|>\s*Enum\.\w+)+)/, content) do
      [_, chain] -> chain
      _ -> ""
    end
  end

  defp convert_enum_to_stream(enum_chain) do
    String.replace(enum_chain, "Enum.", "Stream.")
  end

  defp detect_multiple_enum_passes(content) do
    # Detect if the same variable is processed by Enum multiple times
    Regex.match?(~r/(\w+)\s*\|>\s*Enum\..*\n.*\1\s*\|>\s*Enum\./, content)
  end

  defp detect_large_list_operations(content) do
    String.contains?(content, "Enum.map") and
    (String.contains?(content, "large") or String.contains?(content, "all"))
  end

  defp detect_n_plus_one_pattern(content) do
    String.contains?(content, "Enum.map") and
    String.contains?(content, "Repo.")
  end

  defp detect_parallelizable_operations(content) do
    String.contains?(content, "Enum.map") and
    not String.contains?(content, "Task.")
  end
end
