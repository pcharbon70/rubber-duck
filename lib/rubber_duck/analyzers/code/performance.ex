defmodule RubberDuck.Analyzers.Code.Performance do
  @moduledoc """
  Performance-focused code analysis.
  
  Analyzes code for performance characteristics including time/space complexity,
  database operations, bottlenecks, and optimization opportunities.
  
  ## Supported Analysis Types
  
  - Time and space complexity estimation
  - Performance hotspot identification
  - Database query analysis (N+1 detection)
  - Memory usage estimation
  - Optimization recommendations
  - Algorithmic complexity analysis
  
  ## Integration
  
  This analyzer extracts performance-specific logic from CodeAnalysisSkill
  while maintaining the same analysis capabilities in a focused module.
  """
  
  @behaviour RubberDuck.Analyzer
  
  alias RubberDuck.Messages.Code.{Analyze, PerformanceAnalyze}
  
  @impl true
  def analyze(%Analyze{analysis_type: :performance} = msg, context) do
    content = get_content_from_context(msg, context)
    
    performance_analysis = %{
      time_complexity: estimate_time_complexity(content),
      space_complexity: estimate_space_complexity(content),
      cyclomatic_complexity: calculate_cyclomatic_complexity(content),
      memory_usage: estimate_memory_usage(content),
      database_operations: detect_database_queries(content),
      bottlenecks: identify_bottlenecks(content),
      hot_spots: identify_performance_hotspots(content),
      optimization_opportunities: suggest_performance_optimizations(content),
      algorithmic_complexity: analyze_algorithmic_complexity(content),
      optimization_potential: calculate_optimization_potential(content),
      analyzed_at: DateTime.utc_now(),
      file_path: msg.file_path
    }
    
    {:ok, performance_analysis}
  end
  
  def analyze(%Analyze{analysis_type: :comprehensive} = msg, context) do
    # For comprehensive analysis, return performance subset
    analyze(%{msg | analysis_type: :performance}, context)
  end
  
  def analyze(%PerformanceAnalyze{} = msg, _context) do
    performance_analysis = %{
      hot_spots: identify_performance_hotspots(msg.content),
      memory_usage: estimate_memory_usage(msg.content),
      complexity_analysis: analyze_algorithmic_complexity(msg.content),
      bottlenecks: identify_bottlenecks(msg.content),
      optimizations: suggest_optimizations(msg.content),
      cyclomatic_complexity: calculate_cyclomatic_complexity(msg.content),
      database_operations: detect_database_queries(msg.content),
      analyzed_at: DateTime.utc_now()
    }
    
    {:ok, performance_analysis}
  end
  
  def analyze(message, _context) do
    {:error, {:unsupported_message_type, message.__struct__}}
  end
  
  @impl true
  def supported_types do
    [Analyze, PerformanceAnalyze]
  end
  
  @impl true
  def priority, do: :normal
  
  @impl true  
  def timeout, do: 12_000
  
  @impl true
  def metadata do
    %{
      name: "Performance Analyzer",
      description: "Analyzes code performance characteristics and identifies optimization opportunities",
      version: "1.0.0",
      categories: [:performance, :code],
      tags: ["performance", "optimization", "complexity", "bottlenecks", "database"]
    }
  end
  
  # Core performance analysis functions extracted from CodeAnalysisSkill
  
  defp calculate_cyclomatic_complexity(content) when is_binary(content) do
    # Count decision points in the code
    conditionals = count_pattern(content, ~r/\b(if|unless|case|cond|when)\b/)
    loops = count_pattern(content, ~r/\b(for|while|Enum\.\w+|Stream\.\w+)\b/)

    1 + conditionals + loops
  end
  
  defp calculate_cyclomatic_complexity(_), do: 1

  defp estimate_memory_usage(content) when is_binary(content) do
    # Estimate based on data structure usage
    large_structures = count_pattern(content, ~r/\b(Map\.new|List\.duplicate|:ets\.new)\b/)
    recursion = count_pattern(content, ~r/\bdef\s+\w+/)

    %{
      estimated_mb: large_structures * 10 + recursion * 5,
      risk_level: if(large_structures + recursion > 5, do: :high, else: :low),
      large_structure_count: large_structures,
      recursive_function_count: recursion
    }
  end
  
  defp estimate_memory_usage(_), do: %{estimated_mb: 0, risk_level: :low}

  defp detect_database_queries(content) when is_binary(content) do
    queries = []

    queries =
      if String.contains?(content, "Repo.") do
        ecto_count = count_pattern(content, ~r/Repo\.\w+/)
        [%{type: :ecto, count: ecto_count, operations: extract_repo_operations(content)} | queries]
      else
        queries
      end

    # Check for raw SQL
    queries =
      if String.contains?(content, ["SQL", "sql", "query("]) do
        [%{type: :raw_sql, count: count_pattern(content, ~r/\b(SQL|sql|query\()/)} | queries]
      else
        queries
      end
    
    # Check for async queries
    queries =
      if String.contains?(content, "async_stream") do
        [%{type: :async_queries, count: count_pattern(content, ~r/async_stream/)} | queries]
      else
        queries
      end

    queries
  end
  
  defp detect_database_queries(_), do: []

  defp extract_repo_operations(content) do
    operations = []
    
    repo_patterns = [
      {"Repo.all", :read_many},
      {"Repo.get", :read_one},
      {"Repo.get!", :read_one_bang},
      {"Repo.insert", :create},
      {"Repo.update", :update},
      {"Repo.delete", :delete},
      {"Repo.preload", :preload}
    ]
    
    Enum.reduce(repo_patterns, operations, fn {pattern, type}, acc ->
      count = count_pattern(content, Regex.compile!(Regex.escape(pattern)))
      if count > 0 do
        [%{operation: type, count: count, pattern: pattern} | acc]
      else
        acc
      end
    end)
  end

  defp identify_bottlenecks(content) when is_binary(content) do
    bottlenecks = []

    bottlenecks =
      if String.contains?(content, "Enum.") && String.contains?(content, "|> Enum.") do
        [
          %{type: :multiple_iterations, severity: :medium, suggestion: "Consider using Stream or single pass"}
          | bottlenecks
        ]
      else
        bottlenecks
      end

    bottlenecks =
      if count_pattern(content, ~r/\bn\+1\b|N\+1/) > 0 do
        [%{type: :n_plus_one, severity: :high, suggestion: "Potential N+1 query pattern detected"} | bottlenecks]
      else
        bottlenecks
      end
    
    # Check for potential N+1 patterns in database calls
    bottlenecks =
      if String.contains?(content, ["Repo.all", "Repo.get"]) && String.contains?(content, ["Enum.map", "for"]) do
        [%{type: :potential_n_plus_one, severity: :high, suggestion: "Multiple database queries in loop"} | bottlenecks]
      else
        bottlenecks
      end
    
    # Check for large data operations without streaming
    bottlenecks =
      if String.contains?(content, "Enum.") and not String.contains?(content, "Stream.") do
        [%{type: :no_streaming, severity: :low, suggestion: "Large data operations without Stream module"} | bottlenecks]
      else
        bottlenecks
      end
    
    # Check for synchronous operations that could be async
    bottlenecks =
      if String.contains?(content, ["HTTPoison.get", "GenServer.call"]) && 
         not String.contains?(content, ["Task.async", "async_stream"]) do
        [%{type: :sync_operations, severity: :medium, suggestion: "Consider async operations for external calls"} | bottlenecks]
      else
        bottlenecks
      end

    bottlenecks
  end
  
  defp identify_bottlenecks(_), do: []

  defp suggest_performance_optimizations(content) when is_binary(content) do
    optimizations = []

    optimizations =
      if String.contains?(content, "length(") && String.contains?(content, "== 0") do
        [
          %{
            pattern: "length() == 0",
            replacement: "Enum.empty?()",
            impact: :low,
            reason: "Enum.empty?/1 is more efficient for checking empty collections"
          }
          | optimizations
        ]
      else
        optimizations
      end
    
    # Suggest caching for expensive operations
    optimizations =
      if String.contains?(content, ["DateTime.utc_now()", "System.system_time"]) do
        [
          %{
            pattern: "Repeated time calls",
            replacement: "Cache time value in variable",
            impact: :low,
            reason: "Avoid repeated system calls within same operation"
          }
          | optimizations
        ]
      else
        optimizations
      end
    
    # Suggest pattern matching over conditionals
    optimizations =
      if count_pattern(content, ~r/\bif\b.*\belse\b/) > 2 do
        [
          %{
            pattern: "Multiple if/else chains",
            replacement: "Pattern matching with case/when",
            impact: :medium,
            reason: "Pattern matching is more efficient and readable"
          }
          | optimizations
        ]
      else
        optimizations
      end

    optimizations
  end
  
  defp suggest_performance_optimizations(_), do: []

  defp identify_performance_hotspots(content) when is_binary(content) do
    hotspots = []

    # Check for nested loops
    nested_enum_pattern = String.contains?(content, ["for", "Enum.each"]) and
                         String.contains?(content, ["Enum.map", "Enum.filter"])
    
    hotspots =
      if nested_enum_pattern do
        [%{type: :nested_enumeration, severity: :high, description: "Nested enumerations detected", 
           suggestion: "Consider flattening or using comprehensions"} | hotspots]
      else
        hotspots
      end
    
    # Check for string concatenation in loops
    hotspots =
      if String.contains?(content, ["Enum.reduce", "for"]) && String.contains?(content, "<>") do
        [%{type: :string_concatenation_loop, severity: :medium, 
           description: "String concatenation in loop detected",
           suggestion: "Consider using IO lists or Enum.join/2"} | hotspots]
      else
        hotspots
      end
    
    # Check for large data structure creation
    hotspots =
      if String.contains?(content, ["List.duplicate(", "Stream.cycle("]) do
        [%{type: :large_data_creation, severity: :medium,
           description: "Large data structure creation detected",
           suggestion: "Consider lazy evaluation or streaming"} | hotspots]
      else
        hotspots
      end

    hotspots
  end

  defp identify_performance_hotspots(_), do: []

  defp analyze_algorithmic_complexity(content) when is_binary(content) do
    # Count nested loops more accurately by counting 'for' keywords
    for_count = count_pattern(content, ~r/\bfor\b/)
    
    # Estimate nesting based on indentation or multiple for statements
    nested_loops = if for_count > 3 do
      for_count - 1  # Approximate nesting level
    else
      length(Regex.scan(~r/for.*do.*for/s, content))
    end
    
    # Check for recursion patterns
    recursion = String.contains?(content, ["defp", "def"]) and
                Regex.match?(~r/def\w*\s+(\w+).*\1\(/s, content)

    complexity = cond do
      nested_loops >= 3 -> :exponential
      nested_loops >= 1 -> :quadratic
      recursion -> :logarithmic
      true -> :linear
    end
    
    %{
      complexity: complexity,
      nested_loop_count: nested_loops,
      has_recursion: recursion,
      estimated_big_o: estimate_big_o_notation(complexity, nested_loops)
    }
  end

  defp analyze_algorithmic_complexity(_) do
    %{complexity: :unknown, nested_loop_count: 0, has_recursion: false, estimated_big_o: "O(1)"}
  end
  
  defp estimate_big_o_notation(:exponential, loops) when loops > 2, do: "O(2^n)"
  defp estimate_big_o_notation(:quadratic, _), do: "O(n²)"
  defp estimate_big_o_notation(:logarithmic, _), do: "O(log n)"
  defp estimate_big_o_notation(:linear, _), do: "O(n)"
  defp estimate_big_o_notation(_, _), do: "O(1)"

  defp suggest_optimizations(content) when is_binary(content) do
    optimizations = []

    # Suggest Stream for large enumerations
    optimizations =
      if String.contains?(content, "Enum.") and not String.contains?(content, "Stream.") do
        ["Consider using Stream for large collections" | optimizations]
      else
        optimizations
      end

    # Suggest pattern matching over conditionals
    optimizations =
      if String.contains?(content, ["if", "else", "cond"]) do
        ["Consider pattern matching instead of conditionals" | optimizations]
      else
        optimizations
      end
    
    # Suggest preloading for database queries
    optimizations =
      if String.contains?(content, "Repo.") && not String.contains?(content, "preload") do
        ["Consider preloading associations to avoid N+1 queries" | optimizations]
      else
        optimizations
      end

    optimizations
  end

  defp suggest_optimizations(_), do: []

  # Helper functions for complexity and data analysis
  
  defp estimate_time_complexity(content) when is_binary(content) do
    complexity_analysis = analyze_algorithmic_complexity(content)
    complexity_analysis.complexity
  end
  
  defp estimate_time_complexity(_), do: :linear

  defp estimate_space_complexity(content) when is_binary(content) do
    memory_analysis = estimate_memory_usage(content)
    
    case memory_analysis.risk_level do
      :high -> :quadratic
      :medium -> :linear  
      :low -> :constant
    end
  end
  
  defp estimate_space_complexity(_), do: :constant

  defp calculate_optimization_potential(content) when is_binary(content) do
    # Return 0 for empty content
    if String.trim(content) == "" do
      0
    else
      potential = 0
      
      # Add potential based on complexity
      complexity_analysis = analyze_algorithmic_complexity(content)
      potential = potential + case complexity_analysis.complexity do
        :exponential -> 50
        :quadratic -> 30
        :logarithmic -> 10
        _ -> 5
      end
      
      # Add potential based on database operations
      db_queries = detect_database_queries(content)
      db_potential = Enum.reduce(db_queries, 0, fn query, acc -> acc + query.count * 8 end)
      potential = potential + min(db_potential, 30)
      
      # Add potential based on bottlenecks
      bottlenecks = identify_bottlenecks(content)
      bottleneck_potential = length(bottlenecks) * 18
      potential = potential + bottleneck_potential

      min(100, potential)
    end
  end
  
  defp calculate_optimization_potential(_), do: 0

  # Helper functions

  defp get_content_from_context(%{file_path: file_path}, context) do
    # Try to get content from context first, then read file
    case Map.get(context, :content) do
      nil -> read_file_content(file_path)
      content -> content
    end
  end
  
  defp read_file_content(file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end
end