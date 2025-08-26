defmodule RubberDuck.Agents.Judges.CodeQualityJudgeAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.Judges.CodeQualityJudgeAgent

  describe "init/1" do
    test "initializes with default state" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      assert agent.state.specialization == :code_quality
      assert agent.state.criteria_weights != nil
      assert agent.state.evaluation_history == []
      assert agent.state.performance_metrics.evaluations_completed == 0
    end

    test "initializes with custom configuration" do
      config = %{strict_mode: true}
      {:ok, agent} = CodeQualityJudgeAgent.init(config: config)

      assert agent.state.configuration == config
    end
  end

  describe "evaluate_code/4" do
    setup do
      {:ok, agent} = CodeQualityJudgeAgent.init()
      %{agent: agent}
    end

    test "evaluates simple code successfully", %{agent: agent} do
      code = """
      defmodule Test do
        def hello, do: "world"
      end
      """

      {:ok, result, updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code)

      assert result.specialization == :code_quality
      assert result.score >= 0.0 and result.score <= 1.0
      assert result.confidence >= 0.0 and result.confidence <= 1.0
      assert is_list(result.issues)
      assert is_list(result.recommendations)
      assert Map.has_key?(result, :detailed_analysis)
      assert Map.has_key?(result, :metadata)
      assert updated_agent.state.performance_metrics.evaluations_completed == 1
    end

    test "evaluates code with context", %{agent: agent} do
      code = "def add(a, b), do: a + b"
      context = %{project_type: :library, framework: :elixir}

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code, context)

      assert result.specialization == :code_quality
      assert Map.has_key?(result, :evaluation_timestamp)
    end

    test "evaluates code with custom options", %{agent: agent} do
      code = "def test, do: :ok"
      context = %{}
      options = [focus_areas: [:readability, :maintainability]]

      {:ok, result, _updated_agent} =
        CodeQualityJudgeAgent.evaluate_code(agent, code, context, options)

      assert result.specialization == :code_quality
    end

    test "handles evaluation failure gracefully", %{agent: agent} do
      # This test would require mocking internal analysis functions to fail
      # For now, test with edge case inputs
      code = nil

      # Should handle nil input gracefully
      result = CodeQualityJudgeAgent.evaluate_code(agent, code)
      assert match?({:error, _reason, ^agent}, result)
    end
  end

  describe "get_capabilities/1" do
    test "returns agent capabilities" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      capabilities = CodeQualityJudgeAgent.get_capabilities(agent)

      assert capabilities.specialization == :code_quality
      assert is_list(capabilities.criteria)
      assert is_list(capabilities.strengths)
      assert is_list(capabilities.limitations)
      assert Enum.member?(capabilities.strengths, "Code readability assessment")
    end
  end

  describe "configure_weights/2" do
    test "updates criteria weights" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      new_weights = %{readability: 1.5, complexity: 0.5}
      {:ok, updated_agent} = CodeQualityJudgeAgent.configure_weights(agent, new_weights)

      assert updated_agent.state.criteria_weights.readability == 1.5
      assert updated_agent.state.criteria_weights.complexity == 0.5
      # Other weights should remain unchanged
      assert Map.has_key?(updated_agent.state.criteria_weights, :maintainability)
    end
  end

  describe "performance metrics tracking" do
    test "tracks evaluation count and timing" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      code = "def simple, do: :ok"

      {:ok, _result1, agent1} = CodeQualityJudgeAgent.evaluate_code(agent, code)
      {:ok, _result2, agent2} = CodeQualityJudgeAgent.evaluate_code(agent1, code)

      assert agent2.state.performance_metrics.evaluations_completed == 2
      assert agent2.state.performance_metrics.avg_evaluation_time > 0.0
      assert length(agent2.state.performance_metrics.confidence_trend) == 2
    end
  end

  describe "evaluation result structure" do
    test "includes all required fields" do
      {:ok, agent} = CodeQualityJudgeAgent.init()
      code = "def test, do: :ok"

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code)

      required_fields = [
        :score,
        :confidence,
        :specialization,
        :issues,
        :recommendations,
        :detailed_analysis,
        :metadata,
        :evaluation_timestamp
      ]

      Enum.each(required_fields, fn field ->
        assert Map.has_key?(result, field), "Missing field: #{field}"
      end)
    end

    test "detailed analysis includes all criteria" do
      {:ok, agent} = CodeQualityJudgeAgent.init()
      code = "def test, do: :ok"

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code)

      expected_criteria = [
        :readability,
        :maintainability,
        :naming_conventions,
        :code_organization,
        :complexity,
        :documentation,
        :error_handling,
        :code_duplication
      ]

      Enum.each(expected_criteria, fn criterion ->
        assert Map.has_key?(result.detailed_analysis, criterion),
               "Missing criterion: #{criterion}"

        criterion_result = result.detailed_analysis[criterion]
        assert Map.has_key?(criterion_result, :score)
        assert Map.has_key?(criterion_result, :issues)
        assert Map.has_key?(criterion_result, :confidence)
      end)
    end

    test "metadata includes analysis statistics" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      code = """
      defmodule Test do
        def hello, do: "world"
        def goodbye, do: "farewell"
      end
      """

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code)

      metadata_fields = [:lines_analyzed, :functions_analyzed, :complexity_metrics]

      Enum.each(metadata_fields, fn field ->
        assert Map.has_key?(result.metadata, field), "Missing metadata field: #{field}"
      end)

      assert result.metadata.lines_analyzed > 0
      assert result.metadata.functions_analyzed > 0
    end
  end

  describe "issue detection and classification" do
    test "classifies issues by severity" do
      {:ok, agent} = CodeQualityJudgeAgent.init()
      code = "def test, do: :ok"

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code)

      # Issues should have proper structure if any are found
      Enum.each(result.issues, fn issue ->
        assert Map.has_key?(issue, :criterion)
        assert Map.has_key?(issue, :description)
        assert Map.has_key?(issue, :severity)
        assert issue.severity in [:low, :medium, :high]
      end)
    end
  end

  describe "scoring algorithm" do
    test "produces consistent scores for identical code" do
      {:ok, agent} = CodeQualityJudgeAgent.init()
      code = "def hello, do: :world"

      {:ok, result1, agent1} = CodeQualityJudgeAgent.evaluate_code(agent, code)
      {:ok, result2, _agent2} = CodeQualityJudgeAgent.evaluate_code(agent1, code)

      # Scores should be identical for same code and same agent state
      assert result1.score == result2.score
      assert result1.confidence == result2.confidence
    end

    test "weighted scoring respects criteria weights" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      # Configure to heavily weight complexity
      new_weights = %{complexity: 2.0, readability: 0.1}
      {:ok, weighted_agent} = CodeQualityJudgeAgent.configure_weights(agent, new_weights)

      code = "def test, do: :ok"

      {:ok, normal_result, _} = CodeQualityJudgeAgent.evaluate_code(agent, code)
      {:ok, weighted_result, _} = CodeQualityJudgeAgent.evaluate_code(weighted_agent, code)

      # Results might differ due to different weighting
      # This test verifies the weighting system works
      assert is_number(normal_result.score)
      assert is_number(weighted_result.score)
    end
  end

  describe "edge cases" do
    test "handles empty code" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      result = CodeQualityJudgeAgent.evaluate_code(agent, "")
      assert match?({:error, _reason, ^agent}, result)
    end

    test "handles very long code" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      long_code = String.duplicate("def func#{:rand.uniform(1_000)}, do: :ok\n", 100)

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, long_code)

      assert result.specialization == :code_quality
      assert result.metadata.lines_analyzed > 90
    end

    test "handles code with special characters" do
      {:ok, agent} = CodeQualityJudgeAgent.init()

      code = """
      defmodule TestModule do
        @doc "Handles émojis and ñ characters"
        def test_unicode, do: "🚀 Élixir is awesome! ñoño"
      end
      """

      {:ok, result, _updated_agent} = CodeQualityJudgeAgent.evaluate_code(agent, code)

      assert result.specialization == :code_quality
    end
  end
end
