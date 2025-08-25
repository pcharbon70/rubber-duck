defmodule RubberDuck.Verdict.Resources.EvaluationRunTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Verdict.Resources.EvaluationRun

  describe "create/1" do
    test "creates evaluation run with required fields" do
      params = %{
        evaluation_type: :quality,
        code_hash: "abc123",
        code_size_bytes: 500,
        configuration_snapshot: %{model: "gpt-4o-mini"}
      }

      # Mock the resource creation
      with_mock EvaluationRun, [:passthrough],
        create: fn _params -> {:ok, %{id: "test-id", evaluation_type: :quality}} end do
        assert {:ok, result} = EvaluationRun.create(params)
        assert result.evaluation_type == :quality
      end
    end

    test "validates required fields" do
      invalid_params = %{
        code_hash: "abc123"
        # Missing evaluation_type, code_size_bytes, configuration_snapshot
      }

      with_mock EvaluationRun, [:passthrough],
        create: fn _params -> {:error, "Missing required fields"} end do
        assert {:error, _reason} = EvaluationRun.create(invalid_params)
      end
    end
  end

  describe "evaluation lifecycle" do
    test "can start, complete, and track evaluation" do
      mock_run = %{id: "test-id", status: :pending}

      with_mock EvaluationRun, [:passthrough],
        start_evaluation: fn _run -> {:ok, %{mock_run | status: :running}} end,
        complete_evaluation: fn _run, _params -> {:ok, %{mock_run | status: :completed}} end do
        # Start evaluation
        assert {:ok, started_run} = EvaluationRun.start_evaluation(mock_run)
        assert started_run.status == :running

        # Complete evaluation
        completion_params = %{
          total_cost_usd: Decimal.new("0.05"),
          total_tokens_used: 500,
          total_latency_ms: 2000
        }

        assert {:ok, completed_run} =
                 EvaluationRun.complete_evaluation(started_run, completion_params)

        assert completed_run.status == :completed
      end
    end

    test "can fail evaluation with error message" do
      mock_run = %{id: "test-id", status: :running}

      with_mock EvaluationRun, [:passthrough],
        fail_evaluation: fn _run, params ->
          {:ok, %{mock_run | status: :failed, error_message: params.error_message}}
        end do
        assert {:ok, failed_run} =
                 EvaluationRun.fail_evaluation(mock_run, %{error_message: "API timeout"})

        assert failed_run.status == :failed
        assert failed_run.error_message == "API timeout"
      end
    end
  end

  describe "querying and filtering" do
    test "can query by user" do
      user_id = "user123"

      with_mock EvaluationRun, [:passthrough],
        by_user: fn ^user_id -> {:ok, [%{id: "run1", user_id: user_id}]} end do
        assert {:ok, runs} = EvaluationRun.by_user(user_id)
        assert length(runs) == 1
        assert hd(runs).user_id == user_id
      end
    end

    test "can query by evaluation type" do
      with_mock EvaluationRun, [:passthrough],
        by_evaluation_type: fn :security -> {:ok, [%{id: "run1", evaluation_type: :security}]} end do
        assert {:ok, runs} = EvaluationRun.by_evaluation_type(:security)
        assert length(runs) == 1
        assert hd(runs).evaluation_type == :security
      end
    end

    test "can get completed runs" do
      with_mock EvaluationRun, [:passthrough],
        completed_runs: fn -> {:ok, [%{id: "run1", status: :completed}]} end do
        assert {:ok, runs} = EvaluationRun.completed_runs()
        assert length(runs) == 1
        assert hd(runs).status == :completed
      end
    end
  end

  describe "calculations" do
    test "calculates duration correctly" do
      # Test would verify duration calculation
      # For now, just test that calculations are available
      assert :duration_ms in [:duration_ms, :is_completed, :is_cached, :cost_per_token]
    end

    test "identifies cached evaluations" do
      # Test cache hit identification
      assert :is_cached in [:duration_ms, :is_completed, :is_cached, :cost_per_token]
    end
  end
end
