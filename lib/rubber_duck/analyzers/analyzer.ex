defmodule RubberDuck.Analyzer do
  @moduledoc """
  Behavior for focused analysis components.
  
  Analyzers are stateless, pure functions that process typed messages
  and return analysis results. They integrate with Jido skills while
  maintaining separation of concerns.
  
  ## Design Principles
  
  - **Single Responsibility**: Each analyzer handles one specific analysis type
  - **Pure Functions**: Stateless operations with explicit dependencies
  - **Type Safety**: Work with typed messages, not string signals
  - **Composable**: Can be combined in pipelines or run in parallel
  - **Testable**: Easy to test in isolation
  
  ## Implementing an Analyzer
  
      defmodule MyAnalyzer do
        @behaviour RubberDuck.Analyzer
        
        @impl true
        def analyze(message, context) do
          # Perform analysis
          {:ok, %{result: "analysis complete"}}
        end
        
        @impl true
        def supported_types do
          [Messages.MyMessage]
        end
      end
  
  ## Integration with Skills
  
  Skills use analyzers by calling their `analyze/2` function and combining
  results. Skills remain responsible for:
  - Signal handling (Jido compatibility)
  - Orchestration of multiple analyzers
  - Error handling and recovery
  - State management
  - Telemetry and monitoring
  """
  
  @type message :: struct()
  @type context :: map()
  @type result :: map()
  @type error_reason :: atom() | {atom(), any()}
  
  @doc """
  Analyzes a message and returns analysis results.
  
  ## Parameters
  
  - `message` - A typed message struct to analyze
  - `context` - Analysis context including configuration, metadata
  
  ## Returns
  
  - `{:ok, result}` - Successful analysis with results map
  - `{:error, reason}` - Analysis failed with reason
  
  ## Examples
  
      analyze(%Messages.Code.Analyze{file_path: "lib/app.ex"}, %{depth: :deep})
      #=> {:ok, %{issues: [], score: 0.95}}
  """
  @callback analyze(message :: message(), context :: context()) ::
              {:ok, result()} | {:error, error_reason()}
  
  @doc """
  Validates a message before analysis.
  
  This is an optional callback that can be used to validate messages
  before analysis begins. Useful for checking required fields or
  message format.
  
  ## Parameters
  
  - `message` - The message to validate
  
  ## Returns
  
  - `{:ok, message}` - Valid message, possibly transformed
  - `{:error, reason}` - Invalid message with reason
  """
  @callback validate(message :: message()) ::
              {:ok, message()} | {:error, error_reason()}
  
  @doc """
  Returns the list of message types this analyzer supports.
  
  Used by the analyzer registry and skills to route messages to
  appropriate analyzers.
  
  ## Returns
  
  List of module names representing supported message types.
  
  ## Examples
  
      supported_types()
      #=> [Messages.Code.Analyze, Messages.Code.SecurityScan]
  """
  @callback supported_types() :: [module()]
  
  @doc """
  Returns the priority of this analyzer.
  
  Used for ordering when multiple analyzers process the same message.
  Higher priority analyzers may be given preference or more resources.
  
  ## Returns
  
  Priority level: `:low`, `:normal`, `:high`, or `:critical`
  
  Default: `:normal`
  """
  @callback priority() :: :low | :normal | :high | :critical
  
  @doc """
  Returns the timeout for this analyzer in milliseconds.
  
  Used to prevent analyzers from running indefinitely. Skills may
  use this to set appropriate timeouts when calling analyzers.
  
  ## Returns
  
  Timeout in milliseconds. Default: 10000 (10 seconds)
  """
  @callback timeout() :: pos_integer()
  
  @doc """
  Returns metadata about this analyzer.
  
  Used for discovery, documentation, and monitoring purposes.
  
  ## Returns
  
  Map containing analyzer metadata such as:
  - `:name` - Human-readable name
  - `:description` - What this analyzer does
  - `:version` - Analyzer version
  - `:tags` - List of tags for categorization
  """
  @callback metadata() :: map()
  
  @optional_callbacks validate: 1, priority: 0, timeout: 0, metadata: 0
  
  @doc """
  Runs multiple analyzers in parallel and collects results.
  
  This is a helper function for skills to run multiple analyzers
  concurrently. Results are returned in the same order as analyzers.
  
  ## Parameters
  
  - `analyzers` - List of analyzer modules
  - `message` - Message to analyze
  - `context` - Analysis context
  - `opts` - Options including:
    - `:timeout` - Overall timeout for all analyzers (default: 15000ms)
    - `:max_concurrency` - Maximum concurrent analyzers (default: 4)
  
  ## Returns
  
  - `{:ok, results}` - List of `{analyzer_module, result}` tuples
  - `{:error, failures}` - List of `{analyzer_module, reason}` tuples
  
  ## Examples
  
      run_parallel([Security, Performance], message, context)
      #=> {:ok, [{Security, %{vulnerabilities: []}}, 
      #          {Performance, %{score: 0.8}}]}
  """
  def run_parallel(analyzers, message, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 15_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    
    results = 
      analyzers
      |> Task.async_stream(
        fn analyzer ->
          {analyzer, safe_analyze(analyzer, message, context)}
        end,
        timeout: timeout,
        max_concurrency: max_concurrency,
        on_timeout: :kill_task
      )
      |> Enum.map(&handle_task_result/1)
    
    {successes, failures} = Enum.split_with(results, &match?({_, {:ok, _}}, &1))
    
    if length(failures) == 0 do
      {:ok, successes}
    else
      {:error, failures}
    end
  end
  
  @doc """
  Runs analyzers in a pipeline where each analyzer can transform the message.
  
  This is useful when analyzers need to run in sequence, with each one
  potentially enriching or modifying the message for the next.
  
  ## Parameters
  
  - `analyzers` - List of analyzer modules  
  - `message` - Initial message
  - `context` - Analysis context
  
  ## Returns
  
  - `{:ok, final_result}` - Combined results from all analyzers
  - `{:error, {analyzer, reason}}` - First analyzer that failed
  
  ## Examples
  
      run_pipeline([Validator, Enricher, Analyzer], message, context)
      #=> {:ok, %{validated: true, enriched: true, analyzed: true}}
  """
  def run_pipeline(analyzers, message, context) do
    analyzers
    |> Enum.reduce_while({:ok, message, %{}}, fn analyzer, {:ok, current_message, results} ->
      case safe_analyze(analyzer, current_message, context) do
        {:ok, result} ->
          # Allow analyzer to transform message if it returns one
          next_message = Map.get(result, :message, current_message)
          combined_results = Map.merge(results, Map.delete(result, :message))
          {:cont, {:ok, next_message, combined_results}}
          
        {:error, reason} ->
          {:halt, {:error, {analyzer, reason}}}
      end
    end)
    |> case do
      {:ok, _final_message, results} -> {:ok, results}
      error -> error
    end
  end
  
  # Private helper to safely call analyzer with fallbacks
  defp safe_analyze(analyzer, message, context) do
    # Check if analyzer implements validate callback
    if function_exported?(analyzer, :validate, 1) do
      case analyzer.validate(message) do
        {:ok, validated_message} ->
          analyzer.analyze(validated_message, context)
        {:error, _reason} = error ->
          error
      end
    else
      analyzer.analyze(message, context)
    end
  rescue
    error ->
      {:error, {:analyzer_crashed, error}}
  end
  
  defp handle_task_result({:ok, result}), do: result
  defp handle_task_result({:exit, :timeout}), do: {:error, :timeout}
  defp handle_task_result({:exit, reason}), do: {:error, {:crashed, reason}}
end