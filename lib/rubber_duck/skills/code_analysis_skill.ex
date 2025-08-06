defmodule RubberDuck.Skills.CodeAnalysisSkill do
  @moduledoc """
  Skill for comprehensive code analysis capabilities.

  This skill provides reusable code analysis functionality that can be
  composed with agents to enable autonomous code quality management.
  """

  use Jido.Skill,
    name: "code_analysis",
    description: "Provides code analysis and quality assessment capabilities",
    category: "development",
    tags: ["code", "analysis", "quality", "metrics"],
    vsn: "1.0.0",
    opts_key: :code_analysis,
    signals: [
      input: [
        "code.file.created",
        "code.file.modified",
        "code.analysis.requested"
      ],
      output: [
        "code.analysis.complete",
        "code.quality.alert",
        "code.optimization.found"
      ]
    ],
    config: [
      analysis_depth: [
        type: :atom,
        default: :normal,
        doc: "Depth of analysis to perform",
        values: [:shallow, :normal, :deep]
      ],
      auto_fix: [
        type: :boolean,
        default: false,
        doc: "Automatically apply safe fixes"
      ],
      quality_threshold: [
        type: :float,
        default: 0.7,
        doc: "Minimum quality score threshold"
      ]
    ]

  alias RubberDuck.Actions.CodeFile

  @doc """
  Returns the initial state for the skill.
  """
  def initial_state do
    %{
      files_analyzed: 0,
      total_issues_found: 0,
      total_fixes_applied: 0,
      quality_scores: [],
      analysis_cache: %{},
      last_analysis_at: nil
    }
  end

  @doc """
  Defines routing rules for handling signals.
  """
  def router do
    [
      # High priority: Handle file creation
      %{
        path: "code.file.created",
        instruction: %{
          action: CodeFile.AnalyzeChanges,
          params_transform: &transform_creation_params/1
        },
        priority: 100
      },

      # Medium priority: Handle file modifications
      %{
        path: "code.file.modified",
        instruction: %{
          action: CodeFile.AnalyzeChanges,
          params_transform: &transform_modification_params/1
        },
        priority: 50,
        conditions: [
          &should_analyze_modification?/1
        ]
      },

      # Normal priority: Handle analysis requests
      %{
        path: "code.analysis.requested",
        instruction: %{
          workflow: :comprehensive_analysis
        },
        priority: 10
      }
    ]
  end

  @doc """
  Defines workflows for complex operations.
  """
  def workflows do
    %{
      comprehensive_analysis: [
        %{
          step: :analyze_changes,
          action: CodeFile.AnalyzeChanges,
          on_success: :next,
          on_failure: :abort
        },
        %{
          step: :assess_quality,
          action: CodeFile.AssessQuality,
          on_success: :next,
          on_failure: :continue
        },
        %{
          step: :detect_optimizations,
          action: CodeFile.DetectOptimizations,
          on_success: :next,
          on_failure: :continue
        },
        %{
          step: :analyze_dependencies,
          action: CodeFile.AnalyzeDependencies,
          on_success: :next,
          on_failure: :continue
        },
        %{
          step: :generate_insights,
          action: CodeFile.GenerateInsights,
          on_success: :complete,
          on_failure: :continue
        }
      ],

      auto_fix_workflow: [
        %{
          step: :identify_fixes,
          action: CodeFile.AnalyzeChanges,
          output_key: :issues
        },
        %{
          step: :apply_fixes,
          action: CodeFile.ApplyFixes,
          input_key: :issues,
          conditions: [&safe_to_auto_fix?/1]
        }
      ]
    }
  end

  @doc """
  Handles state updates after action execution.
  """
  def handle_result({:ok, result}, state, %{action: action}) do
    updated_state = case action do
      CodeFile.AnalyzeChanges ->
        update_analysis_stats(state, result)

      CodeFile.AssessQuality ->
        update_quality_metrics(state, result)

      CodeFile.ApplyFixes ->
        update_fix_stats(state, result)

      _ ->
        state
    end

    # Check for quality alerts
    if should_emit_quality_alert?(result, state) do
      emit_quality_alert(result)
    end

    {:ok, updated_state}
  end

  def handle_result({:error, _reason}, state, _context) do
    # Log error but don't fail the skill
    {:ok, state}
  end

  @doc """
  Provides directives for runtime behavior modification.
  """
  def directives do
    [
      %{
        name: :increase_analysis_depth,
        condition: &high_error_rate?/1,
        action: fn state ->
          Map.put(state, :analysis_depth, :deep)
        end
      },

      %{
        name: :enable_auto_fix,
        condition: &stable_quality?/1,
        action: fn state ->
          Map.put(state, :auto_fix_enabled, true)
        end
      },

      %{
        name: :cache_analysis,
        condition: &frequent_analysis?/1,
        action: fn state ->
          Map.put(state, :cache_enabled, true)
        end
      }
    ]
  end

  # Transform functions for routing

  defp transform_creation_params(signal) do
    %{
      file_id: signal.data.file_id,
      content: signal.data.content,
      analyze_depth: :normal
    }
  end

  defp transform_modification_params(signal) do
    %{
      file_id: signal.data.file_id,
      content: signal.data.new_content,
      previous_content: signal.data.old_content,
      analyze_depth: determine_analysis_depth(signal)
    }
  end

  # Condition functions

  defp should_analyze_modification?(signal) do
    # Skip trivial changes
    change_size = calculate_change_size(signal.data)
    change_size > 5
  end

  defp safe_to_auto_fix?(context) do
    issues = context.data.issues || []

    # Only auto-fix low-risk issues
    Enum.all?(issues, fn issue ->
      issue.risk_level in [:low, :minimal] and
      issue.auto_applicable == true
    end)
  end

  defp high_error_rate?(state) do
    if state.files_analyzed > 10 do
      error_rate = state.total_issues_found / state.files_analyzed
      error_rate > 5
    else
      false
    end
  end

  defp stable_quality?(state) do
    if length(state.quality_scores) > 5 do
      recent_scores = Enum.take(state.quality_scores, -5)
      avg_score = Enum.sum(recent_scores) / length(recent_scores)
      avg_score > 0.8
    else
      false
    end
  end

  defp frequent_analysis?(state) do
    state.files_analyzed > 100
  end

  # State update functions

  defp update_analysis_stats(state, result) do
    state
    |> Map.update(:files_analyzed, 1, &(&1 + 1))
    |> Map.update(:total_issues_found, length(result.issues || []),
                   &(&1 + length(result.issues || [])))
    |> Map.put(:last_analysis_at, DateTime.utc_now())
    |> cache_analysis_result(result)
  end

  defp update_quality_metrics(state, result) do
    state
    |> Map.update(:quality_scores, [result.quality_score],
                   &([result.quality_score | &1] |> Enum.take(100)))
  end

  defp update_fix_stats(state, result) do
    state
    |> Map.update(:total_fixes_applied, length(result.applied_fixes || []),
                   &(&1 + length(result.applied_fixes || [])))
  end

  defp cache_analysis_result(state, result) do
    if result[:file_id] do
      cache_entry = %{
        result: result,
        cached_at: DateTime.utc_now()
      }

      put_in(state, [:analysis_cache, result.file_id], cache_entry)
    else
      state
    end
  end

  # Alert functions

  defp should_emit_quality_alert?(result, state) do
    quality_score = result[:quality_score] || 1.0
    threshold = state[:quality_threshold] || 0.7

    quality_score < threshold
  end

  defp emit_quality_alert(result) do
    RubberDuck.Signal.emit("code.quality.alert", %{
      file_id: result[:file_id],
      quality_score: result[:quality_score],
      issues: result[:issues] || [],
      severity: determine_alert_severity(result)
    })
  end

  defp determine_alert_severity(result) do
    score = result[:quality_score] || 1.0

    cond do
      score < 0.3 -> :critical
      score < 0.5 -> :high
      score < 0.7 -> :medium
      true -> :low
    end
  end

  # Utility functions

  defp calculate_change_size(data) do
    old_lines = String.split(data.old_content || "", "\n") |> length()
    new_lines = String.split(data.new_content || "", "\n") |> length()

    abs(new_lines - old_lines)
  end

  defp determine_analysis_depth(signal) do
    change_size = calculate_change_size(signal.data)

    cond do
      change_size > 100 -> :deep
      change_size > 20 -> :normal
      true -> :shallow
    end
  end

  @doc """
  Returns metrics about the skill's performance.
  """
  def metrics(state) do
    %{
      files_analyzed: state.files_analyzed,
      total_issues_found: state.total_issues_found,
      total_fixes_applied: state.total_fixes_applied,
      average_quality_score: calculate_average_quality(state),
      cache_hit_rate: calculate_cache_hit_rate(state)
    }
  end

  defp calculate_average_quality(state) do
    scores = state.quality_scores || []

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp calculate_cache_hit_rate(_state) do
    # Would calculate actual cache hit rate
    0.0
  end
end
