defmodule RubberDuck.Action.BaseTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Action.Base
  
  # Test modules for delegation
  defmodule TestValidator do
    def validate(params, _context) do
      if params[:valid] do
        {:ok, Map.put(params, :validated, true)}
      else
        {:error, :invalid_params}
      end
    end
  end
  
  defmodule TestExecutor do
    def execute(params, _context) do
      if params[:fail] do
        {:error, :execution_failed}
      else
        {:ok, Map.put(params, :executed, true)}
      end
    end
    
    def execute_with_error(_params, _context) do
      raise "Execution error!"
    end
  end
  
  # Test action using the base behavior
  defmodule TestAction do
    use RubberDuck.Action.Base
    
    delegate_to TestValidator, :validate
    delegate_to TestExecutor, :execute
    delegate_to TestExecutor, :execute_with_error, as: :dangerous_execute
    
    @impl true
    def run(params, context) do
      with {:ok, validated} <- validate(params, context),
           {:ok, result} <- execute(validated, context) do
        {:ok, result}
      end
    end
  end
  
  describe "delegation" do
    test "successful delegation" do
      assert {:ok, result} = TestAction.validate(%{valid: true}, %{})
      assert result.validated == true
    end
    
    test "failed delegation" do
      assert {:error, :invalid_params} = TestAction.validate(%{valid: false}, %{})
    end
    
    test "delegation with custom name" do
      assert {:error, {:delegation_failed, _, _, _}} = 
        TestAction.dangerous_execute(%{}, %{})
    end
    
    test "lists all delegations" do
      delegations = TestAction.delegations()
      
      assert {:validate, TestValidator, :validate} in delegations
      assert {:execute, TestExecutor, :execute} in delegations
      assert {:dangerous_execute, TestExecutor, :execute_with_error} in delegations
    end
  end
  
  describe "pipeline" do
    test "successful pipeline execution" do
      steps = [
        {:validate, fn params, _ctx -> 
          {:ok, Map.put(params, :step1, true)} 
        end},
        {:transform, fn params, _ctx -> 
          {:ok, Map.put(params, :step2, true)} 
        end},
        {:finalize, fn params, _ctx -> 
          {:ok, Map.put(params, :step3, true)} 
        end}
      ]
      
      assert {:ok, result} = Base.pipeline(%{}, %{}, steps)
      assert result.step1 == true
      assert result.step2 == true
      assert result.step3 == true
    end
    
    test "pipeline halts on error" do
      steps = [
        {:step1, fn params, _ctx -> 
          {:ok, Map.put(params, :step1, true)} 
        end},
        {:step2, fn _params, _ctx -> 
          {:error, :step2_failed} 
        end},
        {:step3, fn params, _ctx -> 
          {:ok, Map.put(params, :step3, true)} 
        end}
      ]
      
      assert {:error, :step2_failed} = Base.pipeline(%{}, %{}, steps)
    end
    
    test "pipeline handles exceptions" do
      steps = [
        {:step1, fn params, _ctx -> 
          {:ok, Map.put(params, :step1, true)} 
        end},
        {:step2, fn _params, _ctx -> 
          raise "Pipeline error!" 
        end}
      ]
      
      assert {:error, {:step_failed, :step2, _}} = Base.pipeline(%{}, %{}, steps)
    end
  end
  
  describe "metadata" do
    test "builds metadata with defaults" do
      params = %{test: "value"}
      context = %{agent_id: "agent-123", action: "test_action"}
      
      metadata = Base.build_metadata(params, context)
      
      assert metadata.agent_id == "agent-123"
      assert metadata.action == "test_action"
      assert metadata.timestamp
      assert metadata.request_id
      assert metadata.params_checksum
    end
    
    test "merges additional metadata" do
      params = %{test: "value"}
      context = %{}
      additional = %{custom: "data", version: 2}
      
      metadata = Base.build_metadata(params, context, additional)
      
      assert metadata.custom == "data"
      assert metadata.version == 2
    end
  end
  
  describe "with_rollback" do
    test "returns success when operation succeeds" do
      operation = fn -> {:ok, "success"} end
      rollback = fn _reason -> :ok end
      
      assert {:ok, "success"} = Base.with_rollback(operation, rollback)
    end
    
    test "executes rollback on failure" do
      operation = fn -> {:error, :operation_failed} end
      rollback = fn reason -> 
        send(self(), {:rollback_executed, reason})
        :ok 
      end
      
      assert {:error, :operation_failed} = Base.with_rollback(operation, rollback)
      assert_received {:rollback_executed, :operation_failed}
    end
    
    test "handles rollback failure" do
      operation = fn -> {:error, :operation_failed} end
      rollback = fn _reason -> {:error, :rollback_error} end
      
      assert {:error, {:rollback_failed, :operation_failed, :rollback_error}} = 
        Base.with_rollback(operation, rollback)
    end
  end
  
  describe "telemetry" do
    setup do
      # Attach telemetry handler for testing
      handler_id = "test-handler-#{System.unique_integer()}"
      
      :telemetry.attach_many(
        handler_id,
        [
          [:rubber_duck, :action, :delegation, :start],
          [:rubber_duck, :action, :delegation, :stop],
          [:rubber_duck, :action, :pipeline, :step, :start],
          [:rubber_duck, :action, :pipeline, :step, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)
      
      :ok
    end
    
    test "emits telemetry events for delegation" do
      TestAction.validate(%{valid: true}, %{})
      
      assert_receive {:telemetry_event, 
        [:rubber_duck, :action, :delegation, :start], 
        %{system_time: _}, 
        %{module: TestValidator, function: :validate}}
        
      assert_receive {:telemetry_event, 
        [:rubber_duck, :action, :delegation, :stop], 
        %{duration: _, system_time: _}, 
        %{module: TestValidator, function: :validate, success: true}}
    end
    
    test "emits telemetry events for pipeline steps" do
      steps = [
        {:test_step, fn params, _ctx -> {:ok, params} end}
      ]
      
      Base.pipeline(%{}, %{}, steps)
      
      assert_receive {:telemetry_event,
        [:rubber_duck, :action, :pipeline, :step, :start],
        %{system_time: _},
        %{step: :test_step}}
        
      assert_receive {:telemetry_event,
        [:rubber_duck, :action, :pipeline, :step, :stop],
        %{duration: _, system_time: _},
        %{step: :test_step, success: true}}
    end
  end
end