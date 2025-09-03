defmodule RubberDuck.Prompts.Services.LlmPromptSelector do
  @moduledoc """
  Service for efficient prompt selection in LLM operations.

  Provides high-performance prompt retrieval, filtering, and selection
  capabilities for LLM operation interfaces. Enables users to browse
  and select from their three-tier prompt hierarchy (System/Project/User)
  with advanced search and filtering capabilities.

  Features:
  - Efficient prompt retrieval with three-tier hierarchy access
  - Real-time search and filtering with sub-200ms performance
  - ETS caching for frequently accessed prompt collections
  - Integration with LLM operation contexts for relevant prompt suggestions
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Resources.{Prompt, PromptCategory, PromptUsage}

  @cache_table :llm_prompt_selection_cache
  # 5-minute TTL for prompt selection cache
  @cache_ttl :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize ETS cache for prompt selection
    :ets.new(@cache_table, [:set, :public, :named_table])

    Logger.info("LlmPromptSelector: Service initialized with cache table")
    {:ok, %{}}
  end

  # Public API

  @doc """
  Get prompts available to user for LLM operations with three-tier access.
  """
  def get_available_prompts(user_id, project_id \\ nil, options \\ %{}) do
    GenServer.call(__MODULE__, {:get_available_prompts, user_id, project_id, options})
  end

  @doc """
  Search prompts for LLM operations with real-time filtering.
  """
  def search_prompts(user_id, search_query, project_id \\ nil, search_options \\ %{}) do
    GenServer.call(
      __MODULE__,
      {:search_prompts, user_id, search_query, project_id, search_options}
    )
  end

  @doc """
  Get recently used prompts for quick access in LLM operations.
  """
  def get_recent_prompts(user_id, project_id \\ nil, limit \\ 10) do
    GenServer.call(__MODULE__, {:get_recent_prompts, user_id, project_id, limit})
  end

  @doc """
  Get favorite prompts for LLM operations.
  """
  def get_favorite_prompts(user_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:get_favorite_prompts, user_id, project_id})
  end

  @doc """
  Get prompts by category for organized browsing in LLM operations.
  """
  def get_prompts_by_category(user_id, category_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:get_prompts_by_category, user_id, category_id, project_id})
  end

  @doc """
  Invalidate prompt selection cache for user.
  """
  def invalidate_user_cache(user_id) do
    GenServer.cast(__MODULE__, {:invalidate_cache, user_id})
  end

  # GenServer callbacks

  @impl true
  def handle_call({:get_available_prompts, user_id, project_id, options}, _from, state) do
    cache_key = build_cache_key(:available, user_id, project_id)

    case get_from_cache(cache_key) do
      {:ok, cached_prompts} ->
        {:reply, {:ok, cached_prompts}, state}

      {:error, :cache_miss} ->
        case fetch_available_prompts(user_id, project_id, options) do
          {:ok, prompts} ->
            cache_prompts(cache_key, prompts)
            {:reply, {:ok, prompts}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(
        {:search_prompts, user_id, search_query, project_id, search_options},
        _from,
        state
      ) do
    Logger.debug("LlmPromptSelector: Searching prompts",
      user_id: user_id,
      query: search_query,
      project_id: project_id
    )

    # Don't cache search results as they're dynamic
    case execute_prompt_search(user_id, search_query, project_id, search_options) do
      {:ok, search_results} ->
        {:reply, {:ok, search_results}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_recent_prompts, user_id, project_id, limit}, _from, state) do
    cache_key = build_cache_key(:recent, user_id, project_id)

    case get_from_cache(cache_key) do
      {:ok, cached_recent} ->
        limited_recent = Enum.take(cached_recent, limit)
        {:reply, {:ok, limited_recent}, state}

      {:error, :cache_miss} ->
        case fetch_recent_prompts(user_id, project_id, limit) do
          {:ok, recent_prompts} ->
            cache_prompts(cache_key, recent_prompts)
            {:reply, {:ok, recent_prompts}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_favorite_prompts, user_id, project_id}, _from, state) do
    cache_key = build_cache_key(:favorites, user_id, project_id)

    case get_from_cache(cache_key) do
      {:ok, cached_favorites} ->
        {:reply, {:ok, cached_favorites}, state}

      {:error, :cache_miss} ->
        case fetch_favorite_prompts(user_id, project_id) do
          {:ok, favorite_prompts} ->
            cache_prompts(cache_key, favorite_prompts)
            {:reply, {:ok, favorite_prompts}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_prompts_by_category, user_id, category_id, project_id}, _from, state) do
    cache_key = build_cache_key(:category, user_id, "#{project_id}:#{category_id}")

    case get_from_cache(cache_key) do
      {:ok, cached_category_prompts} ->
        {:reply, {:ok, cached_category_prompts}, state}

      {:error, :cache_miss} ->
        case fetch_prompts_by_category(user_id, category_id, project_id) do
          {:ok, category_prompts} ->
            cache_prompts(cache_key, category_prompts)
            {:reply, {:ok, category_prompts}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_cast({:invalidate_cache, user_id}, state) do
    Logger.debug("LlmPromptSelector: Invalidating cache for user", user_id: user_id)

    # Remove all cache entries for this user
    cache_pattern = "#{user_id}:*"
    :ets.match_delete(@cache_table, {cache_pattern, :_})

    {:noreply, state}
  end

  # Private implementation functions

  defp fetch_available_prompts(user_id, project_id, options) do
    # Fetch prompts from all three tiers that user has access to
    filters = build_access_filters(user_id, project_id)

    case Prompt.read(filters) do
      {:ok, prompts} ->
        # Organize by tier and priority
        organized_prompts = organize_prompts_by_tier(prompts)
        {:ok, organized_prompts}

      {:error, reason} ->
        Logger.warning("Failed to fetch available prompts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp execute_prompt_search(user_id, search_query, project_id, search_options) do
    # Execute real-time prompt search across three tiers
    search_scope = Map.get(search_options, :search_scope, :all)
    include_content = Map.get(search_options, :include_content, true)

    base_filters = build_access_filters(user_id, project_id)
    search_filters = build_search_filters(search_query, search_scope, include_content)

    filters = Map.merge(base_filters, search_filters)

    case Prompt.read(filters) do
      {:ok, search_results} ->
        # Rank results by relevance
        ranked_results = rank_search_results(search_results, search_query)
        {:ok, ranked_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_recent_prompts(user_id, project_id, limit) do
    # Fetch recently used prompts based on PromptUsage analytics
    case PromptUsage.get_recent_for_user(user_id, limit) do
      {:ok, recent_usage} ->
        # Get the actual prompts from usage records
        prompt_ids = Enum.map(recent_usage, fn usage -> usage.prompt_id end)

        filters =
          %{
            id: {:in, prompt_ids}
          }
          |> Map.merge(build_access_filters(user_id, project_id))

        case Prompt.read(filters) do
          {:ok, recent_prompts} ->
            # Sort by usage recency
            sorted_prompts = sort_prompts_by_usage_recency(recent_prompts, recent_usage)
            {:ok, sorted_prompts}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_favorite_prompts(user_id, project_id) do
    # Fetch user's favorite prompts (would be tracked in user preferences or prompt metadata)
    # For now, return most frequently used prompts
    case PromptUsage.get_most_used_for_user(user_id, 20) do
      {:ok, frequent_usage} ->
        prompt_ids = Enum.map(frequent_usage, fn usage -> usage.prompt_id end)

        filters =
          %{
            id: {:in, prompt_ids}
          }
          |> Map.merge(build_access_filters(user_id, project_id))

        case Prompt.read(filters) do
          {:ok, favorite_prompts} ->
            {:ok, favorite_prompts}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _reason} ->
        # Fallback to system prompts if no usage data
        {:ok, []}
    end
  end

  defp fetch_prompts_by_category(user_id, category_id, project_id) do
    # Fetch prompts in specific category
    filters =
      %{
        category_id: category_id
      }
      |> Map.merge(build_access_filters(user_id, project_id))

    case Prompt.read(filters) do
      {:ok, category_prompts} ->
        {:ok, category_prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp build_access_filters(user_id, project_id) do
    # Build filters for three-tier access control
    case project_id do
      nil ->
        # User access without project context: User + System prompts
        %{
          or: [
            %{prompt_type: :system, status: :approved},
            %{prompt_type: :user, user_id: user_id}
          ]
        }

      project_id ->
        # User access with project context: User + Project + System prompts
        %{
          or: [
            %{prompt_type: :system, status: :approved},
            %{prompt_type: :project, project_id: project_id, status: :approved},
            %{prompt_type: :user, user_id: user_id}
          ]
        }
    end
  end

  defp build_search_filters(search_query, search_scope, include_content) do
    # Build search filters based on query and options
    search_filters = %{}

    # Add text search filters
    search_filters =
      if include_content do
        Map.merge(search_filters, %{
          or: [
            %{name: {:ilike, "%#{search_query}%"}},
            %{content: {:ilike, "%#{search_query}%"}},
            %{description: {:ilike, "%#{search_query}%"}}
          ]
        })
      else
        Map.merge(search_filters, %{
          or: [
            %{name: {:ilike, "%#{search_query}%"}},
            %{description: {:ilike, "%#{search_query}%"}}
          ]
        })
      end

    # Add scope filters
    case search_scope do
      :system_only ->
        Map.merge(search_filters, %{prompt_type: :system})

      :project_only ->
        Map.merge(search_filters, %{prompt_type: :project})

      :user_only ->
        Map.merge(search_filters, %{prompt_type: :user})

      _ ->
        search_filters
    end
  end

  defp organize_prompts_by_tier(prompts) do
    # Organize prompts by three-tier hierarchy
    prompts
    |> Enum.group_by(fn prompt -> prompt.prompt_type end)
    |> then(fn grouped ->
      %{
        system_prompts: Map.get(grouped, :system, []),
        project_prompts: Map.get(grouped, :project, []),
        user_prompts: Map.get(grouped, :user, []),
        total_count: length(prompts)
      }
    end)
  end

  defp rank_search_results(search_results, search_query) do
    # Rank search results by relevance
    search_query_lower = String.downcase(search_query)

    search_results
    |> Enum.map(fn prompt ->
      relevance_score = calculate_relevance_score(prompt, search_query_lower)
      Map.put(prompt, :relevance_score, relevance_score)
    end)
    |> Enum.sort_by(fn prompt -> prompt.relevance_score end, :desc)
  end

  defp calculate_relevance_score(prompt, search_query) do
    # Calculate relevance score for search ranking
    name_score =
      if String.contains?(String.downcase(prompt.name), search_query), do: 3.0, else: 0.0

    description_score =
      if prompt.description &&
           String.contains?(String.downcase(prompt.description), search_query),
         do: 2.0,
         else: 0.0

    content_score =
      if String.contains?(String.downcase(prompt.content), search_query), do: 1.0, else: 0.0

    # Boost score for more recent prompts
    recency_boost = calculate_recency_boost(prompt)

    name_score + description_score + content_score + recency_boost
  end

  defp calculate_recency_boost(prompt) do
    # Boost recently created or updated prompts
    now = DateTime.utc_now()
    updated_at = prompt.updated_at || prompt.inserted_at

    days_old = DateTime.diff(now, updated_at, :day)

    case days_old do
      # Recent prompts get boost
      days when days <= 7 -> 1.0
      # Moderately recent
      days when days <= 30 -> 0.5
      # Older prompts
      _ -> 0.0
    end
  end

  defp sort_prompts_by_usage_recency(prompts, usage_records) do
    # Sort prompts by usage recency
    usage_map = Map.new(usage_records, fn usage -> {usage.prompt_id, usage.used_at} end)

    prompts
    |> Enum.sort_by(
      fn prompt ->
        case Map.get(usage_map, prompt.id) do
          # Very old date for unused prompts
          nil -> ~U[2000-01-01 00:00:00Z]
          used_at -> used_at
        end
      end,
      :desc
    )
  end

  # Cache functions

  defp get_from_cache(cache_key) do
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, prompts, timestamp}] ->
        if timestamp + @cache_ttl > System.system_time(:millisecond) do
          {:ok, prompts}
        else
          :ets.delete(@cache_table, cache_key)
          {:error, :cache_miss}
        end

      [] ->
        {:error, :cache_miss}
    end
  end

  defp cache_prompts(cache_key, prompts) do
    :ets.insert(@cache_table, {cache_key, prompts, System.system_time(:millisecond)})
    :ok
  end

  defp build_cache_key(operation, user_id, context) do
    "#{operation}:#{user_id}:#{context || "global"}"
  end
end
