defmodule RubberDuck.Actions.Core.UpdateEntity.ImpactAnalyzer do
  @moduledoc """
  Impact analysis module for UpdateEntity action.

  Analyzes the potential impact of entity changes including:
  - Direct impact on the entity itself
  - Dependency impact on related entities
  - Performance implications
  - System-wide effects
  - Risk assessment and mitigation strategies
  """

  require Logger

  @doc """
  Main impact analysis entry point that orchestrates all impact assessments.

  Returns comprehensive impact analysis with scores, recommendations, and mitigation strategies.
  """
  def analyze(params, context) do
    entity = params.entity || params.current_entity
    validated_changes = params.validated_changes || params.changes

    impact = %{
      direct_impact: analyze_direct_impact(entity, validated_changes),
      dependency_impact: analyze_dependency_impact(entity, validated_changes),
      performance_impact: estimate_performance_impact(entity, validated_changes),
      system_impact: assess_system_wide_impact(entity, validated_changes),
      risk_assessment: assess_update_risks(entity, validated_changes),
      affected_entities: identify_affected_entities(entity, validated_changes),
      propagation_analysis: analyze_propagation_requirements(entity, validated_changes)
    }

    {:ok,
     %{
       entity: entity,
       impact_score: calculate_overall_impact_score(impact),
       impact_details: impact,
       recommendations: generate_impact_recommendations(impact),
       mitigation_strategies: suggest_mitigation_strategies(impact),
       rollback_points: identify_rollback_points(impact),
       metadata: Map.get(context, :metadata, %{})
     }}
  end

  @doc """
  Analyzes the direct impact of changes on the entity itself.
  """
  def analyze_direct_impact(entity, changes) do
    %{
      fields_affected: count_affected_fields(changes),
      severity: get_change_severity(changes),
      immediate_effects: predict_immediate_effects(entity, changes),
      data_integrity_impact: assess_data_integrity_impact(changes),
      validation_score: calculate_validation_score(changes)
    }
  end

  defp count_affected_fields(%{changes: changes}) when is_map(changes) do
    map_size(changes)
  end

  defp count_affected_fields(%{change_count: count}), do: count
  defp count_affected_fields(changes) when is_map(changes), do: map_size(changes)
  defp count_affected_fields(_), do: 0

  defp get_change_severity(%{change_severity: severity}), do: severity
  defp get_change_severity(_), do: :unknown

  defp calculate_validation_score(%{validations: validations}) do
    valid_count =
      validations
      |> Map.values()
      |> Enum.count(& &1[:valid])

    total = map_size(validations)
    if total > 0, do: valid_count / total, else: 1.0
  end

  defp calculate_validation_score(_), do: 1.0

  @doc """
  Analyzes the impact on dependent entities.
  """
  def analyze_dependency_impact(entity, changes) do
    dependencies = identify_entity_dependencies(entity)

    %{
      dependent_count: length(dependencies),
      critical_dependencies: filter_critical_dependencies(dependencies),
      cascade_effects: predict_cascade_effects(dependencies, changes),
      breaking_changes: identify_breaking_changes(dependencies, changes),
      dependency_graph: build_dependency_graph(entity, dependencies)
    }
  end

  defp identify_entity_dependencies(entity) do
    case entity[:type] || entity.__struct__ do
      :user -> [:sessions, :projects, :preferences, :activity_logs]
      :project -> [:code_files, :analyses, :collaborators, :deployments]
      :code_file -> [:project, :imports, :tests, :dependencies]
      :analysis -> [:target_entity, :results_cache, :reports]
      _ -> []
    end
  end

  defp filter_critical_dependencies(dependencies) do
    critical = [:sessions, :project, :target_entity, :deployments]
    Enum.filter(dependencies, &(&1 in critical))
  end

  defp predict_cascade_effects(dependencies, changes) do
    Enum.map(dependencies, fn dep ->
      %{
        dependency: dep,
        effect_type: determine_effect_type(dep, changes),
        severity: determine_effect_severity(dep, changes),
        propagation_required: requires_propagation?(dep, changes)
      }
    end)
  end

  defp determine_effect_type(dependency, _changes) do
    case dependency do
      :sessions -> :invalidation
      :code_files -> :revalidation
      :analyses -> :recomputation
      :deployments -> :rollback
      :results_cache -> :flush
      _ -> :notification
    end
  end

  defp determine_effect_severity(dependency, changes) do
    severity = get_change_severity(changes)

    case {dependency, severity} do
      {:deployments, :critical} -> :critical
      {:sessions, :high} -> :high
      {_, :critical} -> :high
      {_, severity} -> severity
    end
  end

  defp requires_propagation?(dependency, _changes) do
    dependency in [:code_files, :analyses, :deployments]
  end

  defp identify_breaking_changes(dependencies, changes) do
    breaking = []

    changes_map = get_changes_map(changes)

    breaking =
      if Map.has_key?(changes_map, :path) and :code_files in dependencies do
        [{:path_change, :affects_imports} | breaking]
      else
        breaking
      end

    breaking =
      if Map.has_key?(changes_map, :api_version) and :deployments in dependencies do
        [{:api_version_change, :requires_migration} | breaking]
      else
        breaking
      end

    breaking
  end

  defp get_changes_map(%{changes: changes}) when is_map(changes), do: changes
  defp get_changes_map(changes) when is_map(changes), do: changes
  defp get_changes_map(_), do: %{}

  defp build_dependency_graph(entity, dependencies) do
    %{
      root: entity[:id] || entity[:type],
      nodes: dependencies,
      edges: Enum.map(dependencies, fn dep -> {entity[:type], dep} end)
    }
  end

  @doc """
  Estimates the performance impact of changes.
  """
  def estimate_performance_impact(_entity, changes) do
    change_size = calculate_change_size(changes)

    %{
      expected_latency_change: estimate_latency_impact(change_size),
      memory_impact: estimate_memory_impact(change_size),
      throughput_impact: estimate_throughput_impact(count_affected_fields(changes)),
      resource_usage_change: estimate_resource_change(change_size),
      optimization_opportunities: identify_optimization_opportunities(changes)
    }
  end

  defp calculate_change_size(changes) do
    changes_map = get_changes_map(changes)

    changes_map
    |> Map.values()
    |> Enum.map(&estimate_value_size/1)
    |> Enum.sum()
  end

  defp estimate_value_size(value) when is_binary(value), do: byte_size(value)
  defp estimate_value_size(value) when is_map(value), do: map_size(value) * 100
  defp estimate_value_size(value) when is_list(value), do: length(value) * 50
  defp estimate_value_size(value) when is_atom(value), do: 20
  defp estimate_value_size(value) when is_number(value), do: 8
  defp estimate_value_size(_), do: 10

  defp estimate_latency_impact(size) when size < 1_000, do: "< 1ms"
  defp estimate_latency_impact(size) when size < 10_000, do: "1-10ms"
  defp estimate_latency_impact(size) when size < 100_000, do: "10-100ms"
  defp estimate_latency_impact(_), do: "> 100ms"

  defp estimate_memory_impact(size) when size < 1_000, do: "negligible"
  defp estimate_memory_impact(size) when size < 10_000, do: "< 10KB"
  defp estimate_memory_impact(size) when size < 100_000, do: "10-100KB"
  defp estimate_memory_impact(size) when size < 1_000_000, do: "100KB-1MB"
  defp estimate_memory_impact(_), do: "> 1MB"

  defp estimate_throughput_impact(field_count) when field_count <= 5, do: "no impact"
  defp estimate_throughput_impact(field_count) when field_count <= 20, do: "minimal impact"
  defp estimate_throughput_impact(field_count) when field_count <= 50, do: "moderate impact"
  defp estimate_throughput_impact(_), do: "significant impact"

  defp estimate_resource_change(size) when size < 10_000, do: "minimal"
  defp estimate_resource_change(size) when size < 100_000, do: "moderate"
  defp estimate_resource_change(_), do: "significant"

  defp identify_optimization_opportunities(changes) do
    opportunities = []

    changes_map = get_changes_map(changes)

    opportunities =
      if map_size(changes_map) > 10 do
        [:batch_processing | opportunities]
      else
        opportunities
      end

    opportunities =
      if Enum.any?(Map.values(changes_map), &is_list/1) do
        [:parallel_processing | opportunities]
      else
        opportunities
      end

    opportunities
  end

  @doc """
  Assesses system-wide impact of changes.
  """
  def assess_system_wide_impact(entity, changes) do
    %{
      cache_invalidation_required: requires_cache_invalidation?(entity, changes),
      index_updates_needed: requires_index_updates?(entity, changes),
      notification_scope: determine_notification_scope(entity, changes),
      audit_trail_impact: assess_audit_impact(changes),
      replication_impact: assess_replication_impact(entity, changes)
    }
  end

  defp requires_cache_invalidation?(entity, changes) do
    entity_type = entity[:type] || :unknown
    changes_map = get_changes_map(changes)

    # Cache invalidation rules
    case entity_type do
      :user -> Map.has_key?(changes_map, :preferences) or Map.has_key?(changes_map, :permissions)
      :project -> Map.has_key?(changes_map, :status) or Map.has_key?(changes_map, :visibility)
      :code_file -> Map.has_key?(changes_map, :content) or Map.has_key?(changes_map, :path)
      _ -> map_size(changes_map) > 0
    end
  end

  defp requires_index_updates?(entity, changes) do
    indexed_fields = get_indexed_fields(entity[:type])
    changes_map = get_changes_map(changes)

    Enum.any?(Map.keys(changes_map), &(&1 in indexed_fields))
  end

  defp get_indexed_fields(entity_type) do
    case entity_type do
      :user -> [:email, :username]
      :project -> [:name, :status]
      :code_file -> [:path, :language]
      :analysis -> [:type, :status]
      _ -> []
    end
  end

  defp determine_notification_scope(entity, changes) do
    severity = get_change_severity(changes)

    case {entity[:type], severity} do
      {_, :critical} -> :organization
      {:project, :high} -> :team
      {:user, _} -> :user
      _ -> :none
    end
  end

  defp assess_audit_impact(changes) do
    changes_map = get_changes_map(changes)

    %{
      audit_required: map_size(changes_map) > 0,
      audit_level: determine_audit_level(changes),
      retention_period: determine_retention_period(changes)
    }
  end

  defp determine_audit_level(changes) do
    case get_change_severity(changes) do
      :critical -> :detailed
      :high -> :standard
      _ -> :minimal
    end
  end

  defp determine_retention_period(changes) do
    case get_change_severity(changes) do
      :critical -> :permanent
      :high -> :long_term
      _ -> :standard
    end
  end

  defp assess_replication_impact(entity, _changes) do
    case entity[:type] do
      :user -> :immediate
      :project -> :eventual
      _ -> :none
    end
  end

  @doc """
  Assesses risks associated with the update.
  """
  def assess_update_risks(entity, changes) do
    risks = []

    # Data loss risk
    risks =
      if has_data_loss_risk?(entity, changes) do
        [{:data_loss, :high} | risks]
      else
        risks
      end

    # Consistency risk
    risks =
      if has_consistency_risk?(entity, changes) do
        [{:consistency, :medium} | risks]
      else
        risks
      end

    # Performance degradation risk
    risks =
      if has_performance_risk?(changes) do
        [{:performance, :medium} | risks]
      else
        risks
      end

    # Security risk
    risks =
      if has_security_risk?(entity, changes) do
        [{:security, :critical} | risks]
      else
        risks
      end

    %{
      identified_risks: risks,
      risk_level: calculate_risk_level(risks),
      mitigation_required: length(risks) > 0,
      risk_matrix: build_risk_matrix(risks)
    }
  end

  defp has_data_loss_risk?(_entity, changes) do
    changes_map = get_changes_map(changes)

    # Check if we're overwriting non-empty values with empty ones
    Enum.any?(changes_map, fn {_key, value} ->
      case value do
        "" -> true
        nil -> true
        [] -> true
        %{} -> true
        _ -> false
      end
    end)
  end

  defp has_consistency_risk?(entity, changes) do
    # Risk if changing indexed or unique fields
    indexed_fields = get_indexed_fields(entity[:type])
    changes_map = get_changes_map(changes)

    Enum.any?(Map.keys(changes_map), &(&1 in indexed_fields))
  end

  defp has_performance_risk?(changes) do
    change_size = calculate_change_size(changes)
    change_size > 100_000
  end

  defp has_security_risk?(entity, changes) do
    sensitive_fields = get_sensitive_fields(entity[:type])
    changes_map = get_changes_map(changes)

    Enum.any?(Map.keys(changes_map), &(&1 in sensitive_fields))
  end

  defp get_sensitive_fields(entity_type) do
    case entity_type do
      :user -> [:password_hash, :api_key, :permissions]
      :project -> [:api_keys, :secrets]
      _ -> []
    end
  end

  defp calculate_risk_level(risks) do
    if Enum.any?(risks, fn {_type, level} -> level == :critical end) do
      :critical
    else
      risk_count = length(risks)

      cond do
        risk_count == 0 -> :none
        risk_count == 1 -> :low
        risk_count <= 3 -> :medium
        true -> :high
      end
    end
  end

  defp build_risk_matrix(risks) do
    %{
      by_type: Enum.group_by(risks, fn {type, _} -> type end),
      by_level: Enum.group_by(risks, fn {_, level} -> level end)
    }
  end

  @doc """
  Identifies entities affected by the changes.
  """
  def identify_affected_entities(entity, _changes) do
    case entity[:type] do
      :user ->
        [
          {:sessions, entity[:id], :invalidate},
          {:preferences, entity[:id], :update},
          {:activity_logs, entity[:id], :append}
        ]

      :project ->
        [
          {:code_files, entity[:id], :revalidate},
          {:analyses, entity[:id], :recompute},
          {:deployments, entity[:id], :check}
        ]

      :code_file ->
        [
          {:project, entity[:project_id], :update_metrics},
          {:analyses, entity[:id], :invalidate},
          {:dependencies, entity[:id], :revalidate}
        ]

      :analysis ->
        [
          {:target, entity[:target_id], :notify},
          {:reports, entity[:id], :regenerate}
        ]

      _ ->
        []
    end
  end

  @doc """
  Analyzes propagation requirements for changes.
  """
  def analyze_propagation_requirements(entity, changes) do
    %{
      propagation_needed: needs_propagation?(entity, changes),
      propagation_strategy: determine_propagation_strategy(entity, changes),
      propagation_order: determine_propagation_order(entity),
      propagation_timeout: calculate_propagation_timeout(changes)
    }
  end

  defp needs_propagation?(entity, changes) do
    entity_type = entity[:type]
    severity = get_change_severity(changes)

    entity_type in [:project, :code_file] and severity in [:high, :critical]
  end

  defp determine_propagation_strategy(_entity, changes) do
    case get_change_severity(changes) do
      :critical -> :immediate
      :high -> :queued
      _ -> :lazy
    end
  end

  defp determine_propagation_order(entity) do
    case entity[:type] do
      :user -> [:sessions, :preferences, :projects]
      :project -> [:deployments, :code_files, :analyses]
      _ -> []
    end
  end

  defp calculate_propagation_timeout(changes) do
    case get_change_severity(changes) do
      :critical -> 5_000
      :high -> 30_000
      _ -> 60_000
    end
  end

  @doc """
  Calculates overall impact score from all impact dimensions.
  """
  def calculate_overall_impact_score(impact) do
    scores = [
      score_direct_impact(impact.direct_impact),
      score_dependency_impact(impact.dependency_impact),
      score_performance_impact(impact.performance_impact),
      score_system_impact(impact.system_impact),
      score_risk_assessment(impact.risk_assessment)
    ]

    # Weighted average
    (Enum.sum(scores) / length(scores)) |> Float.round(2)
  end

  defp score_direct_impact(direct) do
    field_score = min(direct.fields_affected * 0.1, 1.0)
    severity_score = severity_to_score(direct.severity)

    (field_score + severity_score) / 2
  end

  defp score_dependency_impact(dependency) do
    dep_score = min(dependency.dependent_count * 0.1, 1.0)
    critical_score = length(dependency.critical_dependencies) * 0.3
    breaking_score = length(dependency.breaking_changes) * 0.5

    min((dep_score + critical_score + breaking_score) / 3, 1.0)
  end

  defp score_performance_impact(performance) do
    case performance.expected_latency_change do
      "< 1ms" -> 0.1
      "1-10ms" -> 0.3
      "10-100ms" -> 0.6
      _ -> 0.9
    end
  end

  defp score_system_impact(system) do
    score = 0.0
    score = if system.cache_invalidation_required, do: score + 0.3, else: score
    score = if system.index_updates_needed, do: score + 0.3, else: score
    score = if system.notification_scope != :none, do: score + 0.2, else: score
    min(score, 1.0)
  end

  defp score_risk_assessment(risk) do
    case risk.risk_level do
      :none -> 0.0
      :low -> 0.3
      :medium -> 0.6
      :high -> 0.8
      :critical -> 1.0
    end
  end

  defp severity_to_score(severity) do
    case severity do
      :minimal -> 0.1
      :low -> 0.3
      :medium -> 0.5
      :high -> 0.7
      :critical -> 1.0
      _ -> 0.5
    end
  end

  @doc """
  Generates recommendations based on impact analysis.
  """
  def generate_impact_recommendations(impact) do
    recommendations = []

    # Direct impact recommendations
    recommendations =
      if impact.direct_impact.fields_affected > 10 do
        ["Consider batching changes" | recommendations]
      else
        recommendations
      end

    # Dependency recommendations
    recommendations =
      if length(impact.dependency_impact.critical_dependencies) > 0 do
        ["Monitor critical dependencies during update" | recommendations]
      else
        recommendations
      end

    # Performance recommendations
    recommendations =
      case impact.performance_impact.expected_latency_change do
        "> 100ms" -> ["Consider async processing" | recommendations]
        "10-100ms" -> ["Consider caching strategy" | recommendations]
        _ -> recommendations
      end

    # Risk recommendations
    recommendations =
      if impact.risk_assessment.mitigation_required do
        ["Implement rollback strategy" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  @doc """
  Suggests mitigation strategies based on identified impacts.
  """
  def suggest_mitigation_strategies(impact) do
    strategies = []

    # Risk mitigation
    strategies =
      case impact.risk_assessment.risk_level do
        :critical -> ["Create backup before update", "Prepare rollback plan" | strategies]
        :high -> ["Monitor closely after update" | strategies]
        _ -> strategies
      end

    # Performance mitigation
    strategies =
      if impact.performance_impact.resource_usage_change == "significant" do
        ["Scale resources temporarily", "Implement rate limiting" | strategies]
      else
        strategies
      end

    # System impact mitigation
    strategies =
      if impact.system_impact.cache_invalidation_required do
        ["Warm cache after update" | strategies]
      else
        strategies
      end

    strategies
  end

  @doc """
  Identifies safe rollback points based on impact analysis.
  """
  def identify_rollback_points(impact) do
    points = []

    points =
      if impact.direct_impact.fields_affected > 0 do
        [{:before_field_updates, :snapshot_required} | points]
      else
        points
      end

    points =
      if length(impact.dependency_impact.breaking_changes) > 0 do
        [{:before_dependency_updates, :dependency_snapshot} | points]
      else
        points
      end

    points =
      if impact.system_impact.index_updates_needed do
        [{:before_index_updates, :index_backup} | points]
      else
        points
      end

    Enum.reverse(points)
  end

  defp predict_immediate_effects(_entity, _changes) do
    [:cache_invalidation, :index_update, :audit_log_entry]
  end

  defp assess_data_integrity_impact(%{validations: validations}) do
    if validations[:constraint_validation][:valid] do
      :minimal
    else
      :significant
    end
  end

  defp assess_data_integrity_impact(_), do: :unknown
end
