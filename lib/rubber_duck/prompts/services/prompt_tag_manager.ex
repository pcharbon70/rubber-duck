defmodule RubberDuck.Prompts.Services.PromptTagManager do
  @moduledoc """
  Advanced tagging system service for saved prompt organization.

  Provides comprehensive tagging capabilities for users to organize their saved
  prompt collections including tag creation, management, hierarchical relationships,
  auto-suggestions, and tag-based organization patterns for improved prompt
  discovery and workflow optimization.

  Features:
  - Tag creation and management with hierarchical relationships
  - Auto-suggest tags based on prompt content and user patterns
  - Tag hierarchies and relationship mapping for complex organization
  - Tag usage tracking and popularity metrics for optimization
  - Performance optimization for large tag collections and prompt libraries
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Resources.{Prompt, PromptCategory}

  @tag_relationship_types [:parent_child, :related, :synonym, :alternative]
  @auto_suggestion_strategies [:content_analysis, :usage_patterns, :similarity_matching]

  defstruct [
    :tag_config,
    :tag_cache,
    :relationship_graph,
    :suggestion_engine
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      tag_config: build_tag_config(),
      tag_cache: initialize_tag_cache(),
      relationship_graph: initialize_relationship_graph(),
      suggestion_engine: initialize_suggestion_engine()
    }

    Logger.info("PromptTagManager: Service initialized",
      relationship_types: @tag_relationship_types,
      suggestion_strategies: @auto_suggestion_strategies
    )

    {:ok, state}
  end

  # Public API

  @doc """
  Create or update tag for prompt organization.
  """
  def create_tag(user_id, tag_definition, options \\ %{}) do
    GenServer.call(__MODULE__, {:create_tag, user_id, tag_definition, options})
  end

  @doc """
  Get tag suggestions for prompt based on content analysis.
  """
  def suggest_tags_for_prompt(prompt, user_context \\ %{}, suggestion_options \\ %{}) do
    GenServer.call(__MODULE__, {:suggest_tags, prompt, user_context, suggestion_options})
  end

  @doc """
  Apply tags to prompt with relationship tracking.
  """
  def apply_tags_to_prompt(prompt_id, tags, user_id, options \\ %{}) do
    GenServer.call(__MODULE__, {:apply_tags, prompt_id, tags, user_id, options})
  end

  @doc """
  Get tag hierarchy for user's tag collection.
  """
  def get_tag_hierarchy(user_id, hierarchy_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_hierarchy, user_id, hierarchy_options})
  end

  @doc """
  Find related tags for improved prompt discovery.
  """
  def find_related_tags(tag_name, user_id, relation_options \\ %{}) do
    GenServer.call(__MODULE__, {:find_related, tag_name, user_id, relation_options})
  end

  @doc """
  Get tag usage analytics for optimization.
  """
  def get_tag_usage_analytics(user_id, tag_name \\ nil, analytics_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_analytics, user_id, tag_name, analytics_options})
  end

  # GenServer callbacks

  @impl true
  def handle_call({:create_tag, user_id, tag_definition, options}, _from, state) do
    Logger.debug("PromptTagManager: Creating tag",
      user_id: user_id,
      tag_name: tag_definition.name
    )

    case execute_tag_creation(user_id, tag_definition, options, state) do
      {:ok, tag_result} ->
        updated_state = update_tag_cache(state, tag_result)

        Logger.info("PromptTagManager: Tag created successfully",
          user_id: user_id,
          tag_name: tag_result.name,
          tag_type: tag_result.tag_type
        )

        {:reply, {:ok, tag_result}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:suggest_tags, prompt, user_context, suggestion_options}, _from, state) do
    case generate_tag_suggestions(prompt, user_context, suggestion_options, state) do
      {:ok, suggestions} ->
        Logger.debug("PromptTagManager: Tag suggestions generated",
          prompt_id: prompt.id,
          suggestion_count: length(suggestions.suggested_tags)
        )

        {:reply, {:ok, suggestions}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply_tags, prompt_id, tags, user_id, options}, _from, state) do
    case execute_tag_application(prompt_id, tags, user_id, options) do
      {:ok, application_result} ->
        {:reply, {:ok, application_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_hierarchy, user_id, hierarchy_options}, _from, state) do
    case build_user_tag_hierarchy(user_id, hierarchy_options, state) do
      {:ok, hierarchy} ->
        {:reply, {:ok, hierarchy}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:find_related, tag_name, user_id, relation_options}, _from, state) do
    case find_related_tags_for_user(tag_name, user_id, relation_options, state) do
      {:ok, related_tags} ->
        {:reply, {:ok, related_tags}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_analytics, user_id, tag_name, analytics_options}, _from, state) do
    case generate_tag_analytics(user_id, tag_name, analytics_options) do
      {:ok, analytics} ->
        {:reply, {:ok, analytics}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private implementation functions

  defp execute_tag_creation(user_id, tag_definition, options, state) do
    # Execute tag creation with validation and relationship setup
    tag_attrs = %{
      name: tag_definition.name,
      description: Map.get(tag_definition, :description, ""),
      color: Map.get(tag_definition, :color, "#6B7280"),
      user_id: user_id,
      tag_type: Map.get(tag_definition, :tag_type, :user_defined),
      parent_tag_id: Map.get(tag_definition, :parent_tag_id),
      metadata: Map.get(options, :metadata, %{})
    }

    # Create tag record (simplified - would use proper tag resource)
    tag_result = %{
      id: Ash.UUID.generate(),
      name: tag_attrs.name,
      description: tag_attrs.description,
      color: tag_attrs.color,
      user_id: user_id,
      tag_type: tag_attrs.tag_type,
      created_at: DateTime.utc_now()
    }

    {:ok, tag_result}
  end

  defp generate_tag_suggestions(prompt, user_context, suggestion_options, state) do
    # Generate tag suggestions for prompt
    suggestion_strategy = Map.get(suggestion_options, :strategy, :content_analysis)

    case suggestion_strategy do
      :content_analysis ->
        generate_content_based_tag_suggestions(prompt)

      :usage_patterns ->
        generate_usage_pattern_tag_suggestions(prompt, user_context)

      :similarity_matching ->
        generate_similarity_based_tag_suggestions(prompt, user_context, state)

      :comprehensive ->
        generate_comprehensive_tag_suggestions(prompt, user_context, state)
    end
  end

  defp execute_tag_application(prompt_id, tags, user_id, options) do
    # Apply tags to prompt and track relationships
    application_result = %{
      prompt_id: prompt_id,
      applied_tags: tags,
      user_id: user_id,
      application_method: Map.get(options, :method, :manual),
      applied_at: DateTime.utc_now(),
      tag_relationships: build_tag_relationships(tags)
    }

    # Update prompt with tags (simplified - would use proper update action)
    {:ok, application_result}
  end

  defp build_user_tag_hierarchy(user_id, hierarchy_options, state) do
    # Build hierarchical view of user's tags
    user_tags = get_user_tags(user_id)

    hierarchy = %{
      user_id: user_id,
      root_tags: filter_root_tags(user_tags),
      nested_tags: build_nested_tag_structure(user_tags),
      tag_count: length(user_tags),
      hierarchy_depth: calculate_hierarchy_depth(user_tags),
      hierarchy_metadata: %{
        built_at: DateTime.utc_now(),
        hierarchy_type: Map.get(hierarchy_options, :type, :tree)
      }
    }

    {:ok, hierarchy}
  end

  defp find_related_tags_for_user(tag_name, user_id, relation_options, state) do
    # Find tags related to the specified tag
    relation_types = Map.get(relation_options, :relation_types, @tag_relationship_types)

    related_tags = %{
      tag_name: tag_name,
      user_id: user_id,
      parent_tags: find_parent_tags(tag_name, user_id),
      child_tags: find_child_tags(tag_name, user_id),
      related_tags: find_similar_tags(tag_name, user_id),
      synonym_tags: find_synonym_tags(tag_name, user_id),
      relationship_metadata: %{
        relation_types_searched: relation_types,
        search_timestamp: DateTime.utc_now()
      }
    }

    {:ok, related_tags}
  end

  defp generate_tag_analytics(user_id, tag_name, analytics_options) do
    # Generate tag usage analytics
    analytics_scope = Map.get(analytics_options, :scope, :user_specific)

    case analytics_scope do
      :user_specific ->
        generate_user_tag_analytics(user_id, tag_name)

      :tag_specific ->
        generate_specific_tag_analytics(tag_name, user_id)

      :comprehensive ->
        generate_comprehensive_tag_analytics(user_id, tag_name)
    end
  end

  # Tag suggestion implementations

  defp generate_content_based_tag_suggestions(prompt) do
    # Generate tag suggestions based on prompt content
    content_keywords = extract_meaningful_keywords(prompt.content)
    content_topics = identify_content_topics(prompt.content)

    suggested_tags =
      (content_keywords ++ content_topics)
      |> Enum.uniq()
      # Top 5 suggestions
      |> Enum.take(5)

    suggestions = %{
      prompt_id: prompt.id,
      suggested_tags: suggested_tags,
      suggestion_method: :content_analysis,
      confidence_scores: calculate_tag_suggestion_confidence(suggested_tags, prompt),
      suggestion_metadata: %{
        content_keywords: content_keywords,
        content_topics: content_topics,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, suggestions}
  end

  defp generate_usage_pattern_tag_suggestions(prompt, user_context) do
    # Generate suggestions based on usage patterns
    suggestions = %{
      prompt_id: prompt.id,
      suggested_tags: suggest_tags_from_usage_context(user_context),
      suggestion_method: :usage_patterns,
      confidence_scores: %{},
      suggestion_metadata: %{
        user_workflow: Map.get(user_context, :workflow_type, :general),
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, suggestions}
  end

  defp generate_similarity_based_tag_suggestions(prompt, user_context, state) do
    # Generate suggestions based on similar prompts
    similar_prompts = find_similar_prompts(prompt, user_context)
    common_tags = extract_common_tags_from_similar_prompts(similar_prompts)

    suggestions = %{
      prompt_id: prompt.id,
      suggested_tags: common_tags,
      suggestion_method: :similarity_matching,
      confidence_scores: calculate_similarity_confidence(common_tags, similar_prompts),
      suggestion_metadata: %{
        similar_prompt_count: length(similar_prompts),
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, suggestions}
  end

  defp generate_comprehensive_tag_suggestions(prompt, user_context, state) do
    # Generate comprehensive suggestions combining all methods
    with {:ok, content_suggestions} <- generate_content_based_tag_suggestions(prompt),
         {:ok, usage_suggestions} <- generate_usage_pattern_tag_suggestions(prompt, user_context),
         {:ok, similarity_suggestions} <-
           generate_similarity_based_tag_suggestions(prompt, user_context, state) do
      all_suggested_tags =
        combine_tag_suggestions([content_suggestions, usage_suggestions, similarity_suggestions])

      comprehensive_suggestions = %{
        prompt_id: prompt.id,
        suggested_tags: all_suggested_tags,
        suggestion_method: :comprehensive,
        confidence_scores: calculate_comprehensive_tag_confidence(all_suggested_tags),
        suggestion_metadata: %{
          methods_combined: [:content_analysis, :usage_patterns, :similarity_matching],
          generated_at: DateTime.utc_now()
        }
      }

      {:ok, comprehensive_suggestions}
    else
      {:error, reason} -> {:error, {:comprehensive_tag_suggestions_failed, reason}}
    end
  end

  # Helper functions

  defp extract_meaningful_keywords(content) do
    # Extract meaningful keywords from prompt content
    # Remove common stop words and extract relevant terms
    words = String.split(String.downcase(content), ~r/\W+/)

    meaningful_words =
      Enum.filter(words, fn word ->
        String.length(word) > 3 and word not in get_stop_words()
      end)

    Enum.take(meaningful_words, 10)
  end

  defp identify_content_topics(content) do
    # Identify main topics in prompt content
    topic_keywords = %{
      "code_review" => ["review", "code", "quality", "analysis"],
      "documentation" => ["document", "explain", "guide", "reference"],
      "testing" => ["test", "verify", "validate", "check"],
      "debugging" => ["debug", "fix", "error", "issue"],
      "performance" => ["optimize", "performance", "speed", "efficiency"]
    }

    content_lower = String.downcase(content)

    Enum.filter(topic_keywords, fn {topic, keywords} ->
      Enum.any?(keywords, fn keyword -> String.contains?(content_lower, keyword) end)
    end)
    |> Enum.map(fn {topic, _keywords} -> topic end)
  end

  defp suggest_tags_from_usage_context(user_context) do
    # Suggest tags based on user context and workflow
    case Map.get(user_context, :workflow_type) do
      :code_review -> ["code-review", "quality", "analysis"]
      :documentation -> ["documentation", "guide", "reference"]
      :testing -> ["testing", "validation", "qa"]
      :debugging -> ["debugging", "troubleshooting", "fixes"]
      _ -> ["general", "productivity"]
    end
  end

  defp find_similar_prompts(prompt, user_context) do
    # Find prompts similar to current prompt for tag suggestions
    # Simplified implementation - would use actual similarity algorithms
    []
  end

  defp extract_common_tags_from_similar_prompts(similar_prompts) do
    # Extract common tags from similar prompts
    all_tags =
      similar_prompts
      |> Enum.flat_map(fn prompt -> prompt.tags || [] end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_tag, frequency} -> frequency > 1 end)
      |> Enum.map(fn {tag, _frequency} -> tag end)

    all_tags
  end

  defp combine_tag_suggestions(suggestion_lists) do
    # Combine tag suggestions from multiple methods
    all_tags =
      suggestion_lists
      |> Enum.flat_map(fn suggestions -> suggestions.suggested_tags end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_tag, frequency} -> frequency end, :desc)
      |> Enum.map(fn {tag, _frequency} -> tag end)
      # Top 8 combined suggestions
      |> Enum.take(8)

    all_tags
  end

  defp get_user_tags(user_id) do
    # Get all tags used by user (simplified - would query actual tag usage)
    []
  end

  defp filter_root_tags(user_tags) do
    # Filter tags that don't have parent tags (root level)
    Enum.filter(user_tags, fn tag ->
      is_nil(Map.get(tag, :parent_tag_id))
    end)
  end

  defp build_nested_tag_structure(user_tags) do
    # Build nested tag structure from flat list
    # Group tags by parent relationship
    user_tags
    |> Enum.group_by(fn tag -> Map.get(tag, :parent_tag_id, :root) end)
  end

  defp calculate_hierarchy_depth(user_tags) do
    # Calculate depth of tag hierarchy
    # Simplified implementation
    case user_tags do
      [] -> 0
      # Assume max depth of 3 for now
      _ -> 3
    end
  end

  defp build_tag_relationships(tags) do
    # Build relationships between applied tags
    Enum.map(tags, fn tag ->
      %{
        tag_name: tag,
        # Would build actual relationships
        relationships: [],
        applied_at: DateTime.utc_now()
      }
    end)
  end

  defp update_tag_cache(state, tag_result) do
    # Update tag cache with new tag
    updated_cache = Map.put(state.tag_cache, tag_result.id, tag_result)
    %{state | tag_cache: updated_cache}
  end

  # Analytics implementations

  defp generate_user_tag_analytics(user_id, tag_name) do
    # Generate analytics for user's tag usage
    analytics = %{
      user_id: user_id,
      tag_name: tag_name,
      # Would calculate from actual usage data
      total_usage: 0,
      # Would count prompts with this tag
      prompts_tagged: 0,
      # Would calculate usage per day/week
      usage_frequency: 0.0,
      # Would calculate from user feedback
      effectiveness_score: 0.75,
      analytics_metadata: %{
        analytics_type: :user_specific,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, analytics}
  end

  defp generate_specific_tag_analytics(tag_name, user_id) do
    # Generate analytics for specific tag across users
    analytics = %{
      tag_name: tag_name,
      user_id: user_id,
      # Would calculate popularity score
      tag_popularity: 0.0,
      # Would analyze where tag is used
      usage_contexts: [],
      # Would find related/similar tags
      related_tags: [],
      analytics_metadata: %{
        analytics_type: :tag_specific,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, analytics}
  end

  defp generate_comprehensive_tag_analytics(user_id, tag_name) do
    # Generate comprehensive analytics combining multiple perspectives
    with {:ok, user_analytics} <- generate_user_tag_analytics(user_id, tag_name),
         {:ok, tag_analytics} <- generate_specific_tag_analytics(tag_name, user_id) do
      comprehensive_analytics = %{
        user_analytics: user_analytics,
        tag_analytics: tag_analytics,
        combined_insights: generate_combined_tag_insights(user_analytics, tag_analytics),
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

  # Initialization functions

  defp build_tag_config do
    %{
      max_tags_per_prompt: 10,
      auto_suggestion_enabled: true,
      hierarchical_tags_enabled: true,
      tag_validation_enabled: true
    }
  end

  defp initialize_tag_cache do
    %{}
  end

  defp initialize_relationship_graph do
    %{
      parent_child_relationships: %{},
      related_tag_relationships: %{},
      synonym_relationships: %{}
    }
  end

  defp initialize_suggestion_engine do
    %{
      enabled: true,
      content_analysis_enabled: true,
      usage_pattern_analysis_enabled: true,
      similarity_matching_enabled: true
    }
  end

  # Utility functions (simplified implementations)
  defp get_stop_words,
    do: ["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]

  defp calculate_tag_suggestion_confidence(_tags, _prompt), do: %{}
  defp calculate_similarity_confidence(_tags, _prompts), do: %{}
  defp calculate_comprehensive_tag_confidence(_tags), do: %{}
  defp find_parent_tags(_tag_name, _user_id), do: []
  defp find_child_tags(_tag_name, _user_id), do: []
  defp find_similar_tags(_tag_name, _user_id), do: []
  defp find_synonym_tags(_tag_name, _user_id), do: []
  defp generate_combined_tag_insights(_user_analytics, _tag_analytics), do: %{}
end
