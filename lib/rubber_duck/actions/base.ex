defmodule RubberDuck.Action.Base do
  @moduledoc """
  Base behavior for all RubberDuck actions.

  Provides common patterns for action implementation including:
  - Pipeline execution helpers
  - Error handling and recovery
  - Telemetry integration
  - Delegation patterns

  ## Usage

      defmodule MyAction do
        use RubberDuck.Action.Base
        
        delegate_to MyAction.Validator, :validate
        delegate_to MyAction.Executor, :execute
      end
  """

  @doc """
  Defines the behavior that all actions must implement.
  """
  @callback run(params :: map(), context :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Optional callback for action initialization.
  """
  @callback init(opts :: keyword()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks [init: 1]

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      @behaviour RubberDuck.Action.Base

      require Logger
      alias RubberDuck.Telemetry.MessageTelemetry

      @before_compile RubberDuck.Action.Base

      # Store delegations for use in before_compile
      Module.register_attribute(__MODULE__, :delegations, accumulate: true)

      @doc false
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end

      import RubberDuck.Action.Base, only: [delegate_to: 2, delegate_to: 3]
    end
  end

  @doc """
  Macro for delegating responsibilities to specialized modules.

  ## Examples

      delegate_to MyAction.Validator, :validate
      delegate_to MyAction.Executor, :execute, as: :run_execution
  """
  defmacro delegate_to(module, function, opts \\ []) do
    as = Keyword.get(opts, :as, function)

    quote do
      @delegations {unquote(as), unquote(module), unquote(function)}

      def unquote(as)(params, context \\ %{}) do
        RubberDuck.Action.Base.execute_delegation(
          unquote(module),
          unquote(function),
          params,
          context,
          __MODULE__
        )
      end
    end
  end

  @doc """
  Execute a delegated function with telemetry and error handling.
  """
  def execute_delegation(module, function, params, context, caller) do
    start_time = System.monotonic_time(:microsecond)

    # Emit telemetry start event
    :telemetry.execute(
      [:rubber_duck, :action, :delegation, :start],
      %{system_time: System.system_time()},
      %{
        caller: caller,
        module: module,
        function: function
      }
    )

    try do
      result = apply(module, function, [params, context])

      duration = System.monotonic_time(:microsecond) - start_time

      # Emit telemetry stop event
      :telemetry.execute(
        [:rubber_duck, :action, :delegation, :stop],
        %{duration: duration, system_time: System.system_time()},
        %{
          caller: caller,
          module: module,
          function: function,
          success: match?({:ok, _}, result)
        }
      )

      result
    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - start_time

        # Emit telemetry exception event
        :telemetry.execute(
          [:rubber_duck, :action, :delegation, :exception],
          %{duration: duration, system_time: System.system_time()},
          %{
            caller: caller,
            module: module,
            function: function,
            kind: :error,
            reason: error,
            stacktrace: __STACKTRACE__
          }
        )

        {:error, {:delegation_failed, module, function, error}}
    end
  end

  @doc """
  Pipeline execution helper that chains operations together.

  ## Example

      pipeline(params, context, [
        {:validate, &Validator.validate/2},
        {:analyze, &Analyzer.analyze/2},
        {:execute, &Executor.execute/2}
      ])
  """
  def pipeline(initial_params, context, steps) do
    Enum.reduce_while(steps, {:ok, initial_params}, fn
      {step_name, step_fn}, {:ok, params} ->
        case execute_step(step_name, step_fn, params, context) do
          {:ok, result} -> {:cont, {:ok, result}}
          {:error, _} = error -> {:halt, error}
        end

      _, error ->
        {:halt, error}
    end)
  end

  defp execute_step(step_name, step_fn, params, context) do
    start_time = System.monotonic_time(:microsecond)

    :telemetry.execute(
      [:rubber_duck, :action, :pipeline, :step, :start],
      %{system_time: System.system_time()},
      %{step: step_name}
    )

    try do
      result = step_fn.(params, context)

      duration = System.monotonic_time(:microsecond) - start_time

      :telemetry.execute(
        [:rubber_duck, :action, :pipeline, :step, :stop],
        %{duration: duration, system_time: System.system_time()},
        %{step: step_name, success: match?({:ok, _}, result)}
      )

      result
    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - start_time

        :telemetry.execute(
          [:rubber_duck, :action, :pipeline, :step, :exception],
          %{duration: duration, system_time: System.system_time()},
          %{
            step: step_name,
            kind: :error,
            reason: error,
            stacktrace: __STACKTRACE__
          }
        )

        {:error, {:step_failed, step_name, error}}
    end
  end

  @doc """
  Helper for building consistent metadata.
  """
  def build_metadata(params, context, additional \\ %{}) do
    %{
      timestamp: DateTime.utc_now(),
      action: context[:action] || "unknown",
      agent_id: context[:agent_id],
      request_id: context[:request_id] || generate_request_id(),
      params_checksum: calculate_checksum(params)
    }
    |> Map.merge(additional)
  end

  defp generate_request_id do
    bytes = :crypto.strong_rand_bytes(16)
    bytes |> Base.encode16(case: :lower)
  end

  defp calculate_checksum(params) do
    hash = :crypto.hash(:md5, :erlang.term_to_binary(params))

    hash
    |> Base.encode16(case: :lower)
  end

  @doc """
  Helper for error recovery and rollback.
  """
  def with_rollback(operation, rollback_fn) do
    require Logger

    case operation.() do
      {:ok, _} = success ->
        success

      {:error, reason} = error ->
        Logger.warning("Operation failed, executing rollback: #{inspect(reason)}")

        case rollback_fn.(reason) do
          :ok ->
            error

          {:error, rollback_error} ->
            Logger.error("Rollback failed: #{inspect(rollback_error)}")
            {:error, {:rollback_failed, reason, rollback_error}}
        end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Lists all delegations defined in this action.
      """
      def delegations do
        @delegations
      end
    end
  end
end
