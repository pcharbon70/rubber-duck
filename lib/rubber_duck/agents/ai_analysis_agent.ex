defmodule RubberDuck.Agents.AIAnalysisAgent do
  @moduledoc """
  AI analysis agent for autonomous analysis scheduling with quality assessment.

  This agent schedules analysis tasks based on project activity, learns from
  analysis outcomes, and generates proactive insights from pattern recognition.
  """

  use Jido.Agent,
    name: "ai_analysis_agent",
    description: "Autonomous analysis scheduling with quality assessment",
    category: "domain",
    tags: ["ai", "analysis", "scheduling"],
    vsn: "1.0.0",
    actions: [
      RubberDuck.Actions.CreateEntity
    ]

  alias RubberDuck.Skills.{CodeAnalysisSkill, LearningSkill}

  @doc """
  Create a new AIAnalysisAgent instance.
  """
  def create_for_analysis(analysis_scope \\ :project) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             analysis_scope: analysis_scope,
             scheduled_analyses: [],
             completed_analyses: [],
             quality_assessments: %{},
             insights: [],
             analysis_patterns: %{},
             last_scheduling: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Schedule analysis based on project activity.
  """
  def schedule_analysis(agent, analysis_type, target, priority \\ :medium) do
    analysis_task = %{
      id: generate_analysis_id(),
      type: analysis_type,
      target: target,
      priority: priority,
      scheduled_at: DateTime.utc_now(),
      status: :scheduled
    }

    current_scheduled = Map.get(agent, :scheduled_analyses, [])
    updated_scheduled = [analysis_task | current_scheduled]

    # Learn from scheduling patterns
    _pattern_context = %{
      analysis_type: analysis_type,
      priority: priority,
      scope: agent.analysis_scope
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        scheduled_analyses: updated_scheduled,
        last_scheduling: DateTime.utc_now()
      )

    {:ok, analysis_task, updated_agent}
  end

  @doc """
  Execute scheduled analysis and assess quality.
  """
  def execute_analysis(agent, analysis_id) do
    scheduled = Map.get(agent, :scheduled_analyses, [])

    case Enum.find(scheduled, &(&1.id == analysis_id)) do
      nil ->
        {:error, :analysis_not_found}

      analysis_task ->
        # Execute the analysis
        execution_result = perform_analysis(analysis_task)

        # Assess quality of results
        quality_assessment = assess_analysis_quality(execution_result, analysis_task)

        # Update agent state
        completed_analyses = [execution_result | Map.get(agent, :completed_analyses, [])]
        remaining_scheduled = Enum.reject(scheduled, &(&1.id == analysis_id))

        updated_assessments =
          Map.put(
            Map.get(agent, :quality_assessments, %{}),
            analysis_id,
            quality_assessment
          )

        {:ok, updated_agent} =
          __MODULE__.set(agent,
            scheduled_analyses: remaining_scheduled,
            completed_analyses: completed_analyses,
            quality_assessments: updated_assessments,
            last_execution: DateTime.utc_now()
          )

        {:ok, execution_result, updated_agent}
    end
  end

  @doc """
  Generate proactive insights from analysis patterns.
  """
  def generate_insights(agent) do
    completed_analyses = Map.get(agent, :completed_analyses, [])
    quality_assessments = Map.get(agent, :quality_assessments, %{})

    insights = %{
      analysis_trends: identify_analysis_trends(completed_analyses),
      quality_patterns: analyze_quality_patterns(quality_assessments),
      proactive_suggestions: generate_proactive_analysis_suggestions(agent),
      performance_insights: extract_performance_insights(completed_analyses),
      confidence_score: calculate_insight_confidence(completed_analyses)
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        insights: [insights | Map.get(agent, :insights, [])] |> Enum.take(50),
        last_insight_generation: DateTime.utc_now()
      )

    {:ok, insights, updated_agent}
  end

  @doc """
  Self-assess analysis quality and adjust approaches.
  """
  def self_assess_quality(agent) do
    quality_assessments = Map.get(agent, :quality_assessments, %{})
    completed_analyses = Map.get(agent, :completed_analyses, [])

    assessment = %{
      total_analyses: length(completed_analyses),
      average_quality: calculate_average_quality(quality_assessments),
      improvement_trend: calculate_improvement_trend(quality_assessments),
      accuracy_score: calculate_accuracy_score(quality_assessments),
      recommendations: generate_self_improvement_recommendations(agent)
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        self_assessment: assessment,
        last_self_assessment: DateTime.utc_now()
      )

    {:ok, assessment, updated_agent}
  end

  @doc """
  Get current analysis queue and status.
  """
  def get_analysis_status(agent) do
    scheduled = Map.get(agent, :scheduled_analyses, [])
    completed = Map.get(agent, :completed_analyses, [])

    status = %{
      scheduled_count: length(scheduled),
      completed_count: length(completed),
      pending_analyses: scheduled,
      recent_completions: Enum.take(completed, 10),
      queue_health: assess_queue_health(scheduled, completed)
    }

    {:ok, status}
  end

  # Private helper functions

  defp generate_analysis_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp perform_analysis(analysis_task) do
    # TODO: Implement actual analysis execution
    # This would integrate with various analysis tools based on type
    %{
      id: analysis_task.id,
      type: analysis_task.type,
      target: analysis_task.target,
      result: simulate_analysis_result(analysis_task.type),
      execution_time: :rand.uniform(1000),
      # ms
      executed_at: DateTime.utc_now(),
      status: :completed
    }
  end

  defp simulate_analysis_result(:code_quality) do
    %{
      quality_score: 75 + :rand.uniform(20),
      issues_found: :rand.uniform(10),
      suggestions: ["Improve error handling", "Add documentation"]
    }
  end

  defp simulate_analysis_result(:security) do
    %{
      vulnerabilities: :rand.uniform(3),
      risk_level: Enum.random([:low, :medium, :high]),
      recommendations: ["Update dependencies", "Review input validation"]
    }
  end

  defp simulate_analysis_result(:performance) do
    %{
      hotspots: :rand.uniform(5),
      optimization_potential: :rand.uniform(30),
      bottlenecks: ["Database queries", "Large data processing"]
    }
  end

  defp simulate_analysis_result(_type) do
    %{result: "Analysis completed", confidence: 0.8}
  end

  defp assess_analysis_quality(execution_result, _analysis_task) do
    # TODO: Implement actual quality assessment
    %{
      accuracy: 0.8 + :rand.uniform() * 0.15,
      completeness: 0.75 + :rand.uniform() * 0.2,
      relevance: 0.85 + :rand.uniform() * 0.1,
      execution_efficiency: calculate_efficiency_score(execution_result.execution_time),
      overall_score: 0.8
    }
  end

  defp calculate_efficiency_score(execution_time) when execution_time < 500, do: 1.0
  defp calculate_efficiency_score(execution_time) when execution_time < 1000, do: 0.8
  defp calculate_efficiency_score(execution_time) when execution_time < 2000, do: 0.6
  defp calculate_efficiency_score(_execution_time), do: 0.4

  defp identify_analysis_trends(completed_analyses) do
    if Enum.empty?(completed_analyses) do
      %{trend: :insufficient_data}
    else
      recent_analyses = Enum.take(completed_analyses, 20)

      %{
        most_common_type: find_most_common_analysis_type(recent_analyses),
        average_execution_time: calculate_average_execution_time(recent_analyses),
        success_rate: calculate_analysis_success_rate(recent_analyses)
      }
    end
  end

  defp analyze_quality_patterns(quality_assessments) do
    if map_size(quality_assessments) == 0 do
      %{pattern: :insufficient_data}
    else
      scores = Map.values(quality_assessments)

      %{
        average_quality: calculate_average_assessment_score(scores),
        quality_trend: assess_quality_trend(scores),
        consistency: calculate_quality_consistency(scores)
      }
    end
  end

  defp generate_proactive_analysis_suggestions(agent) do
    _patterns = Map.get(agent, :analysis_patterns, %{})
    completed = Map.get(agent, :completed_analyses, [])

    # TODO: Implement sophisticated suggestion generation
    if length(completed) > 10 do
      [
        %{
          type: :automation,
          suggestion: "Consider setting up automated analysis scheduling",
          priority: :medium
        }
      ]
    else
      []
    end
  end

  defp extract_performance_insights(completed_analyses) do
    performance_analyses =
      Enum.filter(completed_analyses, &(&1.type == :performance))

    if Enum.empty?(performance_analyses) do
      %{insight: :no_performance_data}
    else
      %{
        common_bottlenecks: extract_common_bottlenecks(performance_analyses),
        optimization_success_rate: calculate_optimization_success_rate(performance_analyses)
      }
    end
  end

  defp calculate_insight_confidence(completed_analyses) do
    count = length(completed_analyses)
    min(count / 50.0, 1.0)
  end

  defp calculate_average_quality(quality_assessments) do
    if map_size(quality_assessments) == 0 do
      0.0
    else
      scores =
        quality_assessments
        |> Map.values()
        |> Enum.map(& &1.overall_score)

      Enum.sum(scores) / length(scores)
    end
  end

  defp calculate_improvement_trend(quality_assessments) do
    scores =
      quality_assessments
      |> Map.values()
      |> Enum.map(& &1.overall_score)
      |> Enum.reverse()

    if length(scores) < 5 do
      :insufficient_data
    else
      recent_avg = Enum.take(scores, 5) |> Enum.sum() |> Kernel./(5)
      older_avg = Enum.slice(scores, 5, 5) |> Enum.sum() |> Kernel./(5)

      cond do
        recent_avg > older_avg + 0.1 -> :improving
        recent_avg < older_avg - 0.1 -> :declining
        true -> :stable
      end
    end
  end

  defp calculate_accuracy_score(quality_assessments) do
    if map_size(quality_assessments) == 0 do
      0.0
    else
      accuracies =
        quality_assessments
        |> Map.values()
        |> Enum.map(& &1.accuracy)

      Enum.sum(accuracies) / length(accuracies)
    end
  end

  defp generate_self_improvement_recommendations(agent) do
    assessment = Map.get(agent, :self_assessment, %{})
    avg_quality = Map.get(assessment, :average_quality, 0.8)

    cond do
      avg_quality < 0.6 ->
        ["Review analysis methodologies", "Increase validation steps"]

      avg_quality < 0.8 ->
        ["Fine-tune analysis parameters", "Add more context to analyses"]

      true ->
        ["Maintain current quality standards", "Explore advanced analysis techniques"]
    end
  end

  defp assess_queue_health(scheduled, completed) do
    scheduled_count = length(scheduled)
    completed_count = length(completed)

    cond do
      scheduled_count == 0 and completed_count > 0 -> :idle
      scheduled_count < 5 -> :healthy
      scheduled_count < 15 -> :busy
      true -> :overloaded
    end
  end

  defp find_most_common_analysis_type(analyses) do
    analyses
    |> Enum.map(& &1.type)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_type, count} -> count end, fn -> {:unknown, 0} end)
    |> elem(0)
  end

  defp calculate_average_execution_time(analyses) do
    times = Enum.map(analyses, & &1.execution_time)
    if Enum.empty?(times), do: 0, else: Enum.sum(times) / length(times)
  end

  defp calculate_analysis_success_rate(analyses) do
    successful = Enum.count(analyses, &(&1.status == :completed))
    total = length(analyses)
    if total > 0, do: successful / total, else: 0.0
  end

  defp calculate_average_assessment_score(scores) do
    overall_scores = Enum.map(scores, & &1.overall_score)

    if Enum.empty?(overall_scores),
      do: 0.0,
      else: Enum.sum(overall_scores) / length(overall_scores)
  end

  defp assess_quality_trend(scores) do
    if length(scores) < 3, do: :insufficient_data

    recent = Enum.take(scores, 3) |> Enum.map(& &1.overall_score) |> Enum.sum() |> Kernel./(3)

    older =
      Enum.drop(scores, 3)
      |> Enum.take(3)
      |> Enum.map(& &1.overall_score)
      |> Enum.sum()
      |> Kernel./(3)

    cond do
      recent > older + 0.1 -> :improving
      recent < older - 0.1 -> :declining
      true -> :stable
    end
  end

  defp calculate_quality_consistency(scores) do
    overall_scores = Enum.map(scores, & &1.overall_score)

    if length(overall_scores) < 2 do
      1.0
    else
      mean = Enum.sum(overall_scores) / length(overall_scores)

      variance =
        Enum.map(overall_scores, &((&1 - mean) ** 2))
        |> Enum.sum()
        |> Kernel./(length(overall_scores))

      std_dev = :math.sqrt(variance)

      # Lower standard deviation = higher consistency
      max(1.0 - std_dev, 0.0)
    end
  end

  defp extract_common_bottlenecks(performance_analyses) do
    performance_analyses
    |> Enum.flat_map(fn analysis ->
      Map.get(analysis.result, :bottlenecks, [])
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_bottleneck, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp calculate_optimization_success_rate(_performance_analyses) do
    # TODO: Implement optimization success rate calculation
    0.75
  end
end
