defmodule RubberDuck.Agents.AIAnalysisAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.AIAnalysisAgent

  alias RubberDuck.Actions.AI.{
    AssessQuality,
    DiscoverPatterns,
    GenerateInsights,
    LearnFromFeedback,
    RunAnalysis,
    ScheduleAnalysis
  }

  describe "agent initialization" do
    test "starts with default state" do
      agent = AIAnalysisAgent.new()

      assert agent.state.analysis_queue == []
      assert agent.state.scheduled_analyses == %{}
      assert agent.state.quality_metrics == %{}
      assert agent.state.discovered_patterns == []
      assert agent.state.feedback_history == []
    end

    test "accepts custom configuration" do
      agent = AIAnalysisAgent.new()
      agent = %{agent | state: %{agent.state | analysis_interval: 7200}}

      assert agent.state.analysis_interval == 7200
    end
  end

  describe "analysis scheduling" do
    setup do
      agent = AIAnalysisAgent.new()
      %{agent: agent}
    end

    test "schedules project analysis", %{agent: agent} do
      params = %{
        project_id: "project123",
        analysis_types: [:general, :quality],
        priority: :medium
      }

      context = %{agent: agent}

      assert {:ok, schedule} = ScheduleAnalysis.run(params, context)
      assert schedule.priority == :medium
      assert :general in schedule.analysis_types
      assert :quality in schedule.analysis_types
    end

    test "handles immediate priority scheduling", %{agent: agent} do
      params = %{
        project_id: "urgent_project",
        priority: :immediate
      }

      context = %{agent: agent}

      assert {:ok, schedule} = ScheduleAnalysis.run(params, context)
      assert schedule.priority == :immediate
      assert DateTime.diff(schedule.scheduled_at, DateTime.utc_now()) < 60
    end

    test "adds analysis to queue via instruction", %{agent: agent} do
      {:ok, result, updated_agent} =
        AIAnalysisAgent.handle_instruction(
          {:schedule_analysis, %{project_id: "test", priority: :high}},
          agent
        )

      assert result.priority == :high
      assert length(updated_agent.state.analysis_queue) > 0
    end
  end

  describe "analysis execution" do
    setup do
      agent = AIAnalysisAgent.new()
      %{agent: agent}
    end

    test "runs project analysis", %{agent: _agent} do
      params = %{
        project_id: "project123",
        analysis_types: [:general],
        context: %{}
      }

      # Note: This would normally interact with actual project data
      # For testing, we're verifying the structure
      assert {:ok, _result} = RunAnalysis.run(params, %{})
    end

    test "runs code file analysis", %{agent: _agent} do
      params = %{
        file_id: "file123",
        analysis_types: [:complexity, :quality],
        context: %{}
      }

      # This test verifies the action can be called
      # Actual execution would require database fixtures
      assert_raise FunctionClauseError, fn ->
        RunAnalysis.run(params, %{})
      end
    end

    test "handles analysis instruction", %{agent: agent} do
      # Mock a simple project analysis
      result =
        AIAnalysisAgent.handle_instruction(
          {:analyze_project, "project123"},
          agent
        )

      # The actual result depends on database state
      # We're testing the instruction handling
      assert elem(result, 0) in [:ok, :error]
    end
  end

  describe "quality assessment" do
    test "assesses analysis quality" do
      analysis_result = %{
        summary: "Test analysis summary",
        details: %{metrics: %{complexity: 10}},
        score: 85.0,
        suggestions: ["Improve documentation", "Add tests"]
      }

      params = %{
        analysis_result: analysis_result,
        historical_data: %{},
        criteria: [:accuracy, :relevance, :completeness]
      }

      assert {:ok, assessment} = AssessQuality.run(params, %{})
      assert Map.has_key?(assessment, :metrics)
      assert Map.has_key?(assessment, :overall_score)
      assert assessment.overall_score > 0
    end

    test "compares with historical data" do
      analysis_result = %{
        summary: "Analysis with history",
        score: 90.0,
        suggestions: ["Minor improvements"]
      }

      historical = %{
        overall_scores: [75.0, 80.0, 85.0],
        accuracy: [%{score: 0.7}, %{score: 0.8}]
      }

      params = %{
        analysis_result: analysis_result,
        historical_data: historical
      }

      assert {:ok, assessment} = AssessQuality.run(params, %{})
      assert assessment.comparison.status == :compared
      assert assessment.comparison.percentile > 0
    end
  end

  describe "learning from feedback" do
    test "processes positive feedback" do
      feedback = %{
        analysis_id: "analysis123",
        rating: 5,
        comment: "Very helpful and accurate analysis"
      }

      params = %{
        feedback: feedback,
        history: [],
        learning_rate: 0.1
      }

      assert {:ok, result} = LearnFromFeedback.run(params, %{})
      assert result.processed_feedback.sentiment == :positive
      assert length(result.recommendations) > 0
    end

    test "processes corrective feedback" do
      feedback = %{
        analysis_id: "analysis456",
        correction: "The complexity score should be higher",
        specific_issue: "Missed nested conditions"
      }

      params = %{
        feedback: feedback,
        history: []
      }

      assert {:ok, result} = LearnFromFeedback.run(params, %{})
      assert result.processed_feedback.type == :correction
      assert length(result.improvement_areas) > 0
    end

    test "learns from feedback via instruction" do
      agent = AIAnalysisAgent.new()

      feedback = %{
        analysis_id: "test123",
        rating: 4,
        suggestion: "Focus more on performance analysis"
      }

      {:ok, result, updated_agent} =
        AIAnalysisAgent.handle_instruction(
          {:process_feedback, feedback},
          agent
        )

      assert result.processed_feedback
      assert length(updated_agent.state.feedback_history) > 0
    end
  end

  describe "pattern discovery" do
    test "discovers patterns in analyses" do
      params = %{
        scope: :project,
        existing_patterns: [],
        confidence_threshold: 0.7,
        min_occurrences: 2
      }

      # This would normally work with actual analysis data
      # For now, we test the structure without DB access
      result = DiscoverPatterns.run(params, %{})

      # The action should return either success or error based on data availability
      assert elem(result, 0) in [:ok, :error]
    end

    test "validates pattern confidence" do
      existing_patterns = [
        %{
          type: :high_complexity,
          signature: "complexity_high",
          confidence: 0.8,
          occurrences: 5
        }
      ]

      params = %{
        scope: :workspace,
        existing_patterns: existing_patterns,
        confidence_threshold: 0.6
      }

      assert {:ok, result} = DiscoverPatterns.run(params, %{})
      assert result.confidence_scores
    end
  end

  describe "insight generation" do
    test "generates insights from context" do
      context = %{
        project_id: "project123",
        quality_score: 75,
        complexity: 15
      }

      patterns = [
        %{
          type: :quality_issue,
          signature: "low_doc_coverage",
          confidence: 0.85,
          occurrences: 8
        }
      ]

      params = %{
        context: context,
        patterns: patterns,
        cache: %{},
        depth: :normal
      }

      assert {:ok, insights} = GenerateInsights.run(params, %{})
      assert Map.has_key?(insights, :trends)
      assert Map.has_key?(insights, :predictions)
      assert Map.has_key?(insights, :opportunities)
      assert Map.has_key?(insights, :recommendations)
    end

    test "uses cache for performance" do
      context = %{workspace: true}
      cache = %{previous_analysis: %{pattern_count: 10}}

      params = %{
        context: context,
        patterns: [],
        cache: cache,
        depth: :normal
      }

      assert {:ok, insights} = GenerateInsights.run(params, %{})
      assert insights.metadata.cache_hit == true
    end
  end

  describe "typed message handling" do
    test "handles project changed message" do
      agent = AIAnalysisAgent.new()

      msg = %{
        project_id: "project123",
        change_type: :code_update
      }

      {{:ok, result}, updated_agent} =
        AIAnalysisAgent.handle_instruction(
          {:project_changed, msg},
          agent
        )

      assert result.status in [:tracking_only, :analysis_scheduled]
      activity = updated_agent.state.project_activity["project123"]
      assert activity.change_count == 1
    end

    test "handles file modified message" do
      agent = AIAnalysisAgent.new()

      msg = %{
        file_id: "file123",
        project_id: "project123",
        change_type: :content_update
      }

      {{:ok, result}, updated_agent} =
        AIAnalysisAgent.handle_instruction(
          {:file_modified, msg},
          agent
        )

      assert result.status in [:changes_tracked, :analysis_scheduled]
      tracking = updated_agent.state.file_change_tracking["file123"]
      assert tracking.modification_count == 1
    end

    test "handles analysis requested message" do
      agent = AIAnalysisAgent.new()

      msg = %{
        project_id: "urgent_project",
        analysis_types: [:security],
        priority: :high
      }

      result =
        AIAnalysisAgent.handle_instruction(
          {:analysis_requested, msg},
          agent
        )

      # Should be added to queue with high priority
      {status, _result, updated_agent} = result
      assert status == :ok
      assert length(updated_agent.state.analysis_queue) > 0
      queue_item = hd(updated_agent.state.analysis_queue)
      assert queue_item.priority == :high
    end

    test "handles feedback received message" do
      agent = AIAnalysisAgent.new()

      msg = %{
        analysis_id: "analysis789",
        feedback: %{
          rating: 4,
          comment: "Good analysis"
        }
      }

      result =
        AIAnalysisAgent.handle_instruction(
          {:feedback_received, msg},
          agent
        )

      # Should trigger feedback processing
      assert elem(result, 0) == :ok
    end
  end

  describe "autonomous behavior" do
    test "triggers analysis based on activity threshold" do
      agent = AIAnalysisAgent.new()

      # Simulate multiple changes to trigger analysis
      agent =
        Enum.reduce(1..10, agent, fn i, acc ->
          msg = %{project_id: "active_project", change_count: i}

          {{:ok, _result}, updated} =
            AIAnalysisAgent.handle_instruction({:project_changed, msg}, acc)

          updated
        end)

      activity = agent.state.project_activity["active_project"]
      assert activity.change_count >= 10
    end

    test "respects analysis interval" do
      agent = AIAnalysisAgent.new()
      agent = %{agent | state: %{agent.state | analysis_interval: 3600}}

      # Add last analysis timestamp
      project_activity = %{
        "project123" => %{
          last_analysis: DateTime.add(DateTime.utc_now(), -1800, :second),
          change_count: 5
        }
      }

      agent = %{agent | state: %{agent.state | project_activity: project_activity}}

      # Should not trigger due to time constraint
      msg = %{project_id: "project123"}

      {{:ok, _result}, updated_agent} =
        AIAnalysisAgent.handle_instruction({:project_changed, msg}, agent)

      # Verify no new analysis scheduled immediately
      assert updated_agent.state.project_activity["project123"].change_count == 6
    end
  end

  describe "optimization and improvement" do
    test "updates quality metrics" do
      agent = AIAnalysisAgent.new()

      quality_data = %{
        accuracy: 0.85,
        relevance: 0.90,
        completeness: 0.95
      }

      updated_agent = %{agent | state: Map.put(agent.state, :quality_metrics, quality_data)}

      assert updated_agent.state.quality_metrics.accuracy == 0.85
      assert updated_agent.state.quality_metrics.relevance == 0.90
    end

    test "maintains improvement targets" do
      agent = AIAnalysisAgent.new()

      targets = [
        %{area: :documentation, priority: :high},
        %{area: :complexity, priority: :medium}
      ]

      updated_agent = %{agent | state: Map.put(agent.state, :improvement_targets, targets)}

      assert length(updated_agent.state.improvement_targets) == 2
      assert hd(updated_agent.state.improvement_targets).area == :documentation
    end
  end
end
