defmodule RubberDuck.Skills.LearningSkillTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Skills.LearningSkill

  describe "LearningSkill" do
    test "tracks experience successfully" do
      state = %{agent_id: "test_agent"}

      params = %{
        experience: %{action: :test_action, data: "test"},
        outcome: :success,
        context: %{test_type: :unit}
      }

      assert {:ok, new_state} = LearningSkill.track_experience(params, state)
      assert Map.has_key?(new_state, :experiences)
      assert Map.has_key?(new_state, :learning_patterns)
      assert length(new_state.experiences) == 1
    end

    test "gets insights from learning patterns" do
      experiences = [
        %{
          experience: %{action: :test},
          outcome: :success,
          context: %{type: :unit},
          timestamp: DateTime.utc_now(),
          agent_id: "test"
        }
      ]

      state = %{
        experiences: experiences,
        learning_patterns: %{
          %{type: :unit} => %{success_rate: 0.8, sample_size: 10}
        }
      }

      params = %{context: %{type: :unit}}

      assert {:ok, insights, _new_state} = LearningSkill.get_insights(params, state)
      assert Map.has_key?(insights, :patterns)
      assert Map.has_key?(insights, :confidence)
      assert Map.has_key?(insights, :recommendation)
    end

    test "assesses learning effectiveness" do
      experiences = [
        %{outcome: :success, context: %{}, timestamp: DateTime.utc_now()},
        %{outcome: :failure, context: %{}, timestamp: DateTime.utc_now()}
      ]

      state = %{
        experiences: experiences,
        learning_patterns: %{test: %{success_rate: 0.5}}
      }

      assert {:ok, assessment, _new_state} = LearningSkill.assess_learning(%{}, state)
      assert Map.has_key?(assessment, :total_experiences)
      assert Map.has_key?(assessment, :pattern_count)
      assert Map.has_key?(assessment, :effectiveness_score)
      assert assessment.total_experiences == 2
    end
  end
end
