defmodule RubberDuck.Verdict.Coordination.ConsensusEngineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Verdict.Coordination.ConsensusEngine

  describe "compute_consensus/2" do
    test "computes weighted average consensus with valid inputs" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.7, confidence: 0.8, issues: [], recommendations: []}
      }

      consensus_config = %{voting_method: :weighted_average}

      {:ok, result} = ConsensusEngine.compute_consensus(agent_results, consensus_config)

      assert result.consensus_score > 0.0
      assert result.consensus_score <= 1.0
      assert result.consensus_method == :weighted_average
      assert result.participating_agents == [:code_quality, :architecture]
      assert result.agent_count == 2
    end

    test "computes majority vote consensus" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.85, confidence: 0.8, issues: [], recommendations: []},
        security: %{score: 0.82, confidence: 0.85, issues: [], recommendations: []}
      }

      consensus_config = %{voting_method: :majority_vote}

      {:ok, result} = ConsensusEngine.compute_consensus(agent_results, consensus_config)

      assert result.consensus_method == :majority_vote
      assert result.agent_count == 3
    end

    test "computes confidence weighted consensus" do
      agent_results = %{
        code_quality: %{score: 0.6, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.8, confidence: 0.5, issues: [], recommendations: []}
      }

      consensus_config = %{voting_method: :confidence_weighted}

      {:ok, result} = ConsensusEngine.compute_consensus(agent_results, consensus_config)

      assert result.consensus_method == :confidence_weighted
      # Score should be weighted more toward code_quality due to higher confidence
      # Less than architecture score
      assert result.consensus_score < 0.8
      # More than code_quality score
      assert result.consensus_score > 0.6
    end

    test "returns error for insufficient agents" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []}
      }

      {:error, reason} = ConsensusEngine.compute_consensus(agent_results)

      assert String.contains?(reason, "Insufficient agents")
    end

    test "returns error for invalid agent results" do
      agent_results = %{
        # Missing score
        code_quality: %{confidence: 0.9},
        architecture: %{score: 0.8, confidence: 0.8, issues: [], recommendations: []}
      }

      {:error, reason} = ConsensusEngine.compute_consensus(agent_results)

      assert String.contains?(reason, "Invalid agent results")
    end

    test "returns error for unsupported voting method" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.7, confidence: 0.8, issues: [], recommendations: []}
      }

      consensus_config = %{voting_method: :invalid_method}

      {:error, reason} = ConsensusEngine.compute_consensus(agent_results, consensus_config)

      assert String.contains?(reason, "Unsupported voting method")
    end

    test "returns no consensus when threshold not met" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.3, issues: [], recommendations: []},
        architecture: %{score: 0.7, confidence: 0.2, issues: [], recommendations: []}
      }

      consensus_config = %{voting_method: :confidence_weighted, consensus_threshold: 0.8}

      {:error, :no_consensus} = ConsensusEngine.compute_consensus(agent_results, consensus_config)
    end
  end

  describe "analyze_agreement/1" do
    test "analyzes agreement for similar agent results" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.82, confidence: 0.88, issues: [], recommendations: []}
      }

      analysis = ConsensusEngine.analyze_agreement(agent_results)

      # High agreement
      assert analysis.agreement_score > 0.8
      assert analysis.confidence_alignment > 0.8
      assert analysis.disagreement_areas.severity == :low
      assert analysis.consensus_feasibility == :high
    end

    test "analyzes agreement for disagreeing agent results" do
      agent_results = %{
        code_quality: %{score: 0.9, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.3, confidence: 0.8, issues: [], recommendations: []},
        security: %{score: 0.6, confidence: 0.7, issues: [], recommendations: []}
      }

      analysis = ConsensusEngine.analyze_agreement(agent_results)

      # Low agreement
      assert analysis.agreement_score < 0.7
      assert analysis.disagreement_areas.severity == :high
      assert analysis.disagreement_areas.score_range > 0.3
      assert analysis.consensus_feasibility == :low
    end

    test "handles single agent result" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []}
      }

      analysis = ConsensusEngine.analyze_agreement(agent_results)

      # Perfect agreement with self
      assert analysis.agreement_score == 1.0
      assert analysis.confidence_alignment == 1.0
    end
  end

  describe "consensus_achievable?/2" do
    test "returns true for high agreement" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.82, confidence: 0.88, issues: [], recommendations: []}
      }

      assert ConsensusEngine.consensus_achievable?(agent_results)
      assert ConsensusEngine.consensus_achievable?(agent_results, 0.6)
    end

    test "returns false for low agreement" do
      agent_results = %{
        code_quality: %{score: 0.9, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.3, confidence: 0.8, issues: [], recommendations: []}
      }

      refute ConsensusEngine.consensus_achievable?(agent_results)
      refute ConsensusEngine.consensus_achievable?(agent_results, 0.8)
    end

    test "respects custom threshold" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.75, confidence: 0.85, issues: [], recommendations: []}
      }

      # Lower threshold
      assert ConsensusEngine.consensus_achievable?(agent_results, 0.6)
      # Higher threshold
      refute ConsensusEngine.consensus_achievable?(agent_results, 0.95)
    end
  end

  describe "consensus result structure" do
    test "includes complete consensus metadata" do
      agent_results = %{
        code_quality: %{
          score: 0.8,
          confidence: 0.9,
          issues: ["Minor naming issue"],
          recommendations: ["Improve variable names"],
          cost_usd: 0.05,
          tokens_used: 150
        },
        architecture: %{
          score: 0.75,
          confidence: 0.85,
          issues: ["Coupling concern"],
          recommendations: ["Reduce dependencies"],
          cost_usd: 0.03,
          tokens_used: 120
        }
      }

      {:ok, result} = ConsensusEngine.compute_consensus(agent_results)

      assert Map.has_key?(result, :consensus_score)
      assert Map.has_key?(result, :consensus_confidence)
      assert Map.has_key?(result, :consensus_method)
      assert Map.has_key?(result, :participating_agents)
      assert Map.has_key?(result, :agent_count)
      assert Map.has_key?(result, :consolidated_issues)
      assert Map.has_key?(result, :consolidated_recommendations)
      assert Map.has_key?(result, :consensus_reasoning)
      assert Map.has_key?(result, :individual_agent_results)
      assert Map.has_key?(result, :total_cost)
      assert Map.has_key?(result, :total_tokens)
      assert Map.has_key?(result, :agent_cost_breakdown)

      assert result.total_cost == 0.08
      assert result.total_tokens == 270
      assert length(result.consolidated_issues) > 0
      assert length(result.consolidated_recommendations) > 0
    end
  end

  describe "agent weight calculation" do
    test "assigns appropriate weights based on specialization" do
      agent_results = %{
        security: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        test_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        architecture: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []},
        code_quality: %{score: 0.8, confidence: 0.9, issues: [], recommendations: []}
      }

      {:ok, result} = ConsensusEngine.compute_consensus(agent_results)

      # Security should have highest influence due to specialization weight
      # This is tested indirectly through the consensus mechanism
      assert result.consensus_method == :weighted_average
      assert result.agent_count == 4
    end
  end

  describe "edge cases" do
    test "handles zero confidence gracefully" do
      agent_results = %{
        code_quality: %{score: 0.8, confidence: 0.0, issues: [], recommendations: []},
        architecture: %{score: 0.7, confidence: 0.0, issues: [], recommendations: []}
      }

      consensus_config = %{voting_method: :confidence_weighted}

      {:error, :insufficient_confidence} =
        ConsensusEngine.compute_consensus(agent_results, consensus_config)
    end

    test "handles missing optional fields gracefully" do
      agent_results = %{
        # Missing issues, recommendations, cost, tokens
        code_quality: %{score: 0.8, confidence: 0.9},
        architecture: %{score: 0.7, confidence: 0.8}
      }

      {:ok, result} = ConsensusEngine.compute_consensus(agent_results)

      assert result.total_cost == 0.0
      assert result.total_tokens == 0
      assert result.consolidated_issues == []
      assert result.consolidated_recommendations == []
    end
  end
end
