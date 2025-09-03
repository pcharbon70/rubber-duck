defmodule RubberDuck.Prompts.Services.PromptRecommendationEngine do
  @moduledoc """
  Discovery and recommendation engine for saved prompt collections.
  
  Provides intelligent prompt discovery and recommendation capabilities based on
  user usage patterns, prompt similarity analysis, and contextual relevance to
  help users discover relevant saved prompts and improve prompt library utilization.
  
  Features:
  - Contextual prompt recommendations based on current user workflow and task
  - Similarity-based recommendations using content and usage pattern analysis
  - Usage pattern recommendations based on user behavior and prompt effectiveness
  - Discovery suggestions for underutilized but relevant prompts in user collections
  - Performance optimization for real-time recommendation generation
  """

  require Logger

  alias RubberDuck.Prompts.Resources.{Prompt, PromptUsage}

  @recommendation_strategies [:contextual, :similarity_based, :usage_patterns, :discovery_focused]
  @similarity_algorithms [:content_similarity, :usage_similarity, :tag_similarity, :hybrid]

  @doc """
  Get contextual prompt recommendations based on current user context.
  """
  def get_contextual_recommendations(user_id, context, recommendation_options \\ %{}) do
    Logger.debug("PromptRecommendationEngine: Getting contextual recommendations",
      user_id: user_id,
      context_type: Map.get(context, :type, :general)
    )

    case execute_contextual_recommendations(user_id, context, recommendation_options) do
      {:ok, recommendations} ->
        Logger.debug("PromptRecommendationEngine: Contextual recommendations generated",
          recommendation_count: length(recommendations.recommended_prompts),
          context_relevance: recommendations.context_relevance_score
        )

        {:ok, recommendations}

      {:error, reason} ->
        Logger.error("PromptRecommendationEngine: Contextual recommendations failed", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Get similarity-based recommendations for prompt discovery.
  """
  def get_similarity_recommendations(reference_prompt, user_id, similarity_options \\ %{}) do
    Logger.debug("PromptRecommendationEngine: Getting similarity recommendations",
      reference_prompt: reference_prompt.id,
      user_id: user_id,
      similarity_algorithm: Map.get(similarity_options, :algorithm, :content_similarity)
    )

    case execute_similarity_recommendations(reference_prompt, user_id, similarity_options) do
      {:ok, similar_prompts} ->
        {:ok, similar_prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get usage pattern-based recommendations for productivity optimization.
  """
  def get_usage_pattern_recommendations(user_id, pattern_options \\ %{}) do
    Logger.debug("PromptRecommendationEngine: Getting usage pattern recommendations",
      user_id: user_id,
      analysis_period: Map.get(pattern_options, :analysis_period, :last_30_days)
    )

    case execute_usage_pattern_recommendations(user_id, pattern_options) do
      {:ok, pattern_recommendations} ->
        {:ok, pattern_recommendations}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get discovery recommendations for underutilized prompts.
  """
  def get_discovery_recommendations(user_id, discovery_options \\ %{}) do
    Logger.debug("PromptRecommendationEngine: Getting discovery recommendations",
      user_id: user_id,
      discovery_strategy: Map.get(discovery_options, :strategy, :underutilized_prompts)
    )

    case execute_discovery_recommendations(user_id, discovery_options) do
      {:ok, discovery_recommendations} ->
        {:ok, discovery_recommendations}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp execute_contextual_recommendations(user_id, context, recommendation_options) do
    # Execute contextual recommendations based on user context
    context_type = Map.get(context, :type, :general)
    workflow_context = Map.get(context, :workflow_context, %{})

    case get_user_accessible_prompts(user_id, Map.get(context, :project_id)) do
      {:ok, accessible_prompts} ->
        # Filter prompts relevant to current context
        contextual_prompts = filter_prompts_by_context(accessible_prompts, context)
        
        # Rank by contextual relevance
        ranked_prompts = rank_by_contextual_relevance(contextual_prompts, context)

        recommendations = %{
          user_id: user_id,
          context_type: context_type,
          recommended_prompts: Enum.take(ranked_prompts, Map.get(recommendation_options, :limit, 10)),
          context_relevance_score: calculate_overall_context_relevance(ranked_prompts, context),
          recommendation_metadata: %{
            context_analyzed: context,
            recommendation_strategy: :contextual,
            generated_at: DateTime.utc_now()
          }
        }

        {:ok, recommendations}

      {:error, reason} ->
        {:error, {:context_recommendation_failed, reason}}
    end
  end

  defp execute_similarity_recommendations(reference_prompt, user_id, similarity_options) do
    # Execute similarity-based recommendations
    algorithm = Map.get(similarity_options, :algorithm, :content_similarity)
    similarity_threshold = Map.get(similarity_options, :threshold, 0.3)

    case get_user_accessible_prompts(user_id, Map.get(similarity_options, :project_id)) do
      {:ok, accessible_prompts} ->
        # Remove reference prompt from candidates
        candidate_prompts = Enum.filter(accessible_prompts, fn prompt ->
          prompt.id != reference_prompt.id
        end)

        # Calculate similarity scores
        similar_prompts = candidate_prompts
        |> Enum.map(fn prompt ->
          similarity_score = calculate_prompt_similarity(reference_prompt, prompt, algorithm)
          Map.put(prompt, :similarity_score, similarity_score)
        end)
        |> Enum.filter(fn prompt -> prompt.similarity_score >= similarity_threshold end)
        |> Enum.sort_by(fn prompt -> prompt.similarity_score end, :desc)

        similarity_recommendations = %{
          reference_prompt_id: reference_prompt.id,
          user_id: user_id,
          similar_prompts: Enum.take(similar_prompts, Map.get(similarity_options, :limit, 5)),
          algorithm_used: algorithm,
          similarity_threshold: similarity_threshold,
          recommendation_metadata: %{
            candidate_count: length(candidate_prompts),
            similar_count: length(similar_prompts),
            generated_at: DateTime.utc_now()
          }
        }

        {:ok, similarity_recommendations}

      {:error, reason} ->
        {:error, {:similarity_recommendation_failed, reason}}
    end
  end

  defp execute_usage_pattern_recommendations(user_id, pattern_options) do
    # Execute usage pattern-based recommendations
    analysis_period = Map.get(pattern_options, :analysis_period, :last_30_days)
    
    # Analyze user's prompt usage patterns (simplified - would query PromptUsage)
    usage_patterns = analyze_user_prompt_usage_patterns(user_id, analysis_period)
    
    pattern_recommendations = %{
      user_id: user_id,
      analysis_period: analysis_period,
      frequently_used_prompts: get_frequently_used_prompts(usage_patterns),
      underutilized_prompts: get_underutilized_prompts(user_id, usage_patterns),
      trending_prompts: get_trending_prompts(usage_patterns),
      usage_insights: generate_usage_insights(usage_patterns),
      recommendation_metadata: %{
        pattern_analysis_method: :usage_frequency,
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, pattern_recommendations}
  end

  defp execute_discovery_recommendations(user_id, discovery_options) do
    # Execute discovery recommendations for underutilized prompts
    discovery_strategy = Map.get(discovery_options, :strategy, :underutilized_prompts)

    case discovery_strategy do
      :underutilized_prompts ->
        discover_underutilized_prompts(user_id, discovery_options)

      :similar_to_popular ->
        discover_prompts_similar_to_popular(user_id, discovery_options)

      :category_exploration ->
        discover_prompts_by_category_exploration(user_id, discovery_options)

      :comprehensive ->
        discover_prompts_comprehensive(user_id, discovery_options)
    end
  end

  # Discovery implementation functions

  defp discover_underutilized_prompts(user_id, options) do
    # Discover prompts that are rarely used but potentially valuable
    case get_user_accessible_prompts(user_id, Map.get(options, :project_id)) do
      {:ok, accessible_prompts} ->
        underutilized = accessible_prompts
        |> filter_underutilized_prompts(user_id)
        |> rank_by_potential_value(user_id)

        discovery_result = %{
          user_id: user_id,
          discovery_strategy: :underutilized_prompts,
          discovered_prompts: Enum.take(underutilized, Map.get(options, :limit, 5)),
          discovery_insights: %{
            underutilized_count: length(underutilized),
            potential_value_prompts: count_high_potential_prompts(underutilized)
          },
          discovery_metadata: %{
            discovery_method: :usage_analysis,
            generated_at: DateTime.utc_now()
          }
        }

        {:ok, discovery_result}

      {:error, reason} ->
        {:error, {:discovery_failed, reason}}
    end
  end

  defp discover_prompts_similar_to_popular(user_id, options) do
    # Discover prompts similar to user's most popular prompts
    popular_prompts = get_user_popular_prompts(user_id, 5)
    
    case popular_prompts do
      [] ->
        {:ok, %{discovered_prompts: [], discovery_strategy: :similar_to_popular}}

      prompts ->
        similar_discoveries = Enum.flat_map(prompts, fn popular_prompt ->
          case get_similarity_recommendations(popular_prompt, user_id, %{limit: 2}) do
            {:ok, similarity_result} -> similarity_result.similar_prompts
            {:error, _} -> []
          end
        end)
        |> Enum.uniq_by(fn prompt -> prompt.id end)

        discovery_result = %{
          user_id: user_id,
          discovery_strategy: :similar_to_popular,
          discovered_prompts: similar_discoveries,
          discovery_metadata: %{
            based_on_popular_count: length(prompts),
            generated_at: DateTime.utc_now()
          }
        }

        {:ok, discovery_result}
    end
  end

  defp discover_prompts_comprehensive(user_id, options) do
    # Comprehensive discovery combining multiple strategies
    with {:ok, underutilized} <- discover_underutilized_prompts(user_id, options),
         {:ok, similar_to_popular} <- discover_prompts_similar_to_popular(user_id, options) do
      
      comprehensive_discovery = %{
        user_id: user_id,
        discovery_strategy: :comprehensive,
        discovered_prompts: combine_discovery_results([underutilized, similar_to_popular]),
        discovery_insights: %{
          strategies_combined: [:underutilized_prompts, :similar_to_popular],
          total_discoveries: count_total_discoveries([underutilized, similar_to_popular])
        },
        discovery_metadata: %{
          discovery_method: :comprehensive,
          generated_at: DateTime.utc_now()
        }
      }

      {:ok, comprehensive_discovery}
    else
      {:error, reason} -> {:error, {:comprehensive_discovery_failed, reason}}
    end
  end

  # Helper functions

  defp get_user_accessible_prompts(user_id, project_id) do
    # Get all prompts accessible to user (simplified implementation)
    case Prompt.read() do
      {:ok, all_prompts} ->
        accessible_prompts = Enum.filter(all_prompts, fn prompt ->
          case {prompt.prompt_type, project_id} do
            {:system, _} -> prompt.status == :approved
            {:project, ^project_id} -> prompt.project_id == project_id and prompt.status == :approved
            {:project, nil} -> false  # No project prompts without project context
            {:user, _} -> prompt.user_id == user_id
            _ -> false
          end
        end)

        {:ok, accessible_prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter_prompts_by_context(prompts, context) do
    # Filter prompts relevant to current context
    context_keywords = extract_context_keywords(context)
    
    Enum.filter(prompts, fn prompt ->
      prompt_relevance = calculate_context_relevance(prompt, context_keywords, context)
      prompt_relevance > 0.3  # Minimum relevance threshold
    end)
  end

  defp rank_by_contextual_relevance(prompts, context) do
    # Rank prompts by relevance to current context
    context_keywords = extract_context_keywords(context)
    
    prompts
    |> Enum.map(fn prompt ->
      relevance_score = calculate_context_relevance(prompt, context_keywords, context)
      Map.put(prompt, :context_relevance_score, relevance_score)
    end)
    |> Enum.sort_by(fn prompt -> prompt.context_relevance_score end, :desc)
  end

  defp calculate_prompt_similarity(prompt1, prompt2, algorithm) do
    # Calculate similarity between two prompts
    case algorithm do
      :content_similarity ->
        calculate_content_similarity(prompt1.content, prompt2.content)

      :usage_similarity ->
        calculate_usage_similarity(prompt1, prompt2)

      :tag_similarity ->
        calculate_tag_similarity(prompt1, prompt2)

      :hybrid ->
        content_sim = calculate_content_similarity(prompt1.content, prompt2.content)
        usage_sim = calculate_usage_similarity(prompt1, prompt2)
        tag_sim = calculate_tag_similarity(prompt1, prompt2)
        
        # Weighted average
        (content_sim * 0.5) + (usage_sim * 0.3) + (tag_sim * 0.2)
    end
  end

  defp calculate_context_relevance(prompt, context_keywords, context) do
    # Calculate how relevant prompt is to current context
    keyword_relevance = calculate_keyword_relevance(prompt, context_keywords)
    type_relevance = calculate_type_relevance(prompt, context)
    usage_relevance = calculate_usage_context_relevance(prompt, context)

    # Combine relevance scores
    (keyword_relevance * 0.5) + (type_relevance * 0.3) + (usage_relevance * 0.2)
  end

  defp calculate_overall_context_relevance(ranked_prompts, context) do
    # Calculate overall context relevance for recommendation set
    case ranked_prompts do
      [] -> 0.0
      prompts ->
        relevance_scores = Enum.map(prompts, fn prompt -> 
          Map.get(prompt, :context_relevance_score, 0.0) 
        end)
        
        Enum.sum(relevance_scores) / length(relevance_scores)
    end
  end

  # Similarity calculation functions

  defp calculate_content_similarity(content1, content2) do
    # Calculate similarity between prompt contents
    words1 = extract_content_words(content1)
    words2 = extract_content_words(content2)
    
    common_words = MapSet.intersection(words1, words2)
    union_words = MapSet.union(words1, words2)

    case MapSet.size(union_words) do
      0 -> 0.0
      size -> MapSet.size(common_words) / size
    end
  end

  defp calculate_usage_similarity(prompt1, prompt2) do
    # Calculate similarity based on usage patterns
    # Simplified implementation - would analyze actual usage data
    0.5
  end

  defp calculate_tag_similarity(prompt1, prompt2) do
    # Calculate similarity based on tags
    tags1 = MapSet.new(prompt1.tags || [])
    tags2 = MapSet.new(prompt2.tags || [])
    
    common_tags = MapSet.intersection(tags1, tags2)
    union_tags = MapSet.union(tags1, tags2)

    case MapSet.size(union_tags) do
      0 -> 0.0
      size -> MapSet.size(common_tags) / size
    end
  end

  defp calculate_keyword_relevance(prompt, context_keywords) do
    # Calculate relevance based on keyword matching
    prompt_text = "#{prompt.name} #{prompt.description} #{prompt.content}"
    prompt_words = extract_content_words(prompt_text)
    
    keyword_matches = Enum.count(context_keywords, fn keyword ->
      MapSet.member?(prompt_words, String.downcase(keyword))
    end)

    case length(context_keywords) do
      0 -> 0.0
      total -> keyword_matches / total
    end
  end

  defp calculate_type_relevance(prompt, context) do
    # Calculate relevance based on prompt type and context
    context_type = Map.get(context, :type, :general)
    
    case {prompt.prompt_type, context_type} do
      {:system, :general} -> 0.6
      {:project, :project_work} -> 0.8
      {:user, :personal_productivity} -> 0.9
      _ -> 0.4
    end
  end

  defp calculate_usage_context_relevance(prompt, context) do
    # Calculate relevance based on usage context
    # Simplified implementation - would analyze when prompt was used in similar contexts
    0.5
  end

  # Analysis and pattern functions

  defp analyze_user_prompt_usage_patterns(user_id, analysis_period) do
    # Analyze user's prompt usage patterns (simplified)
    %{
      analysis_period: analysis_period,
      user_id: user_id,
      usage_frequency: %{},
      usage_contexts: [],
      effectiveness_scores: %{}
    }
  end

  defp filter_underutilized_prompts(prompts, user_id) do
    # Filter prompts that are underutilized but potentially valuable
    prompts
    |> Enum.filter(fn prompt ->
      usage_count = get_prompt_usage_count(prompt, user_id)
      potential_value = assess_prompt_potential_value(prompt)
      
      # Underutilized if low usage but high potential
      usage_count < 3 and potential_value > 0.6
    end)
  end

  defp rank_by_potential_value(prompts, user_id) do
    # Rank prompts by their potential value to user
    prompts
    |> Enum.map(fn prompt ->
      potential_score = assess_prompt_potential_value(prompt)
      Map.put(prompt, :potential_value_score, potential_score)
    end)
    |> Enum.sort_by(fn prompt -> prompt.potential_value_score end, :desc)
  end

  # Utility functions

  defp extract_context_keywords(context) do
    # Extract keywords from context for relevance matching
    keywords = []
    
    # Add workflow type keywords
    keywords = case Map.get(context, :workflow_type) do
      :code_review -> ["code", "review", "quality", "analysis"] ++ keywords
      :documentation -> ["document", "explain", "guide", "reference"] ++ keywords
      :testing -> ["test", "verify", "validate", "check"] ++ keywords
      _ -> keywords
    end

    # Add custom context keywords
    custom_keywords = Map.get(context, :keywords, [])
    keywords ++ custom_keywords
  end

  defp extract_content_words(content) do
    # Extract words from content for similarity analysis
    content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(fn word -> String.length(word) > 2 end)
    |> Enum.reject(fn word -> word in get_stop_words() end)
    |> MapSet.new()
  end

  defp get_stop_words do
    # Common stop words to filter out
    ["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "a", "an"]
  end

  defp get_prompt_usage_count(prompt, user_id) do
    # Get usage count for prompt by user (simplified)
    0
  end

  defp assess_prompt_potential_value(prompt) do
    # Assess potential value of prompt based on various factors
    content_complexity = assess_content_complexity(prompt.content)
    template_value = assess_template_value(prompt.content)
    category_value = assess_category_value(prompt)

    # Combine factors
    (content_complexity * 0.4) + (template_value * 0.4) + (category_value * 0.2)
  end

  defp assess_content_complexity(content) do
    # Assess complexity and value of prompt content
    word_count = length(String.split(content))
    variable_count = length(Regex.scan(~r/\{\{.*?\}\}/, content))

    case {word_count, variable_count} do
      {words, vars} when words > 50 and vars > 0 -> 0.9  # Complex and templated
      {words, vars} when words > 100 or vars > 3 -> 0.8  # High complexity
      {words, vars} when words > 30 or vars > 0 -> 0.6   # Moderate complexity
      _ -> 0.4                                           # Simple
    end
  end

  defp assess_template_value(content) do
    # Assess value of template variables in content
    variable_count = length(Regex.scan(~r/\{\{.*?\}\}/, content))
    
    case variable_count do
      0 -> 0.3      # No template value
      1 -> 0.6      # Some template value
      count when count <= 3 -> 0.8   # Good template value
      _ -> 0.9      # High template value
    end
  end

  defp assess_category_value(prompt) do
    # Assess value based on prompt category
    case prompt.category_id do
      nil -> 0.3      # Uncategorized
      _category -> 0.7  # Categorized prompts have higher value
    end
  end

  defp get_user_popular_prompts(user_id, limit) do
    # Get user's most popular prompts (simplified)
    []
  end

  # Utility functions for discovery
  defp get_frequently_used_prompts(usage_patterns), do: []
  defp get_underutilized_prompts(user_id, usage_patterns), do: []
  defp get_trending_prompts(usage_patterns), do: []
  defp generate_usage_insights(usage_patterns), do: %{}
  defp discover_prompts_by_category_exploration(user_id, options), do: {:ok, %{discovered_prompts: []}}
  defp combine_discovery_results(discovery_lists), do: []
  defp count_total_discoveries(discovery_lists), do: 0
  defp count_high_potential_prompts(prompts), do: 0
end