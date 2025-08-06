defmodule RubberDuck.Actions.Core.CreateEntity do
  @moduledoc """
  Core agentic action for creating entities with goal-driven validation and learning integration.

  This action provides:
  - Generic entity creation across all domain types
  - Goal-driven validation aligned with agent objectives
  - Learning from creation outcomes to improve future decisions
  - Dynamic skill orchestration based on entity type
  - Impact assessment for entity creation
  """

  use Jido.Action,
    name: "create_entity",
    description: "Creates entities with goal-driven validation and learning",
    schema: [
      entity_type: [type: :atom, required: true, values: [:user, :project, :code_file, :analysis]],
      entity_data: [type: :map, required: true],
      agent_goals: [type: {:list, :map}, default: []],
      validation_config: [type: :map, default: %{}],
      learning_enabled: [type: :boolean, default: true],
      skill_hints: [type: {:list, :atom}, default: []],
      parent_entity: [type: :map, required: false]
    ]

  # Aliases reserved for future integration with actual contexts
  require Logger

  @impl true
  def run(params, context) do
    with {:ok, validated_data} <- validate_with_goals(params, context),
         {:ok, pre_assessment} <- assess_creation_impact(params, context),
         {:ok, entity} <- create_entity(validated_data, context),
         {:ok, post_validation} <- post_creation_validation(entity, params),
         {:ok, learning_data} <- track_creation_outcome(entity, params, context) do

      {:ok, %{
        entity: entity,
        entity_type: params.entity_type,
        validation_results: validated_data,
        impact_assessment: pre_assessment,
        post_validation: post_validation,
        learning_data: learning_data,
        goal_alignment_score: calculate_goal_alignment(entity, params.agent_goals),
        metadata: build_metadata(params, context)
      }}
    end
  end

  # Goal-driven validation
  defp validate_with_goals(params, _context) do
    # Start with basic validation
    validation_results = %{
      basic: validate_basic_requirements(params.entity_data, params.entity_type),
      goals: validate_goal_alignment(params.entity_data, params.agent_goals),
      constraints: validate_constraints(params.entity_data, params.validation_config),
      skills: validate_with_skills(params)
    }

    # Check if all validations passed
    all_valid = validation_results
      |> Map.values()
      |> Enum.all?(& &1.valid)

    if all_valid do
      {:ok, %{
        data: enrich_entity_data(params.entity_data, validation_results),
        validations: validation_results,
        confidence: calculate_validation_confidence(validation_results)
      }}
    else
      {:error, %{
        reason: :validation_failed,
        failures: extract_validation_failures(validation_results),
        suggestions: generate_correction_suggestions(validation_results, params)
      }}
    end
  end

  defp validate_basic_requirements(data, entity_type) do
    required_fields = case entity_type do
      :user -> [:email, :username]
      :project -> [:name, :description]
      :code_file -> [:path, :content]
      :analysis -> [:type, :target]
    end

    missing_fields = required_fields -- Map.keys(data)

    %{
      valid: Enum.empty?(missing_fields),
      missing_fields: missing_fields,
      data_completeness: (length(required_fields) - length(missing_fields)) / length(required_fields)
    }
  end

  defp validate_goal_alignment(data, agent_goals) do
    if Enum.empty?(agent_goals) do
      %{valid: true, score: 1.0, reason: :no_goals_specified}
    else
      alignment_scores = Enum.map(agent_goals, fn goal ->
        evaluate_goal_alignment(data, goal)
      end)

      avg_score = if length(alignment_scores) > 0 do
        Enum.sum(alignment_scores) / length(alignment_scores)
      else
        1.0
      end

      %{
        valid: avg_score >= 0.7,
        score: avg_score,
        goal_count: length(agent_goals),
        aligned_goals: Enum.count(alignment_scores, & &1 >= 0.7)
      }
    end
  end

  defp evaluate_goal_alignment(data, goal) do
    # Evaluate how well the entity data aligns with a specific goal
    case goal.type do
      :quality ->
        evaluate_quality_goal(data, goal)
      :performance ->
        evaluate_performance_goal(data, goal)
      :learning ->
        evaluate_learning_goal(data, goal)
      _ ->
        0.5  # Neutral score for unknown goal types
    end
  end

  defp evaluate_quality_goal(data, goal) do
    quality_indicators = [
      has_documentation?(data),
      has_tests?(data),
      meets_complexity_target?(data, goal[:max_complexity])
    ]

    Enum.count(quality_indicators, & &1) / length(quality_indicators)
  end

  defp evaluate_performance_goal(data, goal) do
    # Evaluate performance-related aspects
    if data[:estimated_performance] do
      target = goal[:target_performance] || 100
      min(1.0, data.estimated_performance / target)
    else
      0.5
    end
  end

  defp evaluate_learning_goal(data, _goal) do
    # Evaluate learning potential
    if data[:learning_enabled] do
      1.0
    else
      0.3
    end
  end

  defp validate_constraints(data, config) do
    constraints = config[:constraints] || %{}

    violations = Enum.reduce(constraints, [], fn {field, constraint}, acc ->
      if violates_constraint?(data[field], constraint) do
        [{field, constraint} | acc]
      else
        acc
      end
    end)

    %{
      valid: Enum.empty?(violations),
      violations: violations,
      checked_constraints: map_size(constraints)
    }
  end

  defp violates_constraint?(nil, %{required: true}), do: true
  defp violates_constraint?(value, %{min: min}) when is_number(value), do: value < min
  defp violates_constraint?(value, %{max: max}) when is_number(value), do: value > max
  defp violates_constraint?(value, %{pattern: pattern}) when is_binary(value) do
    not Regex.match?(pattern, value)
  end
  defp violates_constraint?(_, _), do: false

  defp validate_with_skills(params) do
    # Use appropriate skill for validation based on entity type
    skill_result = case params.entity_type do
      :user ->
        # Simulate skill validation via signals
        %{valid: true, skill: :user_management, confidence: 0.9}
      :project ->
        %{valid: true, skill: :project_management, confidence: 0.85}
      :code_file ->
        %{valid: true, skill: :code_analysis, confidence: 0.88}
      :analysis ->
        %{valid: true, skill: :ai_analysis, confidence: 0.92}
    end

    skill_result
  end

  defp enrich_entity_data(data, validation_results) do
    data
    |> Map.put(:validation_score, calculate_validation_score(validation_results))
    |> Map.put(:created_at, DateTime.utc_now())
    |> Map.put(:enrichments, extract_enrichments(validation_results))
  end

  defp calculate_validation_score(results) do
    scores = [
      if(results.basic.valid, do: 1.0, else: 0.0),
      results.goals[:score] || 1.0,
      if(results.constraints.valid, do: 1.0, else: 0.5),
      results.skills[:confidence] || 0.8
    ]

    Enum.sum(scores) / length(scores)
  end

  defp calculate_validation_confidence(results) do
    # Calculate overall confidence in validation
    base_confidence = calculate_validation_score(results)

    # Adjust based on completeness
    completeness_factor = results.basic[:data_completeness] || 1.0

    base_confidence * completeness_factor
  end

  defp extract_validation_failures(results) do
    failures = []

    failures = if results.basic.valid do
      failures
    else
      [{:basic, results.basic.missing_fields} | failures]
    end

    failures = if results.goals.valid do
      failures
    else
      [{:goals, "Low goal alignment: #{results.goals.score}"} | failures]
    end

    failures = if results.constraints.valid do
      failures
    else
      [{:constraints, results.constraints.violations} | failures]
    end

    failures
  end

  defp generate_correction_suggestions(results, _params) do
    suggestions = []

    suggestions = if results.basic.valid do
      suggestions
    else
      ["Add missing fields: #{Enum.join(results.basic.missing_fields, ", ")}" | suggestions]
    end

    suggestions = if results.goals[:score] && results.goals.score < 0.7 do
      ["Improve goal alignment by adjusting entity properties" | suggestions]
    else
      suggestions
    end

    suggestions
  end

  # Impact assessment
  defp assess_creation_impact(params, _context) do
    impact = %{
      resource_usage: estimate_resource_usage(params.entity_type, params.entity_data),
      dependencies: identify_dependencies(params),
      side_effects: predict_side_effects(params.entity_type, params.entity_data),
      system_load: estimate_system_load(params.entity_type),
      risk_level: assess_risk_level(params)
    }

    {:ok, impact}
  end

  defp estimate_resource_usage(entity_type, data) do
    base_usage = case entity_type do
      :user -> %{memory: 1, cpu: 1, storage: 10}
      :project -> %{memory: 5, cpu: 2, storage: 100}
      :code_file -> %{memory: 2, cpu: 3, storage: data[:content] && byte_size(data.content) || 1_000}
      :analysis -> %{memory: 10, cpu: 8, storage: 50}
    end

    %{
      estimated: base_usage,
      unit: :mb_per_minute
    }
  end

  defp identify_dependencies(params) do
    deps = []

    deps = if params[:parent_entity] do
      [{:parent, params.parent_entity.type, params.parent_entity.id} | deps]
    else
      deps
    end

    deps = case params.entity_type do
      :code_file -> [{:project, :required} | deps]
      :analysis -> [{:target, :required} | deps]
      _ -> deps
    end

    deps
  end

  defp predict_side_effects(entity_type, _data) do
    case entity_type do
      :user -> [:session_creation, :preference_initialization]
      :project -> [:directory_structure_creation, :git_initialization]
      :code_file -> [:dependency_updates, :test_generation]
      :analysis -> [:cache_invalidation, :notification_triggers]
    end
  end

  defp estimate_system_load(entity_type) do
    case entity_type do
      :analysis -> :high
      :project -> :medium
      :code_file -> :low
      :user -> :minimal
    end
  end

  defp assess_risk_level(params) do
    risk_factors = []

    risk_factors = if params[:validation_config][:skip_validation] do
      [:validation_skipped | risk_factors]
    else
      risk_factors
    end

    risk_factors = if params[:learning_enabled] == false do
      [:learning_disabled | risk_factors]
    else
      risk_factors
    end

    cond do
      length(risk_factors) >= 2 -> :high
      length(risk_factors) == 1 -> :medium
      true -> :low
    end
  end

  # Entity creation
  defp create_entity(validated_data, context) do
    entity_data = validated_data.data

    result = case entity_data[:entity_type] || determine_entity_type(entity_data) do
      :user ->
        create_user_entity(entity_data, context)
      :project ->
        create_project_entity(entity_data, context)
      :code_file ->
        create_code_file_entity(entity_data, context)
      :analysis ->
        create_analysis_entity(entity_data, context)
      _ ->
        {:error, :unknown_entity_type}
    end

    case result do
      {:ok, entity} ->
        {:ok, add_entity_metadata(entity, validated_data)}
      error ->
        error
    end
  end

  defp determine_entity_type(data) do
    cond do
      data[:email] -> :user
      data[:project_name] -> :project
      data[:file_path] -> :code_file
      data[:analysis_type] -> :analysis
      true -> :unknown
    end
  end

  defp create_user_entity(data, context) do
    # Simulate user creation (would integrate with Accounts context)
    {:ok, %{
      id: generate_entity_id(),
      type: :user,
      email: data.email,
      username: data.username,
      created_by: context[:actor],
      created_at: DateTime.utc_now()
    }}
  end

  defp create_project_entity(data, context) do
    # Simulate project creation
    {:ok, %{
      id: generate_entity_id(),
      type: :project,
      name: data.name,
      description: data.description,
      owner_id: context[:actor] && context.actor.id,
      created_at: DateTime.utc_now()
    }}
  end

  defp create_code_file_entity(data, _context) do
    # Simulate code file creation
    {:ok, %{
      id: generate_entity_id(),
      type: :code_file,
      path: data.path,
      content: data.content,
      language: detect_language(data.path),
      project_id: data[:project_id],
      created_at: DateTime.utc_now()
    }}
  end

  defp create_analysis_entity(data, context) do
    # Simulate analysis creation
    {:ok, %{
      id: generate_entity_id(),
      type: :analysis,
      analysis_type: data.type,
      target: data.target,
      status: :pending,
      created_by: context[:actor],
      created_at: DateTime.utc_now()
    }}
  end

  defp generate_entity_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp detect_language(path) when is_binary(path) do
    cond do
      String.ends_with?(path, ".ex") -> :elixir
      String.ends_with?(path, ".exs") -> :elixir
      String.ends_with?(path, ".js") -> :javascript
      String.ends_with?(path, ".py") -> :python
      true -> :unknown
    end
  end
  defp detect_language(_), do: :unknown

  defp add_entity_metadata(entity, validated_data) do
    entity
    |> Map.put(:validation_score, validated_data[:confidence])
    |> Map.put(:goal_aligned, validated_data.validations.goals[:valid])
  end

  # Post-creation validation
  defp post_creation_validation(entity, params) do
    validations = %{
      exists: verify_entity_exists(entity),
      accessible: verify_entity_accessible(entity),
      complete: verify_entity_complete(entity, params.entity_type),
      functional: verify_entity_functional(entity)
    }

    all_valid = validations |> Map.values() |> Enum.all?(& &1)

    {:ok, %{
      valid: all_valid,
      checks: validations,
      entity_id: entity.id
    }}
  end

  defp verify_entity_exists(entity) do
    entity.id != nil
  end

  defp verify_entity_accessible(_entity) do
    # In real implementation, would check actual accessibility
    true
  end

  defp verify_entity_complete(entity, entity_type) do
    required_fields = case entity_type do
      :user -> [:id, :email, :username]
      :project -> [:id, :name, :description]
      :code_file -> [:id, :path, :content]
      :analysis -> [:id, :type, :target]
    end

    Enum.all?(required_fields, &Map.has_key?(entity, &1))
  end

  defp verify_entity_functional(_entity) do
    # In real implementation, would perform functional checks
    true
  end

  # Learning tracking
  defp track_creation_outcome(entity, params, context) do
    if params.learning_enabled do
      learning_data = %{
        entity_id: entity.id,
        entity_type: params.entity_type,
        success: true,
        validation_score: entity[:validation_score] || 1.0,
        goal_alignment: entity[:goal_aligned] || true,
        context: extract_learning_context(params, context),
        timestamp: DateTime.utc_now()
      }

      # In real implementation, would send to LearningSkill
      emit_learning_signal(learning_data)

      {:ok, learning_data}
    else
      {:ok, %{learning_enabled: false}}
    end
  end

  defp extract_learning_context(params, context) do
    %{
      agent: context[:agent],
      goals: params.agent_goals,
      validation_config: params.validation_config,
      skill_hints: params.skill_hints
    }
  end

  defp emit_learning_signal(data) do
    # In real implementation, would emit through Jido signal system
    Logger.debug("Learning signal: entity_creation with data: #{inspect(data)}")
    :ok
  end

  # Goal alignment calculation
  defp calculate_goal_alignment(entity, agent_goals) do
    if Enum.empty?(agent_goals) do
      1.0  # Perfect alignment when no goals specified
    else
      scores = Enum.map(agent_goals, fn goal ->
        calculate_entity_goal_alignment(entity, goal)
      end)

      if length(scores) > 0 do
        Enum.sum(scores) / length(scores)
      else
        0.5
      end
    end
  end

  defp calculate_entity_goal_alignment(entity, goal) do
    # Calculate how well the created entity aligns with the goal
    case goal.type do
      :quality ->
        entity[:validation_score] || 0.8
      :performance ->
        0.7  # Default performance alignment
      :learning ->
        if entity[:learning_enabled], do: 1.0, else: 0.3
      _ ->
        0.5
    end
  end

  # Metadata
  defp build_metadata(params, context) do
    %{
      action: "create_entity",
      entity_type: params.entity_type,
      timestamp: DateTime.utc_now(),
      actor: context[:actor],
      agent: context[:agent],
      learning_enabled: params.learning_enabled,
      goal_count: length(params.agent_goals)
    }
  end

  # Helper functions
  defp has_documentation?(data) do
    data[:documentation] != nil || data[:description] != nil
  end

  defp has_tests?(data) do
    data[:tests] != nil || data[:test_coverage] != nil
  end

  defp meets_complexity_target?(data, max_complexity) do
    if max_complexity && data[:complexity] do
      data.complexity <= max_complexity
    else
      true
    end
  end

  defp extract_enrichments(validation_results) do
    %{
      skill_validated: validation_results.skills[:skill],
      goal_aligned: validation_results.goals[:valid],
      constraints_met: validation_results.constraints.valid
    }
  end
end