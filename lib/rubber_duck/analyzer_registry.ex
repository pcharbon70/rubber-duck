defmodule RubberDuck.AnalyzerRegistry do
  @moduledoc """
  Central registry for discovering and routing messages to appropriate analyzers.
  
  The registry maintains a mapping of message types to analyzers and provides
  utilities for finding analyzers that can handle specific messages or analysis
  types.
  
  ## Features
  
  - **Analyzer Discovery**: Find analyzers by message type or analysis category
  - **Priority-based Routing**: Route to highest priority analyzer for a message
  - **Metadata Caching**: Cache analyzer metadata for fast lookups
  - **Runtime Registration**: Register analyzers dynamically
  - **Health Checking**: Validate analyzer availability and functionality
  
  ## Usage
  
      # Find analyzers for a specific message
      analyzers = AnalyzerRegistry.find_analyzers_for(message)
      
      # Get all code analysis analyzers
      code_analyzers = AnalyzerRegistry.find_by_category(:code)
      
      # Register a new analyzer
      AnalyzerRegistry.register(MyAnalyzer)
  """
  
  use GenServer
  require Logger
  
  @registry_table :analyzer_registry
  @metadata_table :analyzer_metadata
  
  # Client API
  
  @doc """
  Starts the analyzer registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers an analyzer with the registry.
  
  The analyzer will be validated and its metadata cached for future lookups.
  
  ## Parameters
  
  - `analyzer` - Module implementing RubberDuck.Analyzer behavior
  
  ## Returns
  
  - `:ok` - Successfully registered
  - `{:error, reason}` - Registration failed
  
  ## Examples
  
      register(RubberDuck.Analyzers.Code.Security)
      #=> :ok
  """
  def register(analyzer) when is_atom(analyzer) do
    GenServer.call(__MODULE__, {:register, analyzer})
  end
  
  @doc """
  Unregisters an analyzer from the registry.
  """
  def unregister(analyzer) when is_atom(analyzer) do
    GenServer.call(__MODULE__, {:unregister, analyzer})
  end
  
  @doc """
  Finds all analyzers that can handle the given message.
  
  Returns analyzers ordered by priority (highest first).
  
  ## Parameters
  
  - `message` - Typed message struct or message module
  
  ## Returns
  
  List of analyzer modules that can handle the message.
  """
  def find_analyzers_for(message) when is_struct(message) do
    find_analyzers_for(message.__struct__)
  end
  
  def find_analyzers_for(message_type) when is_atom(message_type) do
    GenServer.call(__MODULE__, {:find_analyzers_for, message_type})
  end
  
  @doc """
  Finds the best analyzer for the given message based on priority.
  
  Returns the single highest-priority analyzer that can handle the message.
  
  ## Parameters
  
  - `message` - Typed message struct or message module
  
  ## Returns
  
  - `{:ok, analyzer}` - Best analyzer found
  - `{:error, :no_analyzer}` - No analyzer can handle this message
  """
  def find_best_analyzer_for(message) do
    case find_analyzers_for(message) do
      [] -> {:error, :no_analyzer}
      [best | _] -> {:ok, best}
    end
  end
  
  @doc """
  Finds analyzers by category.
  
  Categories are derived from analyzer metadata tags.
  
  ## Parameters
  
  - `category` - Category atom (e.g., `:code`, `:learning`, `:security`)
  
  ## Returns
  
  List of analyzer modules in the category.
  """
  def find_by_category(category) when is_atom(category) do
    GenServer.call(__MODULE__, {:find_by_category, category})
  end
  
  @doc """
  Returns all registered analyzers.
  """
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end
  
  @doc """
  Gets metadata for a specific analyzer.
  
  ## Parameters
  
  - `analyzer` - Analyzer module
  
  ## Returns
  
  - `{:ok, metadata}` - Analyzer metadata map
  - `{:error, :not_found}` - Analyzer not registered
  """
  def get_metadata(analyzer) when is_atom(analyzer) do
    case :ets.lookup(@metadata_table, analyzer) do
      [{^analyzer, metadata}] -> {:ok, metadata}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Returns health status of all registered analyzers.
  
  This performs a lightweight health check to ensure analyzers
  are available and functioning.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check, 10_000)
  end
  
  @doc """
  Validates that an analyzer implements the required behavior.
  
  ## Parameters
  
  - `analyzer` - Module to validate
  
  ## Returns
  
  - `:ok` - Analyzer is valid
  - `{:error, reason}` - Analyzer validation failed
  """
  def validate_analyzer(analyzer) when is_atom(analyzer) do
    try do
      # Check if module exists
      Code.ensure_loaded(analyzer)
      
      # Check required callbacks
      required_callbacks = [{:analyze, 2}, {:supported_types, 0}]
      
      missing_callbacks = 
        Enum.filter(required_callbacks, fn {fun, arity} ->
          not function_exported?(analyzer, fun, arity)
        end)
      
      if missing_callbacks == [] do
        # Validate supported_types returns valid list
        case analyzer.supported_types() do
          types when is_list(types) ->
            :ok
          _ ->
            {:error, :invalid_supported_types}
        end
      else
        {:error, {:missing_callbacks, missing_callbacks}}
      end
    rescue
      error ->
        {:error, {:validation_failed, error}}
    end
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS tables for fast lookups
    :ets.new(@registry_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@metadata_table, [:named_table, :set, :public, read_concurrency: true])
    
    # Register built-in analyzers if they exist
    register_built_in_analyzers()
    
    Logger.info("AnalyzerRegistry started")
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:register, analyzer}, _from, state) do
    case validate_analyzer(analyzer) do
      :ok ->
        register_analyzer(analyzer)
        {:reply, :ok, state}
      
      {:error, reason} ->
        Logger.warning("Failed to register analyzer #{analyzer}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:unregister, analyzer}, _from, state) do
    unregister_analyzer(analyzer)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:find_analyzers_for, message_type}, _from, state) do
    analyzers = find_analyzers_for_message_type(message_type)
    {:reply, analyzers, state}
  end
  
  @impl true
  def handle_call({:find_by_category, category}, _from, state) do
    analyzers = find_analyzers_by_category(category)
    {:reply, analyzers, state}
  end
  
  @impl true
  def handle_call(:list_all, _from, state) do
    analyzers = list_all_analyzers()
    {:reply, analyzers, state}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    health_status = perform_health_check()
    {:reply, health_status, state}
  end
  
  # Private Functions
  
  defp register_analyzer(analyzer) do
    try do
      # Get supported message types
      supported_types = analyzer.supported_types()
      
      # Get analyzer metadata
      metadata = get_analyzer_metadata(analyzer)
      
      # Register for each supported type
      Enum.each(supported_types, fn message_type ->
        key = message_type
        analyzers = get_analyzers_for_type(key)
        updated_analyzers = add_analyzer_by_priority(analyzers, analyzer, metadata.priority)
        :ets.insert(@registry_table, {key, updated_analyzers})
      end)
      
      # Cache metadata
      :ets.insert(@metadata_table, {analyzer, metadata})
      
      Logger.debug("Registered analyzer #{analyzer} for types: #{inspect(supported_types)}")
      
    rescue
      error ->
        Logger.error("Failed to register analyzer #{analyzer}: #{inspect(error)}")
        {:error, error}
    end
  end
  
  defp unregister_analyzer(analyzer) do
    # Remove from all message type registrations
    :ets.foldl(fn {message_type, analyzers}, _acc ->
      updated_analyzers = List.delete(analyzers, analyzer)
      :ets.insert(@registry_table, {message_type, updated_analyzers})
    end, nil, @registry_table)
    
    # Remove metadata
    :ets.delete(@metadata_table, analyzer)
    
    Logger.debug("Unregistered analyzer #{analyzer}")
  end
  
  defp find_analyzers_for_message_type(message_type) do
    case :ets.lookup(@registry_table, message_type) do
      [{^message_type, analyzers}] -> analyzers
      [] -> []
    end
  end
  
  defp find_analyzers_by_category(category) do
    :ets.foldl(fn {analyzer, metadata}, acc ->
      if category in Map.get(metadata, :categories, []) do
        [analyzer | acc]
      else
        acc
      end
    end, [], @metadata_table)
  end
  
  defp list_all_analyzers do
    :ets.foldl(fn {analyzer, _metadata}, acc ->
      [analyzer | acc]
    end, [], @metadata_table)
  end
  
  defp perform_health_check do
    analyzers = list_all_analyzers()
    
    results = 
      Enum.map(analyzers, fn analyzer ->
        health = check_analyzer_health(analyzer)
        {analyzer, health}
      end)
    
    %{
      total_analyzers: length(analyzers),
      healthy: Enum.count(results, fn {_, health} -> health == :healthy end),
      unhealthy: Enum.count(results, fn {_, health} -> health != :healthy end),
      details: results
    }
  end
  
  defp check_analyzer_health(analyzer) do
    try do
      # Check if module is available
      analyzer.supported_types()
      :healthy
    rescue
      _ -> :unhealthy
    end
  end
  
  defp get_analyzers_for_type(message_type) do
    case :ets.lookup(@registry_table, message_type) do
      [{^message_type, analyzers}] -> analyzers
      [] -> []
    end
  end
  
  defp add_analyzer_by_priority(analyzers, analyzer, priority) do
    # Remove if already present, then add by priority
    analyzers
    |> List.delete(analyzer)
    |> insert_by_priority(analyzer, priority)
  end
  
  defp insert_by_priority([], analyzer, _priority), do: [analyzer]
  defp insert_by_priority([first | rest], analyzer, priority) do
    first_priority = get_item_priority(first)
    
    if priority_value(priority) > priority_value(first_priority) do
      [analyzer, first | rest]
    else
      [first | insert_by_priority(rest, analyzer, priority)]
    end
  end
  
  defp get_item_priority({_analyzer, priority}), do: priority
  defp get_item_priority(analyzer) when is_atom(analyzer), do: :normal
  
  defp priority_value(:critical), do: 4
  defp priority_value(:high), do: 3  
  defp priority_value(:normal), do: 2
  defp priority_value(:low), do: 1
  defp priority_value(_), do: 2
  
  defp get_analyzer_metadata(analyzer) do
    base_metadata = %{
      name: to_string(analyzer),
      priority: get_analyzer_priority(analyzer),
      timeout: get_analyzer_timeout(analyzer),
      categories: derive_categories(analyzer)
    }
    
    # Merge with analyzer-provided metadata if available
    if function_exported?(analyzer, :metadata, 0) do
      Map.merge(base_metadata, analyzer.metadata())
    else
      base_metadata
    end
  end
  
  defp get_analyzer_priority(analyzer) do
    if function_exported?(analyzer, :priority, 0) do
      analyzer.priority()
    else
      :normal
    end
  end
  
  defp get_analyzer_timeout(analyzer) do
    if function_exported?(analyzer, :timeout, 0) do
      analyzer.timeout()
    else
      10_000
    end
  end
  
  defp derive_categories(analyzer) do
    # Derive categories from module path
    analyzer
    |> Module.split()
    |> Enum.drop_while(&(&1 != "Analyzers"))
    |> Enum.drop(1)  # Drop "Analyzers"
    |> Enum.take(1)  # Take category (e.g., "Code")
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.to_atom/1)
  end
  
  defp register_built_in_analyzers do
    # This will be expanded as we create analyzers
    built_in_analyzers = []
    
    Enum.each(built_in_analyzers, fn analyzer ->
      case validate_analyzer(analyzer) do
        :ok -> register_analyzer(analyzer)
        error -> Logger.warning("Failed to register built-in analyzer #{analyzer}: #{inspect(error)}")
      end
    end)
  end
end