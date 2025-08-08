defmodule RubberDuck.Agents.AIAnalysisAgent do
  @moduledoc """
  Autonomous AI analysis agent that manages code analysis operations.

  This agent:
  - Autonomously schedules analyses based on project activity
  - Self-assesses result quality and learns from outcomes
  - Learns from user feedback to improve analysis quality
  - Proactively generates insights and discovers patterns
  """

  use RubberDuck.Agents.Base,
    name: "ai_analysis",
    description: "Autonomous AI analysis agent with quality learning",
    schema: [
      # Analysis scheduling
      analysis_queue: [type: {:list, :map}, default: []],
      scheduled_analyses: [type: :map, default: %{}],
      last_analysis_at: [type: {:or, [:naive_datetime, nil]}, default: nil],
      # 1 hour default
      analysis_interval: [type: :pos_integer, default: 3600],

      # Quality tracking
      quality_metrics: [type: :map, default: %{}],
      feedback_history: [type: {:list, :map}, default: []],
      accuracy_scores: [type: :map, default: %{}],
      improvement_targets: [type: {:list, :map}, default: []],

      # Pattern discovery
      discovered_patterns: [type: {:list, :map}, default: []],
      insight_cache: [type: :map, default: %{}],
      pattern_confidence: [type: :map, default: %{}],

      # Activity monitoring
      project_activity: [type: :map, default: %{}],
      file_change_tracking: [type: :map, default: %{}],
      analysis_triggers: [type: {:list, :atom}, default: [:commit, :pr, :major_change]],

      # Learning state
      analysis_models: [type: :map, default: %{}],
      learned_preferences: [type: :map, default: %{}],
      optimization_history: [type: {:list, :map}, default: []]
    ],
    actions: [
      RubberDuck.Actions.AI.ScheduleAnalysis,
      RubberDuck.Actions.AI.RunAnalysis,
      RubberDuck.Actions.AI.AssessQuality,
      RubberDuck.Actions.AI.LearnFromFeedback,
      RubberDuck.Actions.AI.DiscoverPatterns,
      RubberDuck.Actions.AI.GenerateInsights,
      RubberDuck.Actions.AI.OptimizeAnalysis,
      RubberDuck.Actions.AI.BridgeAIDomain
    ]

  require Logger

  # Helper to execute actions
  defp execute_action(_agent, action_module, params) do
    action_module.run(params, %{})
  end

  # Signal subscriptions
  @project_changed "project.changed"
  @file_modified "code_file.modified"
  @analysis_requested "analysis.requested"
  @feedback_received "analysis.feedback"
  # @pattern_detected "pattern.detected"

  def init(opts) do
    # No longer need to subscribe to signals - messages are routed directly
    # Schedule initial analysis check
    schedule_next_analysis_check()

    {:ok, opts}
  end

  @doc """
  Handle incoming instructions for AI analysis operations.
  """
  def handle_instruction({:analyze_project, project_id}, agent) do
    with {:ok, analysis_params} <- prepare_project_analysis(agent, project_id),
         {:ok, result} <-
           execute_action(agent, RubberDuck.Actions.AI.RunAnalysis, analysis_params) do
      # Update agent state with analysis result
      updated_agent = update_analysis_history(agent, project_id, result)

      # Learn from the analysis
      final_agent = learn_from_analysis(updated_agent, result)

      {:ok, result, final_agent}
    else
      {:error, reason} = error ->
        Logger.error("Failed to analyze project: #{inspect(reason)}")
        {error, agent}
    end
  end

  def handle_instruction({:analyze_code_file, file_id}, agent) do
    with {:ok, analysis_params} <- prepare_file_analysis(agent, file_id),
         {:ok, result} <-
           execute_action(agent, RubberDuck.Actions.AI.RunAnalysis, analysis_params) do
      # Assess quality of the analysis
      {:ok, quality} =
        execute_action(agent, RubberDuck.Actions.AI.AssessQuality, %{
          analysis_result: result,
          historical_data: agent.state.quality_metrics
        })

      # Update agent state
      updated_agent =
        agent
        |> update_file_analysis(file_id, result)
        |> update_quality_metrics(quality)

      {:ok, result, updated_agent}
    else
      {:error, reason} = error ->
        Logger.error("Failed to analyze code file: #{inspect(reason)}")
        {error, agent}
    end
  end

  def handle_instruction({:schedule_analysis, params}, agent) do
    case execute_action(agent, RubberDuck.Actions.AI.ScheduleAnalysis, params) do
      {:ok, schedule_result} ->
        updated_agent = add_to_analysis_queue(agent, schedule_result)
        {:ok, schedule_result, updated_agent}

      error ->
        {error, agent}
    end
  end

  def handle_instruction({:process_feedback, feedback}, agent) do
    case execute_action(agent, RubberDuck.Actions.AI.LearnFromFeedback, %{
           feedback: feedback,
           history: agent.state.feedback_history
         }) do
      {:ok, learning_result} ->
        updated_agent =
          agent
          |> add_feedback_to_history(feedback)
          |> apply_learning_updates(learning_result)

        {:ok, learning_result, updated_agent}

      error ->
        {error, agent}
    end
  end

  def handle_instruction({:discover_patterns, scope}, agent) do
    case execute_action(agent, RubberDuck.Actions.AI.DiscoverPatterns, %{
           scope: scope,
           existing_patterns: agent.state.discovered_patterns,
           confidence_threshold: 0.7
         }) do
      {:ok, patterns} ->
        updated_agent = update_discovered_patterns(agent, patterns)

        # Emit signal for discovered patterns
        emit_pattern_signal(patterns)

        {:ok, patterns, updated_agent}

      error ->
        {error, agent}
    end
  end

  def handle_instruction({:generate_insights, context}, agent) do
    case execute_action(agent, RubberDuck.Actions.AI.GenerateInsights, %{
           context: context,
           patterns: agent.state.discovered_patterns,
           cache: agent.state.insight_cache
         }) do
      {:ok, insights} ->
        updated_agent = cache_insights(agent, insights)
        {:ok, insights, updated_agent}

      error ->
        {error, agent}
    end
  end

  # Additional handlers for message routing compatibility

  def handle_instruction({:assess_quality, msg}, agent) do
    # Map to existing analyze_code_file functionality
    case msg.target do
      file_path when is_binary(file_path) ->
        handle_instruction({:analyze_code_file, file_path}, agent)

      _ ->
        # General quality assessment
        case execute_action(agent, RubberDuck.Actions.AI.RunAnalysis, %{
               type: :quality_assessment,
               target: msg.target,
               criteria: msg.criteria || [],
               baseline: msg.baseline
             }) do
          {:ok, result} -> {:ok, result, agent}
          error -> {error, agent}
        end
    end
  end

  def handle_instruction({:analyze, msg}, agent) do
    # Map to appropriate analysis based on type
    case msg.analysis_type do
      :project ->
        handle_instruction({:analyze_project, msg.target}, agent)

      :code_file ->
        handle_instruction({:analyze_code_file, msg.target}, agent)

      _ ->
        # General analysis
        case execute_action(agent, RubberDuck.Actions.AI.RunAnalysis, %{
               type: msg.analysis_type,
               target: msg.target,
               context: msg.context,
               depth: msg.depth
             }) do
          {:ok, result} -> {:ok, result, agent}
          error -> {error, agent}
        end
    end
  end

  def handle_instruction({:detect_patterns, msg}, agent) do
    # Map to discover_patterns functionality
    handle_instruction(
      {:discover_patterns,
       %{
         data_source: msg.data_source,
         pattern_types: msg.pattern_types,
         confidence_threshold: msg.confidence_threshold || 0.7,
         time_window: msg.time_window
       }},
      agent
    )
  end

  @doc """
  Handle signals for autonomous behavior.
  """
  def handle_signal(@project_changed, %{project_id: project_id} = payload, agent) do
    Logger.info("Project changed, scheduling analysis for project #{project_id}")

    # Track project activity
    updated_agent = track_project_activity(agent, project_id, payload)

    # Determine if analysis should be triggered
    if should_trigger_analysis?(updated_agent, project_id) do
      schedule_project_analysis(updated_agent, project_id)
    else
      {:ok, updated_agent}
    end
  end

  def handle_signal(@file_modified, %{file_id: file_id, project_id: project_id} = payload, agent) do
    Logger.debug("File modified: #{file_id}")

    # Track file changes
    updated_agent = track_file_change(agent, file_id, payload)

    # Check if cumulative changes warrant analysis
    if significant_changes_detected?(updated_agent, project_id) do
      schedule_incremental_analysis(updated_agent, project_id, file_id)
    else
      {:ok, updated_agent}
    end
  end

  def handle_signal(@analysis_requested, payload, agent) do
    Logger.info("Analysis requested: #{inspect(payload)}")

    # Add to priority queue
    updated_agent = add_priority_analysis(agent, payload)

    # Process immediately if possible
    process_next_analysis(updated_agent)
  end

  def handle_signal(@feedback_received, %{analysis_id: analysis_id, feedback: feedback}, agent) do
    Logger.info("Feedback received for analysis #{analysis_id}")

    # Process feedback and learn
    handle_instruction(
      {:process_feedback,
       %{
         analysis_id: analysis_id,
         feedback: feedback
       }},
      agent
    )
  end

  @doc """
  Periodic analysis check for autonomous scheduling.
  """
  def handle_info(:check_analysis_queue, agent) do
    # Process any pending analyses
    agent = process_analysis_queue(agent)

    # Schedule next check
    schedule_next_analysis_check()

    {:noreply, agent}
  end

  # Private helper functions

  defp prepare_project_analysis(agent, project_id) do
    {:ok,
     %{
       project_id: project_id,
       analysis_types: determine_analysis_types(agent, project_id),
       priority: calculate_priority(agent, project_id),
       context: build_analysis_context(agent, project_id)
     }}
  end

  defp prepare_file_analysis(agent, file_id) do
    {:ok,
     %{
       file_id: file_id,
       analysis_types: [:complexity, :quality, :security],
       context: build_file_context(agent, file_id)
     }}
  end

  defp determine_analysis_types(agent, project_id) do
    # Use learning to determine relevant analysis types
    base_types = [:general, :complexity, :quality]

    # Add types based on learned preferences
    learned_types =
      agent.state.learned_preferences
      |> Map.get(project_id, %{})
      |> Map.get(:preferred_analyses, [])

    Enum.uniq(base_types ++ learned_types)
  end

  defp calculate_priority(agent, project_id) do
    activity = Map.get(agent.state.project_activity, project_id, %{})

    cond do
      activity[:critical_change] -> :high
      activity[:recent_commits] > 5 -> :medium
      true -> :low
    end
  end

  defp build_analysis_context(agent, project_id) do
    %{
      project_id: project_id,
      last_analysis: get_last_analysis(agent, project_id),
      change_summary: get_change_summary(agent, project_id),
      quality_targets: agent.state.improvement_targets
    }
  end

  defp build_file_context(agent, file_id) do
    %{
      file_id: file_id,
      recent_changes: get_recent_file_changes(agent, file_id),
      patterns: filter_relevant_patterns(agent.state.discovered_patterns, file_id)
    }
  end

  defp update_analysis_history(agent, project_id, result) do
    history =
      agent.state.project_activity
      |> Map.get(project_id, %{})
      |> Map.put(:last_analysis, DateTime.utc_now())
      |> Map.put(:last_result, result)

    put_in(agent.state.project_activity[project_id], history)
  end

  defp learn_from_analysis(agent, result) do
    # Extract patterns from the analysis
    patterns = extract_patterns_from_result(result)

    # Update discovered patterns
    agent
    |> update_discovered_patterns(patterns)
    |> update_pattern_confidence(result)
  end

  defp update_file_analysis(agent, file_id, result) do
    tracking =
      agent.state.file_change_tracking
      |> Map.get(file_id, %{})
      |> Map.put(:last_analysis, DateTime.utc_now())
      |> Map.put(:analysis_result, result)

    put_in(agent.state.file_change_tracking[file_id], tracking)
  end

  defp update_quality_metrics(agent, quality) do
    metrics = Map.merge(agent.state.quality_metrics, quality.metrics)
    %{agent | state: Map.put(agent.state, :quality_metrics, metrics)}
  end

  defp add_to_analysis_queue(agent, schedule_result) do
    queue =
      [schedule_result | agent.state.analysis_queue]
      |> Enum.sort_by(& &1.priority)
      # Keep queue bounded
      |> Enum.take(100)

    %{agent | state: Map.put(agent.state, :analysis_queue, queue)}
  end

  defp add_feedback_to_history(agent, feedback) do
    history =
      [feedback | agent.state.feedback_history]
      # Keep history bounded
      |> Enum.take(1000)

    %{agent | state: Map.put(agent.state, :feedback_history, history)}
  end

  defp apply_learning_updates(agent, learning_result) do
    agent
    |> update_accuracy_scores(learning_result.accuracy_updates)
    |> update_improvement_targets(learning_result.improvement_areas)
    |> update_learned_preferences(learning_result.preferences)
  end

  defp update_accuracy_scores(agent, updates) do
    scores = Map.merge(agent.state.accuracy_scores, updates)
    %{agent | state: Map.put(agent.state, :accuracy_scores, scores)}
  end

  defp update_improvement_targets(agent, areas) do
    targets =
      (areas ++ agent.state.improvement_targets)
      |> Enum.uniq_by(& &1.area)
      |> Enum.take(20)

    %{agent | state: Map.put(agent.state, :improvement_targets, targets)}
  end

  defp update_learned_preferences(agent, preferences) do
    prefs = Map.merge(agent.state.learned_preferences, preferences)
    %{agent | state: Map.put(agent.state, :learned_preferences, prefs)}
  end

  defp update_discovered_patterns(agent, patterns) do
    discovered =
      (patterns ++ agent.state.discovered_patterns)
      |> Enum.uniq_by(& &1.signature)
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(500)

    %{agent | state: Map.put(agent.state, :discovered_patterns, discovered)}
  end

  defp cache_insights(agent, insights) do
    cache =
      agent.state.insight_cache
      |> Map.put(insights.context_id, insights)
      |> limit_cache_size(100)

    %{agent | state: Map.put(agent.state, :insight_cache, cache)}
  end

  defp limit_cache_size(cache, max_size) when map_size(cache) <= max_size, do: cache

  defp limit_cache_size(cache, max_size) do
    cache
    |> Enum.sort_by(fn {_, v} -> v.timestamp end, :desc)
    |> Enum.take(max_size)
    |> Map.new()
  end

  defp track_project_activity(agent, project_id, changes) do
    activity =
      agent.state.project_activity
      |> Map.get(project_id, %{})
      |> Map.put(:last_change, DateTime.utc_now())
      |> Map.update(:change_count, 1, &(&1 + 1))
      |> Map.put(:latest_changes, changes)

    put_in(agent.state.project_activity[project_id], activity)
  end

  defp track_file_change(agent, file_id, changes) do
    tracking =
      agent.state.file_change_tracking
      |> Map.get(file_id, %{})
      |> Map.put(:last_modified, DateTime.utc_now())
      |> Map.update(:modification_count, 1, &(&1 + 1))
      |> Map.put(:changes, changes)

    put_in(agent.state.file_change_tracking[file_id], tracking)
  end

  defp should_trigger_analysis?(agent, project_id) do
    activity = Map.get(agent.state.project_activity, project_id, %{})

    cond do
      # Always analyze if never analyzed
      is_nil(activity[:last_analysis]) -> true
      # Analyze if significant changes
      activity[:change_count] >= 10 -> true
      # Analyze if time threshold passed
      time_since_last_analysis(activity) > agent.state.analysis_interval -> true
      # Otherwise don't trigger
      true -> false
    end
  end

  defp significant_changes_detected?(agent, project_id) do
    files =
      agent.state.file_change_tracking
      |> Enum.filter(fn {_, tracking} ->
        tracking[:project_id] == project_id and
          tracking[:modification_count] > 3
      end)

    length(files) >= 5
  end

  defp time_since_last_analysis(%{last_analysis: last}) when not is_nil(last) do
    DateTime.diff(DateTime.utc_now(), last)
  end

  defp time_since_last_analysis(_), do: :infinity

  defp schedule_project_analysis(agent, project_id) do
    analysis = %{
      type: :project,
      project_id: project_id,
      scheduled_at: DateTime.utc_now(),
      priority: :medium
    }

    add_to_analysis_queue(agent, analysis)
  end

  defp schedule_incremental_analysis(agent, project_id, file_id) do
    analysis = %{
      type: :incremental,
      project_id: project_id,
      file_id: file_id,
      scheduled_at: DateTime.utc_now(),
      priority: :low
    }

    add_to_analysis_queue(agent, analysis)
  end

  defp add_priority_analysis(agent, request) do
    analysis = Map.put(request, :priority, :high)
    add_to_analysis_queue(agent, analysis)
  end

  defp process_next_analysis(agent) do
    case agent.state.analysis_queue do
      [analysis | rest] ->
        # Process the analysis
        {:ok, _result, updated_agent} = execute_analysis(agent, analysis)

        # Remove from queue
        final_agent = %{
          updated_agent
          | state: Map.put(updated_agent.state, :analysis_queue, rest)
        }

        {:ok, final_agent}

      [] ->
        {:ok, agent}
    end
  end

  defp process_analysis_queue(agent) do
    # Process up to 3 analyses from the queue
    Enum.reduce_while(1..3, agent, fn _, acc_agent ->
      case process_next_analysis(acc_agent) do
        {:ok, new_agent} when new_agent.state.analysis_queue != [] ->
          {:cont, new_agent}

        {:ok, new_agent} ->
          {:halt, new_agent}

        _ ->
          {:halt, acc_agent}
      end
    end)
  end

  defp execute_analysis(agent, %{type: :project, project_id: project_id}) do
    handle_instruction({:analyze_project, project_id}, agent)
  end

  defp execute_analysis(agent, %{type: :incremental, file_id: file_id}) do
    handle_instruction({:analyze_code_file, file_id}, agent)
  end

  defp execute_analysis(agent, analysis) do
    Logger.warning("Unknown analysis type: #{inspect(analysis)}")
    {:error, :unknown_analysis_type, agent}
  end

  defp extract_patterns_from_result(result) do
    # Extract recurring patterns from analysis results
    patterns = []

    # Look for code patterns
    if result[:code_patterns] do
      patterns ++
        Enum.map(result.code_patterns, fn pattern ->
          %{
            type: :code,
            signature: pattern.signature,
            occurrences: pattern.count,
            confidence: pattern.confidence || 0.8,
            discovered_at: DateTime.utc_now()
          }
        end)
    else
      patterns
    end
  end

  defp update_pattern_confidence(agent, result) do
    # Update confidence scores based on result accuracy
    confidence = agent.state.pattern_confidence

    if result[:validated_patterns] do
      updated_confidence =
        Enum.reduce(result.validated_patterns, confidence, &update_single_pattern_confidence/2)

      %{agent | state: Map.put(agent.state, :pattern_confidence, updated_confidence)}
    else
      agent
    end
  end

  defp update_single_pattern_confidence(pattern, acc) do
    Map.update(acc, pattern.signature, 0.5, fn current ->
      # Increase confidence for validated patterns
      min(1.0, current + 0.1)
    end)
  end

  defp filter_relevant_patterns(patterns, file_id) do
    # Filter patterns relevant to the specific file
    Enum.filter(patterns, fn pattern ->
      pattern[:file_ids] == nil or file_id in pattern[:file_ids]
    end)
  end

  defp get_last_analysis(agent, project_id) do
    agent.state.project_activity
    |> Map.get(project_id, %{})
    |> Map.get(:last_result)
  end

  defp get_change_summary(agent, project_id) do
    agent.state.project_activity
    |> Map.get(project_id, %{})
    |> Map.get(:latest_changes, %{})
  end

  defp get_recent_file_changes(agent, file_id) do
    agent.state.file_change_tracking
    |> Map.get(file_id, %{})
    |> Map.get(:changes, [])
  end

  defp emit_pattern_signal(patterns) do
    # Use typed AI messages
    message = %RubberDuck.Messages.AI.PatternDetect{
      data_source: %{patterns: patterns},
      pattern_types: [:behavioral, :temporal],
      confidence_threshold: 0.7,
      metadata: %{source: "ai_analysis_agent", pattern_count: length(patterns)}
    }

    RubberDuck.Routing.MessageRouter.route(message)
  end

  defp schedule_next_analysis_check do
    # Check every minute
    Process.send_after(self(), :check_analysis_queue, 60_000)
  end
end
