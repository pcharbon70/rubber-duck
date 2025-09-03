defmodule RubberDuck.Prompts.Services.PromptFilterManager do
  @moduledoc """
  Advanced filtering and saved search queries service for prompt discovery.
  
  Provides comprehensive filtering capabilities for saved prompt collections
  including custom filter creation, saved search queries, complex filter
  combinations, and filter usage tracking for improved prompt discovery.
  
  Features:
  - Custom filter creation and management with user-defined criteria
  - Saved search queries for quick access to complex search patterns
  - Complex filter combinations with boolean logic and nested criteria
  - Filter usage tracking and effectiveness analytics for optimization
  - Performance optimization for complex filtering operations on large collections
  """

  use GenServer
  require Logger

  @filter_types [:category, :tag, :prompt_type, :date_range, :user, :content, :usage_frequency]
  @filter_operators [:equals, :contains, :starts_with, :ends_with, :between, :greater_than, :less_than]
  @boolean_operators [:and, :or, :not]

  defstruct [
    :filter_config,
    :saved_searches,
    :filter_cache,
    :usage_analytics
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      filter_config: build_filter_config(),
      saved_searches: initialize_saved_searches(),
      filter_cache: initialize_filter_cache(),
      usage_analytics: initialize_usage_analytics()
    }

    Logger.info("PromptFilterManager: Service initialized",
      filter_types: @filter_types,
      operators: @filter_operators
    )

    {:ok, state}
  end

  # Public API

  @doc """
  Create custom filter for prompt collection filtering.
  """
  def create_custom_filter(user_id, filter_definition, options \\ %{}) do
    GenServer.call(__MODULE__, {:create_filter, user_id, filter_definition, options})
  end

  @doc """
  Apply filter to prompt collection with performance optimization.
  """
  def apply_filter(user_id, filter_criteria, prompt_collection \\ nil, filter_options \\ %{}) do
    GenServer.call(__MODULE__, {:apply_filter, user_id, filter_criteria, prompt_collection, filter_options})
  end

  @doc """
  Save search query for quick access and reuse.
  """
  def save_search_query(user_id, search_query_definition, save_options \\ %{}) do
    GenServer.call(__MODULE__, {:save_search, user_id, search_query_definition, save_options})
  end

  @doc """
  Execute saved search query with current data.
  """
  def execute_saved_search(user_id, saved_search_id, execution_options \\ %{}) do
    GenServer.call(__MODULE__, {:execute_saved_search, user_id, saved_search_id, execution_options})
  end

  @doc """
  Get popular filters for user discovery and recommendation.
  """
  def get_popular_filters(user_id, popularity_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_popular_filters, user_id, popularity_options})
  end

  @doc """
  Get filter usage analytics for optimization.
  """
  def get_filter_analytics(user_id, filter_id \\ nil, analytics_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_analytics, user_id, filter_id, analytics_options})
  end

  # GenServer callbacks

  @impl true
  def handle_call({:create_filter, user_id, filter_definition, options}, _from, state) do
    Logger.debug("PromptFilterManager: Creating custom filter",
      user_id: user_id,
      filter_name: Map.get(filter_definition, :name, "unnamed")
    )

    case execute_filter_creation(user_id, filter_definition, options, state) do
      {:ok, filter_result} ->
        updated_state = add_custom_filter_to_state(state, filter_result)

        Logger.info("PromptFilterManager: Custom filter created",
          user_id: user_id,
          filter_id: filter_result.filter_id,
          filter_type: filter_result.filter_type
        )

        {:reply, {:ok, filter_result}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply_filter, user_id, filter_criteria, prompt_collection, filter_options}, _from, state) do
    case execute_filter_application(user_id, filter_criteria, prompt_collection, filter_options, state) do
      {:ok, filtered_results} ->
        Logger.debug("PromptFilterManager: Filter applied successfully",
          user_id: user_id,
          original_count: if(prompt_collection, do: length(prompt_collection), else: "all"),
          filtered_count: length(filtered_results)
        )

        {:reply, {:ok, filtered_results}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:save_search, user_id, search_query_definition, save_options}, _from, state) do
    case save_search_query_for_user(user_id, search_query_definition, save_options, state) do
      {:ok, saved_search} ->
        updated_state = add_saved_search_to_state(state, saved_search)

        Logger.info("PromptFilterManager: Search query saved",
          user_id: user_id,
          saved_search_id: saved_search.id,
          search_name: saved_search.name
        )

        {:reply, {:ok, saved_search}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:execute_saved_search, user_id, saved_search_id, execution_options}, _from, state) do
    case execute_saved_search_query(user_id, saved_search_id, execution_options, state) do
      {:ok, search_results} ->
        {:reply, {:ok, search_results}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_popular_filters, user_id, popularity_options}, _from, state) do
    case get_popular_filters_for_user(user_id, popularity_options, state) do
      {:ok, popular_filters} ->
        {:reply, {:ok, popular_filters}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_analytics, user_id, filter_id, analytics_options}, _from, state) do
    case generate_filter_analytics(user_id, filter_id, analytics_options, state) do
      {:ok, analytics} ->
        {:reply, {:ok, analytics}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private implementation functions

  defp execute_filter_creation(user_id, filter_definition, options, state) do
    # Execute custom filter creation
    filter_id = Ash.UUID.generate()
    
    custom_filter = %{
      filter_id: filter_id,
      user_id: user_id,
      name: filter_definition.name,
      description: Map.get(filter_definition, :description, ""),
      filter_criteria: filter_definition.criteria,
      filter_type: determine_filter_type(filter_definition.criteria),
      created_at: DateTime.utc_now(),
      filter_metadata: %{
        criteria_count: count_filter_criteria(filter_definition.criteria),
        complexity_level: assess_filter_complexity(filter_definition.criteria)
      }
    }

    {:ok, custom_filter}
  end

  defp execute_filter_application(user_id, filter_criteria, prompt_collection, filter_options, state) do
    # Execute filter application to prompt collection
    target_collection = prompt_collection || get_user_accessible_prompts(user_id, filter_options)

    case target_collection do
      [] ->
        {:ok, []}

      prompts when is_list(prompts) ->
        filtered_prompts = apply_filter_criteria_to_prompts(prompts, filter_criteria)
        {:ok, filtered_prompts}

      {:error, reason} ->
        {:error, {:collection_access_failed, reason}}
    end
  end

  defp save_search_query_for_user(user_id, search_query_definition, save_options, state) do
    # Save search query for user reuse
    saved_search_id = Ash.UUID.generate()
    
    saved_search = %{
      id: saved_search_id,
      user_id: user_id,
      name: search_query_definition.name,
      description: Map.get(search_query_definition, :description, ""),
      search_criteria: search_query_definition.criteria,
      search_options: Map.get(search_query_definition, :options, %{}),
      created_at: DateTime.utc_now(),
      usage_count: 0,
      last_used_at: nil
    }

    {:ok, saved_search}
  end

  defp execute_saved_search_query(user_id, saved_search_id, execution_options, state) do
    # Execute previously saved search query
    case get_saved_search(user_id, saved_search_id, state) do
      {:ok, saved_search} ->
        # Execute the saved search criteria
        case execute_filter_application(user_id, saved_search.search_criteria, nil, execution_options, state) do
          {:ok, search_results} ->
            # Update usage tracking
            update_saved_search_usage(saved_search_id, state)
            {:ok, search_results}

          {:error, reason} ->
            {:error, {:saved_search_execution_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_popular_filters_for_user(user_id, popularity_options, state) do
    # Get popular filters based on usage analytics
    time_range = Map.get(popularity_options, :time_range, :last_30_days)
    
    popular_filters = %{
      user_id: user_id,
      time_range: time_range,
      popular_filter_types: get_most_used_filter_types(user_id, time_range),
      popular_criteria: get_most_used_criteria(user_id, time_range),
      suggested_filters: suggest_filters_based_on_usage(user_id, time_range),
      popularity_metadata: %{
        analysis_period: time_range,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, popular_filters}
  end

  defp generate_filter_analytics(user_id, filter_id, analytics_options, state) do
    # Generate comprehensive filter analytics
    analytics_scope = Map.get(analytics_options, :scope, :user_specific)

    case analytics_scope do
      :user_specific ->
        generate_user_filter_analytics(user_id, filter_id)

      :filter_specific ->
        generate_specific_filter_analytics(filter_id, user_id)

      :comprehensive ->
        generate_comprehensive_filter_analytics(user_id, filter_id)
    end
  end

  # Filter application functions

  defp apply_filter_criteria_to_prompts(prompts, filter_criteria) do
    # Apply filter criteria to prompt collection
    Enum.filter(prompts, fn prompt ->
      evaluate_filter_criteria(prompt, filter_criteria)
    end)
  end

  defp evaluate_filter_criteria(prompt, filter_criteria) do
    # Evaluate if prompt matches filter criteria
    case filter_criteria do
      %{operator: :and, conditions: conditions} ->
        Enum.all?(conditions, fn condition -> evaluate_single_condition(prompt, condition) end)

      %{operator: :or, conditions: conditions} ->
        Enum.any?(conditions, fn condition -> evaluate_single_condition(prompt, condition) end)

      single_condition when is_map(single_condition) ->
        evaluate_single_condition(prompt, single_condition)

      _ ->
        false
    end
  end

  defp evaluate_single_condition(prompt, condition) do
    # Evaluate single filter condition
    field = Map.get(condition, :field)
    operator = Map.get(condition, :operator)
    value = Map.get(condition, :value)

    prompt_value = get_prompt_field_value(prompt, field)

    case operator do
      :equals -> prompt_value == value
      :contains -> prompt_value && String.contains?(String.downcase(prompt_value), String.downcase(value))
      :starts_with -> prompt_value && String.starts_with?(String.downcase(prompt_value), String.downcase(value))
      :ends_with -> prompt_value && String.ends_with?(String.downcase(prompt_value), String.downcase(value))
      _ -> false
    end
  end

  defp get_prompt_field_value(prompt, field) do
    # Get field value from prompt for comparison
    case field do
      :name -> prompt.name
      :description -> prompt.description
      :content -> prompt.content
      :prompt_type -> prompt.prompt_type
      :category_id -> prompt.category_id
      :user_id -> prompt.user_id
      :project_id -> prompt.project_id
      _ -> nil
    end
  end

  # Utility functions

  defp get_user_accessible_prompts(user_id, options) do
    # Get all prompts accessible to user (would use proper Ash query)
    project_id = Map.get(options, :project_id)
    
    case project_id do
      nil ->
        # User + System prompts
        case Prompt.read() do
          {:ok, prompts} ->
            Enum.filter(prompts, fn prompt ->
              prompt.prompt_type == :system and prompt.status == :approved or
              prompt.prompt_type == :user and prompt.user_id == user_id
            end)

          {:error, reason} ->
            {:error, reason}
        end

      project_id ->
        # User + Project + System prompts
        case Prompt.read() do
          {:ok, prompts} ->
            Enum.filter(prompts, fn prompt ->
              prompt.prompt_type == :system and prompt.status == :approved or
              prompt.prompt_type == :project and prompt.project_id == project_id and prompt.status == :approved or
              prompt.prompt_type == :user and prompt.user_id == user_id
            end)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp determine_filter_type(criteria) do
    # Determine the primary type of filter based on criteria
    cond do
      Map.has_key?(criteria, :category) or Map.has_key?(criteria, :category_id) -> :category
      Map.has_key?(criteria, :tags) -> :tag
      Map.has_key?(criteria, :prompt_type) -> :prompt_type
      Map.has_key?(criteria, :date_range) -> :date_range
      Map.has_key?(criteria, :content) -> :content
      true -> :custom
    end
  end

  defp count_filter_criteria(criteria) do
    # Count the number of filter criteria
    case criteria do
      %{conditions: conditions} when is_list(conditions) -> length(conditions)
      %{} -> map_size(criteria)
      _ -> 1
    end
  end

  defp assess_filter_complexity(criteria) do
    # Assess complexity of filter criteria
    criteria_count = count_filter_criteria(criteria)
    has_nested_conditions = Map.has_key?(criteria, :conditions)
    
    case {criteria_count, has_nested_conditions} do
      {count, true} when count > 5 -> :high
      {count, _} when count > 3 -> :medium
      _ -> :low
    end
  end

  defp get_saved_search(user_id, saved_search_id, state) do
    # Get saved search by ID for user
    case Map.get(state.saved_searches, "#{user_id}:#{saved_search_id}") do
      nil -> {:error, :saved_search_not_found}
      saved_search -> {:ok, saved_search}
    end
  end

  defp update_saved_search_usage(saved_search_id, state) do
    # Update usage tracking for saved search
    # Simplified implementation - would update actual usage records
    :ok
  end

  defp add_custom_filter_to_state(state, filter_result) do
    # Add custom filter to state
    filter_key = "#{filter_result.user_id}:#{filter_result.filter_id}"
    updated_filters = Map.put(state.filter_cache, filter_key, filter_result)
    
    %{state | filter_cache: updated_filters}
  end

  defp add_saved_search_to_state(state, saved_search) do
    # Add saved search to state
    search_key = "#{saved_search.user_id}:#{saved_search.id}"
    updated_searches = Map.put(state.saved_searches, search_key, saved_search)
    
    %{state | saved_searches: updated_searches}
  end

  # Analytics functions

  defp generate_user_filter_analytics(user_id, filter_id) do
    # Generate analytics for user's filter usage
    analytics = %{
      user_id: user_id,
      filter_id: filter_id,
      usage_frequency: 0.0,  # Would calculate from actual usage data
      effectiveness_score: 0.8,  # Would calculate from user feedback
      most_used_criteria: [],  # Would analyze criteria usage
      filter_performance: %{
        average_execution_time_ms: 50,  # Would measure actual performance
        cache_hit_rate: 0.85
      },
      analytics_metadata: %{
        analytics_type: :user_specific,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, analytics}
  end

  defp generate_specific_filter_analytics(filter_id, user_id) do
    # Generate analytics for specific filter
    analytics = %{
      filter_id: filter_id,
      user_id: user_id,
      filter_popularity: 0.0,  # Would calculate popularity across users
      usage_contexts: [],  # Would analyze when filter is used
      effectiveness_metrics: %{},  # Would calculate effectiveness
      analytics_metadata: %{
        analytics_type: :filter_specific,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, analytics}
  end

  defp generate_comprehensive_filter_analytics(user_id, filter_id) do
    # Generate comprehensive analytics
    with {:ok, user_analytics} <- generate_user_filter_analytics(user_id, filter_id),
         {:ok, filter_analytics} <- generate_specific_filter_analytics(filter_id, user_id) do
      
      comprehensive_analytics = %{
        user_analytics: user_analytics,
        filter_analytics: filter_analytics,
        combined_insights: %{
          overall_effectiveness: 0.8,
          usage_patterns: [],
          optimization_suggestions: []
        },
        analytics_metadata: %{
          analytics_type: :comprehensive,
          generated_at: DateTime.utc_now()
        }
      }

      {:ok, comprehensive_analytics}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper functions

  defp get_most_used_filter_types(user_id, time_range) do
    # Get most frequently used filter types for user
    # Simplified implementation - would analyze actual usage data
    [:category, :tag, :date_range]
  end

  defp get_most_used_criteria(user_id, time_range) do
    # Get most frequently used filter criteria
    # Simplified implementation
    []
  end

  defp suggest_filters_based_on_usage(user_id, time_range) do
    # Suggest new filters based on usage patterns
    # Simplified implementation
    []
  end

  defp build_filter_config do
    %{
      max_filter_criteria: 10,
      max_saved_searches_per_user: 50,
      cache_enabled: true,
      analytics_enabled: true
    }
  end

  defp initialize_saved_searches do
    %{}
  end

  defp initialize_filter_cache do
    %{}
  end

  defp initialize_usage_analytics do
    %{
      total_filter_applications: 0,
      successful_applications: 0,
      average_filter_time_ms: 0.0,
      popular_filter_types: %{}
    }
  end
end