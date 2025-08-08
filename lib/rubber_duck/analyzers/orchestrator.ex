defmodule RubberDuck.Analyzers.Orchestrator do
  @moduledoc """
  Orchestrates and coordinates multiple code analyzers for comprehensive analysis.

  The Orchestrator manages the execution of different analyzers (Security, Performance,
  Quality, Impact) and handles cross-analyzer communication, result aggregation,
  and intelligent workflow coordination.

  ## Features

  - Parallel and sequential analyzer execution
  - Cross-analyzer data sharing and insights
  - Intelligent analysis ordering based on dependencies
  - Result aggregation and correlation
  - Adaptive analysis depth based on initial findings
  - Caching and memoization of analysis results

  ## Analysis Strategies

  - **Quick**: Run only essential analyzers with shallow depth
  - **Standard**: Run all analyzers with moderate depth
  - **Deep**: Run all analyzers with deep analysis and cross-correlation
  - **Focused**: Run specific analyzers based on detected issues
  - **Adaptive**: Dynamically adjust analysis based on findings
  """

  require Logger

  alias RubberDuck.Messages.Code.Analyze
  alias RubberDuck.Analyzers.Code.{Security, Performance, Quality, Impact}

  @type analyzer :: :security | :performance | :quality | :impact
  @type strategy :: :quick | :standard | :deep | :focused | :adaptive
  @type priority :: :critical | :high | :medium | :low

  @type analysis_request :: %{
          file_path: String.t(),
          content: String.t() | nil,
          analyzers: [analyzer] | :all,
          strategy: strategy,
          context: map(),
          options: map()
        }

  @type analysis_result :: %{
          file_path: String.t(),
          timestamp: DateTime.t(),
          strategy: strategy,
          results: map(),
          insights: [insight],
          recommendations: [recommendation],
          overall_health: health_score,
          execution_time: integer()
        }

  @type insight :: %{
          type: atom(),
          severity: priority,
          message: String.t(),
          source_analyzers: [analyzer],
          confidence: float()
        }

  @type recommendation :: %{
          action: String.t(),
          priority: priority,
          effort: atom(),
          impact: atom(),
          analyzers: [analyzer]
        }

  @type health_score :: %{
          overall: float(),
          security: float(),
          performance: float(),
          quality: float(),
          maintainability: float()
        }

  # Analyzer dependencies and ordering
  @analyzer_dependencies %{
    impact: [:quality, :performance],
    performance: [:quality],
    security: [],
    quality: []
  }

  @doc """
  Orchestrate a comprehensive code analysis across multiple analyzers.

  ## Options

  - `:analyzers` - List of analyzers to run or `:all` (default: `:all`)
  - `:strategy` - Analysis strategy to use (default: `:standard`)
  - `:parallel` - Run analyzers in parallel when possible (default: true)
  - `:cache` - Use cached results if available (default: true)
  - `:timeout` - Maximum time for analysis in ms (default: 30000)
  """
  @spec orchestrate(analysis_request) :: {:ok, analysis_result} | {:error, term()}
  def orchestrate(request) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, plan} <- create_execution_plan(request),
         {:ok, results} <- execute_analysis_plan(plan, request),
         {:ok, insights} <- generate_cross_analyzer_insights(results),
         {:ok, recommendations} <- generate_recommendations(results, insights) do
      execution_time = System.monotonic_time(:millisecond) - start_time

      {:ok,
       %{
         file_path: request.file_path,
         timestamp: DateTime.utc_now(),
         strategy: request.strategy,
         results: results,
         insights: insights,
         recommendations: prioritize_recommendations(recommendations),
         overall_health: calculate_overall_health(results),
         execution_time: execution_time
       }}
    end
  end

  @doc """
  Run a specific analyzer with orchestrator enhancements.
  """
  @spec run_analyzer(analyzer, Analyze.t(), map()) :: {:ok, map()} | {:error, term()}
  def run_analyzer(analyzer, message, context) do
    enhanced_context = enhance_context_for_analyzer(analyzer, context)

    case analyzer do
      :security -> Security.analyze(message, enhanced_context)
      :performance -> Performance.analyze(message, enhanced_context)
      :quality -> Quality.analyze(message, enhanced_context)
      :impact -> Impact.analyze(message, enhanced_context)
      _ -> {:error, :unknown_analyzer}
    end
  end

  @doc """
  Perform adaptive analysis that adjusts based on initial findings.
  """
  @spec adaptive_analysis(analysis_request) :: {:ok, analysis_result} | {:error, term()}
  def adaptive_analysis(request) do
    # Start with quick analysis
    quick_request = %{request | strategy: :quick, analyzers: [:quality, :security]}

    case orchestrate(quick_request) do
      {:ok, initial_results} ->
        # Determine which additional analyzers to run based on findings
        additional_analyzers = determine_additional_analyzers(initial_results)

        if Enum.empty?(additional_analyzers) do
          {:ok, initial_results}
        else
          # Run deeper analysis on areas of concern
          deep_request = %{
            request
            | strategy: :deep,
              analyzers: additional_analyzers,
              context: Map.put(request.context, :initial_findings, initial_results)
          }

          case orchestrate(deep_request) do
            {:ok, deep_results} ->
              {:ok, merge_analysis_results(initial_results, deep_results)}

            error ->
              error
          end
        end

      error ->
        error
    end
  end

  # Private functions

  defp create_execution_plan(request) do
    analyzers = resolve_analyzers(request.analyzers)

    plan =
      case request.strategy do
        :quick ->
          %{
            phases: [
              %{analyzers: [:quality], parallel: false, depth: :shallow}
            ]
          }

        :standard ->
          analyzed =
            if request.analyzers == :all do
              [:quality, :security, :performance, :impact]
            else
              resolve_analyzers(request.analyzers)
            end

          # Split analyzers into phases based on dependencies
          phase1 = Enum.filter(analyzed, fn a -> a in [:quality, :security] end)
          phase2 = Enum.filter(analyzed, fn a -> a in [:performance, :impact] end)

          phases = []

          phases =
            if length(phase1) > 0,
              do: phases ++ [%{analyzers: phase1, parallel: true, depth: :moderate}],
              else: phases

          phases =
            if length(phase2) > 0,
              do: phases ++ [%{analyzers: phase2, parallel: true, depth: :moderate}],
              else: phases

          %{phases: phases}

        :deep ->
          %{
            phases: [
              %{analyzers: [:quality], parallel: false, depth: :deep},
              %{analyzers: [:security, :performance], parallel: true, depth: :deep},
              %{analyzers: [:impact], parallel: false, depth: :deep}
            ]
          }

        :focused ->
          create_focused_plan(analyzers, request.context)

        :adaptive ->
          %{
            phases: [
              %{analyzers: analyzers, parallel: false, depth: :moderate, adaptive: true}
            ]
          }
      end

    {:ok, plan}
  end

  defp execute_analysis_plan(plan, request) do
    results =
      Enum.reduce(plan.phases, %{}, fn phase, acc ->
        phase_results =
          if Map.get(phase, :parallel, false) do
            execute_parallel_phase(phase, request, acc)
          else
            execute_sequential_phase(phase, request, acc)
          end

        Map.merge(acc, phase_results)
      end)

    {:ok, results}
  end

  defp execute_parallel_phase(phase, request, previous_results) do
    tasks =
      Enum.map(phase.analyzers, fn analyzer ->
        Task.async(fn ->
          context = build_analyzer_context(request, previous_results, analyzer)
          message = build_analyze_message(request, analyzer, phase.depth)

          case run_analyzer(analyzer, message, context) do
            {:ok, result} ->
              {analyzer, result}

            {:error, reason} ->
              Logger.warning("Analyzer #{analyzer} failed: #{inspect(reason)}")
              {analyzer, %{error: reason}}
          end
        end)
      end)

    tasks
    |> Task.await_many(request.options[:timeout] || 30000)
    |> Map.new()
  end

  defp execute_sequential_phase(phase, request, previous_results) do
    Enum.reduce(phase.analyzers, %{}, fn analyzer, acc ->
      context = build_analyzer_context(request, Map.merge(previous_results, acc), analyzer)
      message = build_analyze_message(request, analyzer, phase.depth)

      result =
        case run_analyzer(analyzer, message, context) do
          {:ok, result} ->
            result

          {:error, reason} ->
            Logger.warning("Analyzer #{analyzer} failed: #{inspect(reason)}")
            %{error: reason}
        end

      Map.put(acc, analyzer, result)
    end)
  end

  defp generate_cross_analyzer_insights(results) do
    insights = []

    # Security + Performance correlation
    insights =
      insights ++
        correlate_security_performance(
          results[:security],
          results[:performance]
        )

    # Quality + Impact correlation
    insights =
      insights ++
        correlate_quality_impact(
          results[:quality],
          results[:impact]
        )

    # Performance + Impact correlation
    insights =
      insights ++
        correlate_performance_impact(
          results[:performance],
          results[:impact]
        )

    # Overall code health insights
    insights = insights ++ generate_health_insights(results)

    {:ok, insights}
  end

  defp correlate_security_performance(security, performance)
       when is_map(security) and is_map(performance) do
    insights = []

    # Check if security measures impact performance
    if length(security[:vulnerabilities] || []) > 0 and performance[:optimization_potential] > 0.3 do
      insights ++
        [
          %{
            type: :security_performance_tradeoff,
            severity: :medium,
            message:
              "Security vulnerabilities detected alongside performance issues. Fix security first.",
            source_analyzers: [:security, :performance],
            confidence: 0.8
          }
        ]
    else
      insights
    end
  end

  defp correlate_security_performance(_, _), do: []

  defp correlate_quality_impact(quality, impact) when is_map(quality) and is_map(impact) do
    insights = []

    # High complexity changes with high impact
    if quality[:metrics][:complexity] > 10 and impact[:severity] in [:high, :critical] do
      insights ++
        [
          %{
            type: :complex_high_impact_change,
            severity: :high,
            message:
              "High complexity code with significant impact. Consider breaking into smaller changes.",
            source_analyzers: [:quality, :impact],
            confidence: 0.9
          }
        ]
    else
      insights
    end
  end

  defp correlate_quality_impact(_, _), do: []

  defp correlate_performance_impact(performance, impact)
       when is_map(performance) and is_map(impact) do
    insights = []

    # Performance bottlenecks in high-impact areas
    if length(performance[:bottlenecks] || []) > 0 and
         impact[:scope] in [:system_wide, :module_wide] do
      insights ++
        [
          %{
            type: :critical_performance_bottleneck,
            severity: :critical,
            message:
              "Performance bottlenecks in high-impact code paths require immediate attention.",
            source_analyzers: [:performance, :impact],
            confidence: 0.95
          }
        ]
    else
      insights
    end
  end

  defp correlate_performance_impact(_, _), do: []

  defp generate_health_insights(results) do
    insights = []

    # Calculate combined metrics
    security_issues = length(results[:security][:vulnerabilities] || [])
    quality_score = results[:quality][:quality_score] || 0.5
    performance_score = 1.0 - (results[:performance][:optimization_potential] || 0)

    cond do
      security_issues > 5 and quality_score < 0.3 ->
        insights ++
          [
            %{
              type: :critical_code_health,
              severity: :critical,
              message:
                "Code health is critical: multiple security issues and poor quality metrics.",
              source_analyzers: [:security, :quality],
              confidence: 1.0
            }
          ]

      quality_score < 0.4 and performance_score < 0.5 ->
        insights ++
          [
            %{
              type: :poor_code_health,
              severity: :high,
              message:
                "Poor code health: low quality and performance scores indicate need for refactoring.",
              source_analyzers: [:quality, :performance],
              confidence: 0.85
            }
          ]

      quality_score > 0.8 and security_issues == 0 and performance_score > 0.8 ->
        insights ++
          [
            %{
              type: :excellent_code_health,
              severity: :low,
              message: "Excellent code health: high quality, secure, and performant.",
              source_analyzers: [:quality, :security, :performance],
              confidence: 0.9
            }
          ]

      true ->
        insights
    end
  end

  defp generate_recommendations(results, insights) do
    recommendations = []

    # Generate recommendations from individual analyzer results
    recommendations = recommendations ++ generate_security_recommendations(results[:security])

    recommendations =
      recommendations ++ generate_performance_recommendations(results[:performance])

    recommendations = recommendations ++ generate_quality_recommendations(results[:quality])
    recommendations = recommendations ++ generate_impact_recommendations(results[:impact])

    # Generate recommendations from insights
    recommendations = recommendations ++ generate_insight_recommendations(insights)

    # Deduplicate and merge similar recommendations
    recommendations = deduplicate_recommendations(recommendations)

    {:ok, recommendations}
  end

  defp generate_security_recommendations(nil), do: []

  defp generate_security_recommendations(security) do
    if length(security[:vulnerabilities] || []) > 0 do
      [
        %{
          action: "Fix #{length(security.vulnerabilities)} security vulnerabilities",
          priority: :critical,
          effort: :moderate,
          impact: :high,
          analyzers: [:security]
        }
      ]
    else
      []
    end
  end

  defp generate_performance_recommendations(nil), do: []

  defp generate_performance_recommendations(performance) do
    recommendations = []

    if performance[:optimization_potential] > 0.5 do
      recommendations ++
        [
          %{
            action:
              "Optimize performance bottlenecks for #{round(performance.optimization_potential * 100)}% improvement",
            priority: :high,
            effort: :moderate,
            impact: :high,
            analyzers: [:performance]
          }
        ]
    else
      recommendations
    end
  end

  defp generate_quality_recommendations(nil), do: []

  defp generate_quality_recommendations(quality) do
    recommendations = []

    if quality[:quality_score] < 0.5 do
      recommendations ++
        [
          %{
            action:
              "Improve code quality (current score: #{round(quality.quality_score * 100)}%)",
            priority: :medium,
            effort: :high,
            impact: :medium,
            analyzers: [:quality]
          }
        ]
    else
      recommendations
    end
  end

  defp generate_impact_recommendations(nil), do: []

  defp generate_impact_recommendations(impact) do
    recommendations = []

    if impact[:risk_assessment][:level] in [:high, :critical] do
      recommendations ++
        [
          %{
            action: "Review high-risk changes and add tests before deployment",
            priority: :critical,
            effort: :low,
            impact: :high,
            analyzers: [:impact]
          }
        ]
    else
      recommendations
    end
  end

  defp generate_insight_recommendations(insights) do
    Enum.flat_map(insights, fn insight ->
      case insight.type do
        :critical_code_health ->
          [
            %{
              action: "Initiate immediate code health improvement initiative",
              priority: :critical,
              effort: :high,
              impact: :high,
              analyzers: insight.source_analyzers
            }
          ]

        :complex_high_impact_change ->
          [
            %{
              action: "Break complex changes into smaller, manageable pieces",
              priority: :high,
              effort: :moderate,
              impact: :high,
              analyzers: insight.source_analyzers
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp prioritize_recommendations(recommendations) do
    recommendations
    |> Enum.sort_by(fn rec ->
      priority_score =
        case rec.priority do
          :critical -> 0
          :high -> 1
          :medium -> 2
          :low -> 3
        end

      impact_score =
        case rec.impact do
          :high -> 0
          :medium -> 1
          :low -> 2
        end

      {priority_score, impact_score}
    end)
    # Limit to top 10 recommendations
    |> Enum.take(10)
  end

  defp calculate_overall_health(results) do
    # Extract scores from results
    security_score = calculate_security_score(results[:security])
    performance_score = calculate_performance_score(results[:performance])
    quality_score = results[:quality][:quality_score] || 0.5
    maintainability_score = results[:quality][:maintainability_score] || 0.5

    # Calculate weighted overall score
    overall =
      security_score * 0.3 +
        performance_score * 0.2 +
        quality_score * 0.3 +
        maintainability_score * 0.2

    %{
      overall: overall,
      security: security_score,
      performance: performance_score,
      quality: quality_score,
      maintainability: maintainability_score
    }
  end

  defp calculate_security_score(nil), do: 0.5

  defp calculate_security_score(security) do
    vulnerabilities = length(security[:vulnerabilities] || [])

    cond do
      vulnerabilities == 0 -> 1.0
      vulnerabilities <= 2 -> 0.7
      vulnerabilities <= 5 -> 0.4
      true -> 0.1
    end
  end

  defp calculate_performance_score(nil), do: 0.5

  defp calculate_performance_score(performance) do
    # optimization_potential is 0-100, convert to 0-1 scale
    # Higher optimization potential = lower performance score
    optimization_potential = (performance[:optimization_potential] || 0) / 100.0
    1.0 - optimization_potential
  end

  defp resolve_analyzers(:all), do: [:security, :performance, :quality, :impact]
  defp resolve_analyzers(analyzers) when is_list(analyzers), do: analyzers

  defp build_analyzer_context(request, previous_results, analyzer) do
    base_context = request.context || %{}

    # Add previous results that this analyzer depends on
    dependencies = @analyzer_dependencies[analyzer] || []

    dependency_context =
      dependencies
      |> Enum.reduce(%{}, fn dep, acc ->
        if previous_results[dep] do
          Map.put(acc, :"#{dep}_results", previous_results[dep])
        else
          acc
        end
      end)

    Map.merge(base_context, dependency_context)
  end

  defp build_analyze_message(request, analyzer, depth) do
    %Analyze{
      file_path: request.file_path,
      analysis_type: analyzer,
      depth: depth || :moderate,
      auto_fix: false
    }
  end

  defp enhance_context_for_analyzer(analyzer, context) do
    # Add analyzer-specific context enhancements
    case analyzer do
      :impact ->
        # Impact analyzer benefits from knowing about other analysis results
        Map.put(context, :comprehensive_mode, true)

      :performance ->
        # Performance analyzer can use quality metrics for better analysis
        Map.put(context, :include_complexity_analysis, true)

      _ ->
        context
    end
  end

  defp determine_additional_analyzers(initial_results) do
    additional = []

    # If security issues found, run performance analysis
    if length(initial_results.results[:security][:vulnerabilities] || []) > 0 do
      additional ++ [:performance, :impact]
    else
      additional
    end
  end

  defp merge_analysis_results(initial, deep) do
    %{
      initial
      | results: Map.merge(initial.results, deep.results),
        insights: initial.insights ++ deep.insights,
        recommendations:
          deduplicate_recommendations(initial.recommendations ++ deep.recommendations),
        overall_health: calculate_overall_health(Map.merge(initial.results, deep.results))
    }
  end

  defp create_focused_plan(analyzers, context) do
    # Create a focused plan based on specific needs
    focus = context[:focus] || :general

    case focus do
      :security_audit ->
        %{
          phases: [
            %{analyzers: [:security], parallel: false, depth: :deep},
            %{analyzers: [:impact], parallel: false, depth: :moderate}
          ]
        }

      :performance_optimization ->
        %{
          phases: [
            %{analyzers: [:performance], parallel: false, depth: :deep},
            %{analyzers: [:quality], parallel: false, depth: :moderate}
          ]
        }

      :refactoring ->
        %{
          phases: [
            %{analyzers: [:quality], parallel: false, depth: :deep},
            %{analyzers: [:impact, :performance], parallel: true, depth: :moderate}
          ]
        }

      _ ->
        %{
          phases: [
            %{analyzers: analyzers, parallel: true, depth: :moderate}
          ]
        }
    end
  end

  defp deduplicate_recommendations(recommendations) do
    recommendations
    |> Enum.uniq_by(& &1.action)
    |> Enum.group_by(& &1.action)
    |> Enum.map(fn {_action, recs} ->
      # Merge duplicate recommendations, keeping highest priority
      Enum.reduce(recs, fn rec, acc ->
        %{
          acc
          | priority: highest_priority(acc.priority, rec.priority),
            analyzers: Enum.uniq(acc.analyzers ++ rec.analyzers)
        }
      end)
    end)
  end

  defp highest_priority(p1, p2) do
    priorities = [:critical, :high, :medium, :low]
    p1_index = Enum.find_index(priorities, &(&1 == p1))
    p2_index = Enum.find_index(priorities, &(&1 == p2))

    if p1_index <= p2_index, do: p1, else: p2
  end
end
