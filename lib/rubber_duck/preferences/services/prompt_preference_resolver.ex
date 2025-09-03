defmodule RubberDuck.Preferences.Services.PromptPreferenceResolver do
  @moduledoc """
  Service for resolving prompt management preferences with high-performance caching.
  
  Provides specialized preference resolution for prompt management interface customization,
  integrating with the Phase 1A user preference system to enable personalized prompt
  library organization, display modes, search behavior, and workflow optimization.
  
  Features:
  - Integration with Phase 1A preference hierarchy (System → User → Project)
  - High-performance ETS caching for sub-100ms preference resolution
  - Intelligent defaults for prompt management interface customization
  - Real-time preference updates with automatic cache invalidation
  """

  use GenServer
  require Logger

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Resources.{SystemDefault, UserPreference}

  @cache_table :prompt_preference_cache
  @cache_ttl :timer.minutes(15)  # 15-minute cache TTL

  @prompt_preference_keys %{
    display: [
      "prompt_management.display.view_mode",
      "prompt_management.display.sort_by", 
      "prompt_management.display.sort_direction",
      "prompt_management.display.items_per_page",
      "prompt_management.display.show_metadata",
      "prompt_management.display.color_coding"
    ],
    organization: [
      "prompt_management.organization.categorization_scheme",
      "prompt_management.organization.auto_categorization",
      "prompt_management.organization.custom_categories",
      "prompt_management.organization.hierarchy_depth"
    ],
    search: [
      "prompt_management.search.default_scope",
      "prompt_management.search.fuzzy_search",
      "prompt_management.search.include_content",
      "prompt_management.search.quick_filters"
    ],
    workflow: [
      "prompt_management.workflow.quick_access_prompts",
      "prompt_management.workflow.favorite_categories",
      "prompt_management.workflow.recent_limit",
      "prompt_management.workflow.shortcuts"
    ]
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize ETS cache for prompt preferences
    :ets.new(@cache_table, [:set, :public, :named_table])
    
    # Subscribe to preference change events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "preference_changes")
    
    Logger.info("PromptPreferenceResolver: Service initialized with cache table")
    {:ok, %{}}
  end

  # Public API

  @doc """
  Resolve display preferences for user's prompt management interface.
  """
  def resolve_display_preferences(user_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:resolve_display_preferences, user_id, project_id})
  end

  @doc """
  Resolve organization preferences for user's prompt library.
  """
  def resolve_organization_preferences(user_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:resolve_organization_preferences, user_id, project_id})
  end

  @doc """
  Resolve search preferences for prompt discovery.
  """
  def resolve_search_preferences(user_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:resolve_search_preferences, user_id, project_id})
  end

  @doc """
  Resolve workflow preferences for prompt access optimization.
  """
  def resolve_workflow_preferences(user_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:resolve_workflow_preferences, user_id, project_id})
  end

  @doc """
  Resolve all prompt management preferences efficiently in one call.
  """
  def resolve_all_prompt_management_preferences(user_id, project_id \\ nil) do
    GenServer.call(__MODULE__, {:resolve_all_preferences, user_id, project_id})
  end

  @doc """
  Invalidate prompt preference cache for user.
  """
  def invalidate_user_cache(user_id) do
    GenServer.cast(__MODULE__, {:invalidate_user_cache, user_id})
  end

  # GenServer callbacks

  @impl true
  def handle_call({:resolve_display_preferences, user_id, project_id}, _from, state) do
    cache_key = build_cache_key(:display, user_id, project_id)
    
    case get_from_cache(cache_key) do
      {:ok, cached_preferences} ->
        {:reply, {:ok, cached_preferences}, state}

      {:error, :cache_miss} ->
        case resolve_preference_category(:display, user_id, project_id) do
          {:ok, display_prefs} ->
            cache_preferences(cache_key, display_prefs)
            {:reply, {:ok, display_prefs}, state}

          {:error, reason} ->
            # Return intelligent defaults if preference resolution fails
            defaults = build_intelligent_display_defaults(user_id)
            cache_preferences(cache_key, defaults)
            {:reply, {:ok, defaults}, state}
        end
    end
  end

  @impl true
  def handle_call({:resolve_organization_preferences, user_id, project_id}, _from, state) do
    cache_key = build_cache_key(:organization, user_id, project_id)
    
    case get_from_cache(cache_key) do
      {:ok, cached_preferences} ->
        {:reply, {:ok, cached_preferences}, state}

      {:error, :cache_miss} ->
        case resolve_preference_category(:organization, user_id, project_id) do
          {:ok, org_prefs} ->
            cache_preferences(cache_key, org_prefs)
            {:reply, {:ok, org_prefs}, state}

          {:error, reason} ->
            defaults = build_intelligent_organization_defaults(user_id)
            cache_preferences(cache_key, defaults)
            {:reply, {:ok, defaults}, state}
        end
    end
  end

  @impl true
  def handle_call({:resolve_search_preferences, user_id, project_id}, _from, state) do
    cache_key = build_cache_key(:search, user_id, project_id)
    
    case get_from_cache(cache_key) do
      {:ok, cached_preferences} ->
        {:reply, {:ok, cached_preferences}, state}

      {:error, :cache_miss} ->
        case resolve_preference_category(:search, user_id, project_id) do
          {:ok, search_prefs} ->
            cache_preferences(cache_key, search_prefs)
            {:reply, {:ok, search_prefs}, state}

          {:error, reason} ->
            defaults = build_intelligent_search_defaults(user_id)
            cache_preferences(cache_key, defaults)
            {:reply, {:ok, defaults}, state}
        end
    end
  end

  @impl true
  def handle_call({:resolve_workflow_preferences, user_id, project_id}, _from, state) do
    cache_key = build_cache_key(:workflow, user_id, project_id)
    
    case get_from_cache(cache_key) do
      {:ok, cached_preferences} ->
        {:reply, {:ok, cached_preferences}, state}

      {:error, :cache_miss} ->
        case resolve_preference_category(:workflow, user_id, project_id) do
          {:ok, workflow_prefs} ->
            cache_preferences(cache_key, workflow_prefs)
            {:reply, {:ok, workflow_prefs}, state}

          {:error, reason} ->
            defaults = build_intelligent_workflow_defaults(user_id)
            cache_preferences(cache_key, defaults)
            {:reply, {:ok, defaults}, state}
        end
    end
  end

  @impl true
  def handle_call({:resolve_all_preferences, user_id, project_id}, _from, state) do
    with {:ok, display_prefs} <- resolve_display_preferences(user_id, project_id),
         {:ok, org_prefs} <- resolve_organization_preferences(user_id, project_id),
         {:ok, search_prefs} <- resolve_search_preferences(user_id, project_id),
         {:ok, workflow_prefs} <- resolve_workflow_preferences(user_id, project_id) do
      
      all_preferences = %{
        display: display_prefs,
        organization: org_prefs,
        search: search_prefs,
        workflow: workflow_prefs,
        resolved_at: DateTime.utc_now()
      }

      {:reply, {:ok, all_preferences}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:invalidate_user_cache, user_id}, state) do
    Logger.debug("PromptPreferenceResolver: Invalidating cache for user", user_id: user_id)
    
    # Remove all cache entries for this user
    :ets.match_delete(@cache_table, {"*:#{user_id}:*", :_})
    
    {:noreply, state}
  end

  @impl true
  def handle_info({:preference_changed, user_id, preference_key, project_id}, state) do
    # Invalidate specific preference cache when preferences change
    category = determine_preference_category(preference_key)
    
    if category do
      cache_key = build_cache_key(category, user_id, project_id)
      :ets.delete(@cache_table, cache_key)
      
      Logger.debug("PromptPreferenceResolver: Cache invalidated for preference change",
        user_id: user_id,
        preference_key: preference_key,
        category: category
      )
    end

    {:noreply, state}
  end

  # Private implementation functions

  defp resolve_preference_category(category, user_id, project_id) do
    # Resolve preferences for specific category using Phase 1A infrastructure
    preference_keys = Map.get(@prompt_preference_keys, category, [])
    
    case PreferenceResolver.resolve_batch(user_id, preference_keys, project_id) do
      resolved_map when is_map(resolved_map) ->
        # Organize resolved preferences into structured format
        structured_prefs = structure_preferences_for_category(category, resolved_map)
        {:ok, structured_prefs}

      error ->
        Logger.warning("Failed to resolve #{category} preferences for user #{user_id}: #{inspect(error)}")
        {:error, {:preference_resolution_failed, category, error}}
    end
  end

  defp structure_preferences_for_category(category, resolved_map) do
    # Structure resolved preferences based on category
    case category do
      :display ->
        %{
          view_mode: Map.get(resolved_map, "prompt_management.display.view_mode", "list"),
          sort_by: Map.get(resolved_map, "prompt_management.display.sort_by", "name"),
          sort_direction: Map.get(resolved_map, "prompt_management.display.sort_direction", "asc"),
          items_per_page: Map.get(resolved_map, "prompt_management.display.items_per_page", 25),
          show_metadata: Map.get(resolved_map, "prompt_management.display.show_metadata", true),
          color_coding: parse_json_preference(Map.get(resolved_map, "prompt_management.display.color_coding", "{}"))
        }

      :organization ->
        %{
          categorization_scheme: Map.get(resolved_map, "prompt_management.organization.categorization_scheme", "hierarchical"),
          auto_categorization: Map.get(resolved_map, "prompt_management.organization.auto_categorization", true),
          custom_categories: parse_json_preference(Map.get(resolved_map, "prompt_management.organization.custom_categories", "[]")),
          hierarchy_depth: Map.get(resolved_map, "prompt_management.organization.hierarchy_depth", 3)
        }

      :search ->
        %{
          default_scope: Map.get(resolved_map, "prompt_management.search.default_scope", "all"),
          fuzzy_search: Map.get(resolved_map, "prompt_management.search.fuzzy_search", true),
          include_content: Map.get(resolved_map, "prompt_management.search.include_content", true),
          quick_filters: parse_json_preference(Map.get(resolved_map, "prompt_management.search.quick_filters", "[\"recent\", \"favorites\"]"))
        }

      :workflow ->
        %{
          quick_access_prompts: parse_json_preference(Map.get(resolved_map, "prompt_management.workflow.quick_access_prompts", "[]")),
          favorite_categories: parse_json_preference(Map.get(resolved_map, "prompt_management.workflow.favorite_categories", "[]")),
          recent_limit: Map.get(resolved_map, "prompt_management.workflow.recent_limit", 10),
          shortcuts: parse_json_preference(Map.get(resolved_map, "prompt_management.workflow.shortcuts", "{}"))
        }
    end
  end

  # Cache functions

  defp get_from_cache(cache_key) do
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, preferences, timestamp}] ->
        if timestamp + @cache_ttl > System.system_time(:millisecond) do
          {:ok, preferences}
        else
          :ets.delete(@cache_table, cache_key)
          {:error, :cache_miss}
        end

      [] ->
        {:error, :cache_miss}
    end
  end

  defp cache_preferences(cache_key, preferences) do
    :ets.insert(@cache_table, {cache_key, preferences, System.system_time(:millisecond)})
    :ok
  end

  defp build_cache_key(category, user_id, project_id) do
    "#{category}:#{user_id}:#{project_id || "global"}"
  end

  # Intelligent defaults

  defp build_intelligent_display_defaults(user_id) do
    # Build intelligent display defaults based on user characteristics
    user_type = determine_user_type(user_id)
    
    case user_type do
      :power_user ->
        %{
          view_mode: "compact",
          sort_by: "usage_count",
          sort_direction: "desc",
          items_per_page: 50,
          show_metadata: true,
          color_coding: %{}
        }

      :casual_user ->
        %{
          view_mode: "cards",
          sort_by: "name",
          sort_direction: "asc",
          items_per_page: 20,
          show_metadata: true,
          color_coding: %{}
        }

      _ ->
        %{
          view_mode: "list",
          sort_by: "created_at",
          sort_direction: "desc",
          items_per_page: 25,
          show_metadata: true,
          color_coding: %{}
        }
    end
  end

  defp build_intelligent_organization_defaults(user_id) do
    # Build intelligent organization defaults
    user_type = determine_user_type(user_id)
    
    case user_type do
      :power_user ->
        %{
          categorization_scheme: "tag_based",
          auto_categorization: true,
          custom_categories: [],
          hierarchy_depth: 5
        }

      _ ->
        %{
          categorization_scheme: "hierarchical",
          auto_categorization: true,
          custom_categories: [],
          hierarchy_depth: 3
        }
    end
  end

  defp build_intelligent_search_defaults(user_id) do
    # Build intelligent search defaults
    user_type = determine_user_type(user_id)
    
    case user_type do
      :power_user ->
        %{
          default_scope: "all",
          fuzzy_search: true,
          include_content: true,
          quick_filters: ["recent", "favorites", "most_used", "by_category"]
        }

      _ ->
        %{
          default_scope: "all",
          fuzzy_search: true,
          include_content: true,
          quick_filters: ["recent", "favorites"]
        }
    end
  end

  defp build_intelligent_workflow_defaults(user_id) do
    # Build intelligent workflow defaults
    %{
      quick_access_prompts: [],
      favorite_categories: [],
      recent_limit: 10,
      shortcuts: %{}
    }
  end

  # Helper functions

  defp determine_preference_category(preference_key) do
    # Determine which category a preference key belongs to
    cond do
      String.starts_with?(preference_key, "prompt_management.display.") -> :display
      String.starts_with?(preference_key, "prompt_management.organization.") -> :organization
      String.starts_with?(preference_key, "prompt_management.search.") -> :search
      String.starts_with?(preference_key, "prompt_management.workflow.") -> :workflow
      true -> nil
    end
  end

  defp determine_user_type(user_id) do
    # Determine user type for intelligent defaults (simplified)
    # In full implementation, would analyze user behavior patterns
    :standard_user
  end

  defp parse_json_preference(json_string) do
    # Parse JSON preference values safely
    case Jason.decode(json_string) do
      {:ok, parsed_value} -> parsed_value
      {:error, _} -> json_string  # Return as string if not valid JSON
    end
  end
end