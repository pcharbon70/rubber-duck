defmodule RubberDuck.Verdict.Analytics.UserPreferenceProfiler do
  @moduledoc """
  Advanced user preference profiling for personalized evaluation experiences.
  
  Analyzes user feedback patterns, behavioral indicators, and interaction history
  to build comprehensive user preference profiles enabling personalized judge
  selection, evaluation criteria, and system adaptation.
  """

  require Logger

  @preference_dimensions [
    :evaluation_speed_vs_accuracy,
    :judge_specialization_preference,
    :consensus_requirement_level,
    :cost_sensitivity,
    :feedback_verbosity_preference,
    :technical_depth_preference
  ]

  @user_segments [
    :speed_focused,
    :accuracy_focused,
    :cost_conscious,
    :quality_demanding,
    :collaborative,
    :independent
  ]

  @doc """
  Profile user preferences from feedback and behavioral data.
  
  ## Parameters
  - `user_data` - User feedback, behavior, and interaction history
  - `options` - Profiling options and configuration
  
  ## Returns
  - `{:ok, user_profiles}` - User preference profiles generated
  - `{:error, reason}` - Profiling failed
  """
  def profile_user_preferences(user_data, options \\ []) do
    Logger.info("Profiling user preferences for #{length(user_data)} users")
    
    case preprocess_user_data(user_data) do
      {:ok, processed_data} ->
        case analyze_user_segments(processed_data, options) do
          {:ok, user_segments} ->
            preference_profiles = generate_preference_profiles(user_segments)
            personalization_insights = extract_personalization_insights(preference_profiles)
            
            result = %{
              user_profiles: preference_profiles,
              user_segments: user_segments,
              personalization_insights: personalization_insights,
              segment_distribution: calculate_segment_distribution(user_segments),
              profiling_metadata: %{
                users_analyzed: length(user_data),
                segments_identified: length(user_segments),
                analysis_timestamp: DateTime.utc_now(),
                profiling_confidence: calculate_profiling_confidence(preference_profiles)
              }
            }
            
            {:ok, result}
            
          {:error, reason} ->
            {:error, "User segmentation failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "User data preprocessing failed: #{reason}"}
    end
  end

  @doc """
  Generate personalized evaluation recommendations for a specific user.
  
  ## Parameters
  - `user_profile` - Individual user preference profile
  - `evaluation_context` - Context for the specific evaluation
  - `options` - Recommendation options
  
  ## Returns
  - `{:ok, recommendations}` - Personalized recommendations generated
  - `{:error, reason}` - Recommendation generation failed
  """
  def generate_personalized_recommendations(user_profile, evaluation_context, options \\ []) do
    Logger.debug("Generating personalized recommendations for user profile: #{user_profile.segment}")
    
    case validate_user_profile(user_profile) do
      :ok ->
        recommendations = build_personalized_recommendations(user_profile, evaluation_context, options)
        confidence = calculate_recommendation_confidence(user_profile, recommendations)
        
        result = %{
          user_segment: user_profile.segment,
          recommendations: recommendations,
          confidence: confidence,
          personalization_factors: extract_personalization_factors(user_profile),
          adaptation_suggestions: generate_adaptation_suggestions(user_profile, evaluation_context),
          recommendation_metadata: %{
            profile_age_days: calculate_profile_age_days(user_profile),
            data_points_used: user_profile.data_points_count,
            generated_at: DateTime.utc_now()
          }
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update user profile based on new feedback and behavioral data.
  
  ## Parameters
  - `existing_profile` - Current user profile
  - `new_data` - New feedback and behavioral data
  - `options` - Update options
  
  ## Returns
  - `{:ok, updated_profile}` - Profile updated successfully
  - `{:error, reason}` - Update failed
  """
  def update_user_profile(existing_profile, new_data, options \\ []) do
    learning_rate = Keyword.get(options, :learning_rate, 0.1)
    
    case integrate_new_data(existing_profile, new_data, learning_rate) do
      {:ok, integrated_profile} ->
        updated_profile = recalculate_user_segment(integrated_profile)
        validated_profile = validate_profile_consistency(updated_profile)
        
        {:ok, validated_profile}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Profiling Functions

  defp preprocess_user_data(user_data) do
    # Group data by user and extract preference indicators
    users_by_id = Enum.group_by(user_data, fn data ->
      Map.get(data, :user_id, :anonymous)
    end)
    
    processed_users = Enum.map(users_by_id, fn {user_id, user_records} ->
      preference_indicators = extract_user_preference_indicators(user_records)
      behavioral_patterns = analyze_user_behavioral_patterns(user_records)
      
      %{
        user_id: user_id,
        data_points_count: length(user_records),
        preference_indicators: preference_indicators,
        behavioral_patterns: behavioral_patterns,
        activity_timeline: extract_activity_timeline(user_records)
      }
    end)
    
    # Filter users with sufficient data for profiling
    sufficient_data_users = Enum.filter(processed_users, fn user ->
      user.data_points_count >= 3  # Minimum data points for reliable profiling
    end)
    
    if Enum.empty?(sufficient_data_users) do
      {:error, "Insufficient user data for preference profiling"}
    else
      {:ok, sufficient_data_users}
    end
  end

  defp analyze_user_segments(processed_data, options) do
    # Cluster users based on preference indicators
    preference_vectors = Enum.map(processed_data, &convert_to_preference_vector/1)
    
    segment_count = Keyword.get(options, :segment_count, length(@user_segments))
    
    case cluster_user_preferences(preference_vectors, segment_count) do
      {:ok, preference_clusters} ->
        user_segments = Enum.map(preference_clusters, fn cluster ->
          %{
            segment_id: Map.get(cluster, :id),
            segment_name: determine_segment_name(cluster),
            user_count: Map.get(cluster, :size, 0),
            characteristic_preferences: extract_segment_characteristics(cluster),
            segment_confidence: calculate_segment_confidence(cluster)
          }
        end)
        
        {:ok, user_segments}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_preference_profiles(user_segments) do
    Enum.flat_map(user_segments, fn segment ->
      # Generate profiles for users in this segment
      generate_segment_user_profiles(segment)
    end)
  end

  defp extract_personalization_insights(preference_profiles) do
    # Extract insights about user personalization opportunities
    segment_insights = analyze_segment_insights(preference_profiles)
    personalization_opportunities = identify_personalization_opportunities(preference_profiles)
    adaptation_potential = assess_adaptation_potential(preference_profiles)
    
    %{
      segment_insights: segment_insights,
      personalization_opportunities: personalization_opportunities,
      adaptation_potential: adaptation_potential,
      profile_quality: assess_profile_quality(preference_profiles)
    }
  end

  # User preference extraction

  defp extract_user_preference_indicators(user_records) do
    # Extract preference indicators from user's historical data
    feedback_patterns = analyze_user_feedback_patterns(user_records)
    behavioral_patterns = analyze_user_behavior_preferences(user_records)
    evaluation_patterns = analyze_user_evaluation_preferences(user_records)
    
    %{
      speed_vs_accuracy_preference: calculate_speed_accuracy_preference(feedback_patterns),
      judge_type_preference: identify_preferred_judge_types(evaluation_patterns),
      consensus_tolerance: calculate_consensus_tolerance(feedback_patterns),
      cost_sensitivity: assess_cost_sensitivity(behavioral_patterns),
      feedback_verbosity: assess_feedback_verbosity_preference(feedback_patterns),
      technical_depth: assess_technical_depth_preference(evaluation_patterns)
    }
  end

  defp analyze_user_behavioral_patterns(user_records) do
    # Analyze behavioral indicators for preference inference
    %{
      average_session_duration: calculate_average_session_duration(user_records),
      retry_frequency: calculate_retry_frequency(user_records),
      edit_frequency: calculate_edit_frequency(user_records),
      acceptance_speed: calculate_average_acceptance_speed(user_records),
      feature_usage_patterns: analyze_feature_usage(user_records),
      engagement_level: assess_engagement_level(user_records)
    }
  end

  defp extract_activity_timeline(user_records) do
    # Extract temporal activity patterns
    sorted_records = Enum.sort_by(user_records, fn record ->
      Map.get(record, :timestamp, DateTime.utc_now())
    end)
    
    %{
      first_activity: get_first_activity_time(sorted_records),
      last_activity: get_last_activity_time(sorted_records),
      activity_frequency: calculate_activity_frequency(sorted_records),
      peak_usage_times: identify_peak_usage_times(sorted_records)
    }
  end

  defp convert_to_preference_vector(user_data) do
    indicators = user_data.preference_indicators
    
    %{
      speed_preference: normalize_preference_value(indicators.speed_vs_accuracy_preference),
      consensus_tolerance: normalize_preference_value(indicators.consensus_tolerance),
      cost_sensitivity: normalize_preference_value(indicators.cost_sensitivity),
      technical_depth: normalize_preference_value(indicators.technical_depth),
      feedback_verbosity: normalize_preference_value(indicators.feedback_verbosity),
      engagement_level: normalize_preference_value(user_data.behavioral_patterns.engagement_level)
    }
  end

  # Clustering and segmentation

  defp cluster_user_preferences(preference_vectors, segment_count) do
    # Simplified clustering - would use actual ML clustering
    if length(preference_vectors) < segment_count do
      {:error, "Not enough users for preference segmentation"}
    else
      clusters = simulate_preference_clusters(preference_vectors, segment_count)
      {:ok, clusters}
    end
  end

  defp simulate_preference_clusters(preference_vectors, k) do
    cluster_size = max(1, div(length(preference_vectors), k))
    
    Enum.map(1..k, fn cluster_id ->
      cluster_members = Enum.take(preference_vectors, cluster_size)
      
      %{
        id: cluster_id,
        size: length(cluster_members),
        members: cluster_members,
        centroid: calculate_cluster_centroid(cluster_members),
        cohesion: 0.7 + :rand.uniform() * 0.2
      }
    end)
  end

  defp calculate_cluster_centroid(members) when is_list(members) and length(members) > 0 do
    feature_keys = Map.keys(List.first(members))
    
    Enum.reduce(feature_keys, %{}, fn key, acc ->
      values = Enum.map(members, fn member -> Map.get(member, key, 0.5) end)
      average = Enum.sum(values) / length(values)
      Map.put(acc, key, average)
    end)
  end

  defp calculate_cluster_centroid(_), do: %{}

  defp determine_segment_name(cluster) do
    centroid = Map.get(cluster, :centroid, %{})
    
    # Determine segment name based on dominant characteristics
    cond do
      Map.get(centroid, :speed_preference, 0.5) > 0.7 -> :speed_focused
      Map.get(centroid, :technical_depth, 0.5) > 0.8 -> :accuracy_focused
      Map.get(centroid, :cost_sensitivity, 0.5) > 0.7 -> :cost_conscious
      Map.get(centroid, :consensus_tolerance, 0.5) < 0.3 -> :independent
      Map.get(centroid, :consensus_tolerance, 0.5) > 0.8 -> :collaborative
      true -> :balanced
    end
  end

  defp extract_segment_characteristics(cluster) do
    centroid = Map.get(cluster, :centroid, %{})
    
    %{
      primary_preferences: identify_primary_preferences(centroid),
      preference_strength: calculate_preference_strength(centroid),
      consistency_level: assess_preference_consistency(cluster),
      adaptation_potential: assess_segment_adaptation_potential(centroid)
    }
  end

  defp calculate_segment_confidence(cluster) do
    # Confidence based on cluster cohesion and size
    base_confidence = 0.6
    cohesion_bonus = Map.get(cluster, :cohesion, 0.0) * 0.3
    size_bonus = min(0.1, Map.get(cluster, :size, 0) / 50.0)
    
    min(1.0, base_confidence + cohesion_bonus + size_bonus)
  end

  # Profile generation and recommendations

  defp generate_segment_user_profiles(segment) do
    # Generate individual profiles for users in this segment
    segment_characteristics = segment.characteristic_preferences
    
    # Mock individual user profiles - would be based on actual user clustering
    user_count = segment.user_count
    
    Enum.map(1..user_count, fn user_index ->
      %{
        user_id: "user_#{segment.segment_id}_#{user_index}",
        segment: segment.segment_name,
        preference_profile: generate_individual_preference_profile(segment_characteristics),
        confidence: segment.segment_confidence,
        profile_strength: calculate_individual_profile_strength(segment_characteristics),
        last_updated: DateTime.utc_now()
      }
    end)
  end

  defp generate_individual_preference_profile(segment_characteristics) do
    %{
      evaluation_speed_preference: Map.get(segment_characteristics, :speed_preference, 0.5),
      accuracy_requirement: Map.get(segment_characteristics, :accuracy_requirement, 0.8),
      preferred_judge_types: determine_preferred_judges(segment_characteristics),
      consensus_requirement: Map.get(segment_characteristics, :consensus_requirement, 0.7),
      cost_budget_sensitivity: Map.get(segment_characteristics, :cost_sensitivity, 0.5),
      feedback_detail_preference: Map.get(segment_characteristics, :feedback_verbosity, 0.6),
      technical_depth_requirement: Map.get(segment_characteristics, :technical_depth, 0.7)
    }
  end

  defp build_personalized_recommendations(user_profile, evaluation_context, options) do
    base_recommendations = generate_base_recommendations(user_profile)
    context_specific = adapt_to_evaluation_context(base_recommendations, evaluation_context)
    optimized_recommendations = optimize_recommendations(context_specific, options)
    
    %{
      judge_selection_recommendations: extract_judge_recommendations(optimized_recommendations),
      evaluation_configuration: extract_evaluation_config(optimized_recommendations),
      consensus_settings: extract_consensus_settings(optimized_recommendations),
      cost_optimization_settings: extract_cost_settings(optimized_recommendations),
      user_experience_optimizations: extract_ux_optimizations(optimized_recommendations)
    }
  end

  # Preference analysis helpers

  defp analyze_user_feedback_patterns(user_records) do
    feedback_records = Enum.filter(user_records, fn record ->
      Map.has_key?(record, :feedback_data)
    end)
    
    if Enum.empty?(feedback_records) do
      %{feedback_frequency: 0, average_satisfaction: 0.5}
    else
      %{
        feedback_frequency: length(feedback_records) / length(user_records),
        average_satisfaction: calculate_average_satisfaction(feedback_records),
        feedback_types_used: extract_feedback_types(feedback_records),
        correction_frequency: calculate_correction_frequency(feedback_records)
      }
    end
  end

  defp analyze_user_behavior_preferences(user_records) do
    %{
      session_length_preference: infer_session_length_preference(user_records),
      interaction_style: infer_interaction_style(user_records), 
      feature_exploration_level: assess_feature_exploration(user_records),
      help_seeking_behavior: assess_help_seeking_patterns(user_records)
    }
  end

  defp analyze_user_evaluation_preferences(user_records) do
    evaluation_records = Enum.filter(user_records, fn record ->
      Map.has_key?(record, :evaluation_data)
    end)
    
    %{
      preferred_evaluation_depth: infer_evaluation_depth_preference(evaluation_records),
      judge_type_preferences: analyze_judge_type_preferences(evaluation_records),
      consensus_level_preferences: analyze_consensus_preferences(evaluation_records),
      cost_vs_quality_preference: analyze_cost_quality_tradeoffs(evaluation_records)
    }
  end

  # Preference calculation helpers

  defp calculate_speed_accuracy_preference(feedback_patterns) do
    # Analyze user's preference for speed vs accuracy based on feedback
    satisfaction = feedback_patterns.average_satisfaction
    correction_freq = feedback_patterns.correction_frequency
    
    # High satisfaction with few corrections suggests speed preference
    # Low satisfaction despite few corrections suggests accuracy preference
    speed_indicator = satisfaction - correction_freq
    
    # Normalize to 0-1 scale (0 = accuracy focused, 1 = speed focused)
    min(1.0, max(0.0, 0.5 + speed_indicator))
  end

  defp identify_preferred_judge_types(evaluation_patterns) do
    # Analyze which judge types the user seems to prefer
    judge_preferences = evaluation_patterns.judge_type_preferences || %{}
    
    # Sort by preference strength and return top preferences
    sorted_preferences = Enum.sort_by(judge_preferences, fn {_judge, preference} ->
      -preference
    end)
    
    Enum.take(sorted_preferences, 3) |> Enum.map(fn {judge, _pref} -> judge end)
  end

  defp calculate_consensus_tolerance(feedback_patterns) do
    # Analyze user's tolerance for multi-agent consensus processes
    correction_freq = feedback_patterns.correction_frequency
    satisfaction = feedback_patterns.average_satisfaction
    
    # Users who provide many corrections may prefer independent evaluation
    # Users with high satisfaction despite consensus may tolerate consensus well
    consensus_tolerance = satisfaction - (correction_freq * 0.5)
    
    min(1.0, max(0.0, consensus_tolerance))
  end

  defp assess_cost_sensitivity(behavioral_patterns) do
    # Infer cost sensitivity from behavioral patterns
    session_length = behavioral_patterns.session_length_preference || 0.5
    interaction_style = behavioral_patterns.interaction_style || :moderate
    
    # Longer sessions and detailed interactions suggest less cost sensitivity
    base_sensitivity = 0.6
    
    length_factor = case session_length do
      :short -> 0.3  # High cost sensitivity
      :medium -> 0.0  # Neutral
      :long -> -0.2  # Lower cost sensitivity
      _ -> 0.0
    end
    
    interaction_factor = case interaction_style do
      :minimal -> 0.2  # Higher cost sensitivity
      :detailed -> -0.1  # Lower cost sensitivity
      _ -> 0.0
    end
    
    min(1.0, max(0.0, base_sensitivity + length_factor + interaction_factor))
  end

  defp assess_feedback_verbosity_preference(feedback_patterns) do
    # Analyze user's preference for detailed vs concise feedback
    feedback_types = feedback_patterns.feedback_types_used || []
    detailed_feedback_count = Enum.count(feedback_types, fn type ->
      type in [:explicit_correction, :explicit_comment]
    end)
    
    if length(feedback_types) > 0 do
      detailed_feedback_count / length(feedback_types)
    else
      0.5  # Default neutral preference
    end
  end

  defp assess_technical_depth_preference(evaluation_patterns) do
    # Analyze user's preference for technical depth in evaluations
    depth_preference = evaluation_patterns.preferred_evaluation_depth || 0.7
    
    # Normalize depth preference to 0-1 scale
    min(1.0, max(0.0, depth_preference))
  end

  # Recommendation generation

  defp generate_base_recommendations(user_profile) do
    profile_data = user_profile.preference_profile
    
    %{
      judge_selection_strategy: recommend_judge_selection_strategy(profile_data),
      evaluation_speed_setting: recommend_speed_setting(profile_data),
      consensus_threshold: recommend_consensus_threshold(profile_data),
      cost_optimization_level: recommend_cost_optimization(profile_data),
      feedback_detail_level: recommend_feedback_detail_level(profile_data),
      quality_vs_speed_balance: recommend_quality_speed_balance(profile_data)
    }
  end

  defp adapt_to_evaluation_context(base_recommendations, evaluation_context) do
    # Adapt recommendations based on specific evaluation context
    context_factors = %{
      evaluation_complexity: Map.get(evaluation_context, :complexity, :medium),
      time_constraints: Map.get(evaluation_context, :time_constraints, :normal),
      quality_requirements: Map.get(evaluation_context, :quality_requirements, :standard)
    }
    
    # Adjust recommendations based on context
    Enum.reduce(context_factors, base_recommendations, fn {factor, value}, acc ->
      adjust_recommendations_for_context(acc, factor, value)
    end)
  end

  defp optimize_recommendations(recommendations, options) do
    optimization_level = Keyword.get(options, :optimization_level, :balanced)
    
    case optimization_level do
      :aggressive -> apply_aggressive_optimizations(recommendations)
      :conservative -> apply_conservative_optimizations(recommendations)
      :balanced -> apply_balanced_optimizations(recommendations)
      _ -> recommendations
    end
  end

  # Recommendation extraction helpers

  defp extract_judge_recommendations(recommendations) do
    %{
      primary_judges: Map.get(recommendations, :preferred_judge_types, [:code_quality]),
      judge_selection_strategy: Map.get(recommendations, :judge_selection_strategy, :balanced),
      consensus_threshold: Map.get(recommendations, :consensus_threshold, 0.7)
    }
  end

  defp extract_evaluation_config(recommendations) do
    %{
      speed_setting: Map.get(recommendations, :evaluation_speed_setting, :standard),
      quality_level: Map.get(recommendations, :quality_vs_speed_balance, :balanced),
      detail_level: Map.get(recommendations, :feedback_detail_level, :standard)
    }
  end

  defp extract_consensus_settings(recommendations) do
    %{
      consensus_threshold: Map.get(recommendations, :consensus_threshold, 0.7),
      max_negotiation_rounds: 3,  # Based on user tolerance
      fallback_strategy: :single_best  # For low consensus tolerance users
    }
  end

  defp extract_cost_settings(recommendations) do
    %{
      cost_optimization_level: Map.get(recommendations, :cost_optimization_level, :medium),
      budget_constraints: :auto_detect,
      cost_vs_quality_preference: Map.get(recommendations, :quality_vs_speed_balance, :balanced)
    }
  end

  defp extract_ux_optimizations(recommendations) do
    %{
      interface_complexity: :adaptive,
      feedback_frequency: Map.get(recommendations, :feedback_detail_level, :standard),
      progress_reporting: :detailed
    }
  end

  # Profile update and validation

  defp integrate_new_data(existing_profile, new_data, learning_rate) do
    # Integrate new data using exponential moving average
    current_preferences = existing_profile.preference_profile
    new_indicators = extract_preference_indicators_from_new_data(new_data)
    
    updated_preferences = Enum.reduce(new_indicators, current_preferences, fn {key, new_value}, acc ->
      current_value = Map.get(acc, key, 0.5)
      updated_value = current_value * (1 - learning_rate) + new_value * learning_rate
      Map.put(acc, key, updated_value)
    end)
    
    updated_profile = %{existing_profile |
      preference_profile: updated_preferences,
      data_points_count: existing_profile.data_points_count + 1,
      last_updated: DateTime.utc_now()
    }
    
    {:ok, updated_profile}
  end

  defp recalculate_user_segment(profile) do
    # Recalculate user segment based on updated preferences
    preference_vector = convert_profile_to_vector(profile.preference_profile)
    new_segment = classify_user_segment(preference_vector)
    
    %{profile | segment: new_segment}
  end

  defp validate_profile_consistency(profile) do
    # Ensure profile values are consistent and within expected ranges
    validated_preferences = Enum.reduce(profile.preference_profile, %{}, fn {key, value}, acc ->
      validated_value = if is_number(value) do
        min(1.0, max(0.0, value))
      else
        0.5
      end
      
      Map.put(acc, key, validated_value)
    end)
    
    %{profile | preference_profile: validated_preferences}
  end

  # Helper calculation functions (stubs for comprehensive implementation)

  defp calculate_segment_distribution(user_segments) do
    total_users = Enum.sum(Enum.map(user_segments, & &1.user_count))
    
    Enum.reduce(user_segments, %{}, fn segment, acc ->
      percentage = if total_users > 0, do: segment.user_count / total_users, else: 0.0
      Map.put(acc, segment.segment_name, percentage)
    end)
  end

  defp calculate_profiling_confidence(profiles) do
    if Enum.empty?(profiles) do
      0.0
    else
      confidences = Enum.map(profiles, & &1.confidence)
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp validate_user_profile(profile) when is_map(profile) do
    required_fields = [:segment, :preference_profile]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(profile, field)
    end)
    
    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing profile fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_user_profile(_), do: {:error, "Invalid profile format"}

  # Stub implementations for comprehensive user analysis

  defp calculate_average_satisfaction(feedback_records) when is_list(feedback_records) do
    satisfactions = Enum.map(feedback_records, fn record ->
      feedback = Map.get(record, :feedback_data, %{})
      Map.get(feedback, :satisfaction, 0.5)
    end)
    
    if Enum.empty?(satisfactions), do: 0.5, else: Enum.sum(satisfactions) / length(satisfactions)
  end

  defp extract_feedback_types(feedback_records) do
    Enum.map(feedback_records, fn record ->
      Map.get(record, :feedback_type, :unknown)
    end) |> Enum.uniq()
  end

  defp calculate_correction_frequency(feedback_records) do
    correction_count = Enum.count(feedback_records, fn record ->
      Map.get(record, :feedback_type) == :explicit_correction
    end)
    
    correction_count / max(1, length(feedback_records))
  end

  defp normalize_preference_value(value) when is_number(value), do: min(1.0, max(0.0, value))
  defp normalize_preference_value(:high), do: 0.8
  defp normalize_preference_value(:medium), do: 0.5  
  defp normalize_preference_value(:low), do: 0.2
  defp normalize_preference_value(_), do: 0.5

  # Analysis helpers (stubs)

  defp analyze_segment_insights(_profiles), do: %{primary_segments: [:speed_focused, :accuracy_focused]}
  defp identify_personalization_opportunities(_profiles), do: ["judge_selection", "evaluation_speed"]
  defp assess_adaptation_potential(_profiles), do: :high
  defp assess_profile_quality(_profiles), do: :good

  defp calculate_average_session_duration(_records), do: 15.5
  defp calculate_retry_frequency(_records), do: 0.1
  defp calculate_edit_frequency(_records), do: 0.2
  defp calculate_average_acceptance_speed(_records), do: 3_500
  defp analyze_feature_usage(_records), do: %{most_used: :basic_evaluation}
  defp assess_engagement_level(_records), do: :medium

  defp get_first_activity_time([]), do: DateTime.utc_now()
  defp get_first_activity_time([first | _]), do: Map.get(first, :timestamp, DateTime.utc_now())
  defp get_last_activity_time([]), do: DateTime.utc_now()
  defp get_last_activity_time(records), do: Map.get(List.last(records), :timestamp, DateTime.utc_now())
  defp calculate_activity_frequency(_records), do: :regular
  defp identify_peak_usage_times(_records), do: [9, 14, 17]

  defp identify_primary_preferences(centroid) when is_map(centroid) do
    # Identify the strongest preferences
    Enum.filter(centroid, fn {_key, value} ->
      is_number(value) and (value > 0.7 or value < 0.3)
    end)
    |> Enum.map(fn {key, _value} -> key end)
  end

  defp calculate_preference_strength(centroid) when is_map(centroid) do
    # Calculate how strong/distinct the preferences are
    values = Map.values(centroid) |> Enum.filter(&is_number/1)
    
    if Enum.empty?(values) do
      0.5
    else
      # Strength based on deviation from neutral (0.5)
      deviations = Enum.map(values, fn value -> abs(value - 0.5) end)
      average_deviation = Enum.sum(deviations) / length(deviations)
      
      # Convert to strength score
      average_deviation * 2
    end
  end

  defp assess_preference_consistency(_cluster), do: :high
  defp assess_segment_adaptation_potential(_centroid), do: :medium

  defp calculate_individual_profile_strength(_characteristics), do: 0.75
  defp calculate_recommendation_confidence(_profile, _recommendations), do: 0.8
  defp extract_personalization_factors(_profile), do: [:judge_selection, :consensus_level]
  defp generate_adaptation_suggestions(_profile, _context), do: ["adapt_judge_selection", "personalize_consensus"]
  defp calculate_profile_age_days(_profile), do: 7

  defp determine_preferred_judges(_characteristics), do: [:code_quality, :architecture]

  defp recommend_judge_selection_strategy(_profile), do: :specialized
  defp recommend_speed_setting(_profile), do: :standard  
  defp recommend_consensus_threshold(_profile), do: 0.7
  defp recommend_cost_optimization(_profile), do: :medium
  defp recommend_feedback_detail_level(_profile), do: :detailed
  defp recommend_quality_speed_balance(_profile), do: :balanced

  defp adjust_recommendations_for_context(recommendations, :evaluation_complexity, :high) do
    Map.put(recommendations, :quality_vs_speed_balance, :quality_focused)
  end

  defp adjust_recommendations_for_context(recommendations, :time_constraints, :urgent) do
    Map.put(recommendations, :evaluation_speed_setting, :fast)
  end

  defp adjust_recommendations_for_context(recommendations, _factor, _value), do: recommendations

  defp apply_aggressive_optimizations(recommendations), do: Map.put(recommendations, :optimization_level, :aggressive)
  defp apply_conservative_optimizations(recommendations), do: Map.put(recommendations, :optimization_level, :conservative)
  defp apply_balanced_optimizations(recommendations), do: recommendations

  defp extract_preference_indicators_from_new_data(_new_data) do
    # Would extract preference indicators from new user data
    %{speed_vs_accuracy_preference: 0.6, consensus_tolerance: 0.7}
  end

  defp convert_profile_to_vector(_preference_profile), do: %{speed_preference: 0.6, accuracy_preference: 0.7}
  defp classify_user_segment(_preference_vector), do: :balanced

  # Analysis stubs for user behavior

  defp infer_session_length_preference(_records), do: :medium
  defp infer_interaction_style(_records), do: :moderate
  defp assess_feature_exploration(_records), do: :medium
  defp assess_help_seeking_patterns(_records), do: :occasional
  defp infer_evaluation_depth_preference(_records), do: 0.7
  defp analyze_judge_type_preferences(_records), do: %{code_quality: 0.8, architecture: 0.6}
  defp analyze_consensus_preferences(_records), do: 0.7
  defp analyze_cost_quality_tradeoffs(_records), do: :balanced
end