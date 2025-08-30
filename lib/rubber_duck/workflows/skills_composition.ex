defmodule RubberDuck.Workflows.SkillsComposition do
  @moduledoc """
  Skills composition patterns for converting Jido Skills into Reactor workflows.

  This module provides utilities for agents to optionally compose their existing
  Skills into sophisticated Reactor workflows when complex coordination is needed.
  Agents maintain full autonomy and can use simple Skills composition or
  workflow orchestration based on their coordination requirements.

  Features:
  - Skills-to-workflow composition with dependency management
  - Preservation of Skills semantics within workflow context
  - Integration with existing Jido Skills, Actions, Instructions, Directives
  - Optional workflow adoption without breaking existing functionality
  - Performance optimization through workflow orchestration
  - Advanced error recovery and compensation patterns

  Composition Patterns:
  - **Skills Chain**: Sequential Skills execution with data flow
  - **Skills Fan-Out**: Parallel Skills execution with result aggregation
  - **Skills Orchestration**: Complex Skills coordination with conditional logic
  - **Skills Pipeline**: Data processing pipeline with transformation stages
  """

  require Logger

  alias RubberDuck.Workflows.{ReactorConfig, WorkflowTemplates}

  @doc """
  Compose Skills into a sequential workflow chain.

  Agents can use this to create workflows from their existing Skills
  when they need sophisticated coordination beyond simple composition.
  """
  def compose_skills_chain(skills_list, composition_config \\ %{}) do
    Logger.debug("SkillsComposition: Composing Skills chain",
      skills_count: length(skills_list),
      config: Map.keys(composition_config)
    )

    with {:ok, validated_skills} <- validate_skills_for_composition(skills_list),
         {:ok, workflow_steps} <- convert_skills_to_workflow_steps(validated_skills, :sequential),
         {:ok, workflow_spec} <- build_skills_workflow_spec(workflow_steps, composition_config) do
      Logger.info("SkillsComposition: Skills chain composed successfully",
        skills_count: length(validated_skills),
        workflow_steps: length(workflow_steps)
      )

      {:ok,
       %{
         workflow_spec: workflow_spec,
         skills_mapped: validated_skills,
         composition_type: :sequential_chain,
         performance_metadata: calculate_composition_performance(validated_skills, :sequential)
       }}
    else
      {:error, reason} ->
        Logger.error("SkillsComposition: Failed to compose Skills chain", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Compose Skills into parallel execution workflow.

  Enables agents to execute multiple Skills concurrently with
  result aggregation and coordinated error handling.
  """
  def compose_skills_parallel(skills_list, aggregation_config \\ %{}) do
    Logger.debug("SkillsComposition: Composing parallel Skills execution")

    with {:ok, validated_skills} <- validate_skills_for_composition(skills_list),
         {:ok, parallel_steps} <- convert_skills_to_workflow_steps(validated_skills, :parallel),
         {:ok, aggregation_step} <- create_aggregation_step(aggregation_config),
         {:ok, workflow_spec} <-
           build_parallel_workflow_spec(parallel_steps, aggregation_step, aggregation_config) do
      Logger.info("SkillsComposition: Parallel Skills composition successful",
        parallel_skills: length(validated_skills)
      )

      {:ok,
       %{
         workflow_spec: workflow_spec,
         skills_mapped: validated_skills,
         composition_type: :parallel_execution,
         aggregation_strategy: Map.get(aggregation_config, :strategy, :merge_results)
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compose Skills into orchestrated workflow with conditional logic.

  Provides sophisticated coordination patterns for complex agent operations
  requiring dynamic execution paths and conditional branching.
  """
  def compose_skills_orchestration(orchestration_spec, composition_config \\ %{}) do
    Logger.debug("SkillsComposition: Creating orchestrated Skills workflow")

    skills_groups = Map.get(orchestration_spec, :skills_groups, %{})
    coordination_logic = Map.get(orchestration_spec, :coordination_logic, %{})

    with {:ok, validated_groups} <- validate_skills_groups(skills_groups),
         {:ok, orchestration_steps} <-
           build_orchestration_steps(validated_groups, coordination_logic),
         {:ok, workflow_spec} <-
           build_orchestration_workflow_spec(orchestration_steps, composition_config) do
      Logger.info("SkillsComposition: Skills orchestration created",
        skills_groups: map_size(validated_groups),
        orchestration_steps: length(orchestration_steps)
      )

      {:ok,
       %{
         workflow_spec: workflow_spec,
         skills_groups: validated_groups,
         composition_type: :orchestrated_coordination,
         coordination_complexity: assess_orchestration_complexity(coordination_logic)
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create Skills processing pipeline workflow.

  Enables agents to create data processing pipelines where each Skill
  transforms data and passes it to the next stage with quality validation.
  """
  def compose_skills_pipeline(pipeline_spec, composition_config \\ %{}) do
    Logger.debug("SkillsComposition: Creating Skills processing pipeline")

    pipeline_stages = Map.get(pipeline_spec, :stages, [])
    transformation_logic = Map.get(pipeline_spec, :transformations, %{})

    with {:ok, validated_stages} <- validate_pipeline_stages(pipeline_stages),
         {:ok, pipeline_steps} <- build_pipeline_steps(validated_stages, transformation_logic),
         {:ok, workflow_spec} <- build_pipeline_workflow_spec(pipeline_steps, composition_config) do
      Logger.info("SkillsComposition: Skills pipeline created",
        pipeline_stages: length(validated_stages)
      )

      {:ok,
       %{
         workflow_spec: workflow_spec,
         pipeline_stages: validated_stages,
         composition_type: :data_pipeline,
         pipeline_efficiency: estimate_pipeline_efficiency(validated_stages)
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp validate_skills_for_composition(skills_list) do
    if Enum.empty?(skills_list) do
      {:error, :no_skills_provided}
    else
      # Validate each skill has required metadata for workflow composition
      validated_skills = Enum.map(skills_list, &validate_single_skill/1)

      # Check if all skills are valid
      invalid_skills = Enum.filter(validated_skills, &(!&1.validated))

      if Enum.empty?(invalid_skills) do
        {:ok, validated_skills}
      else
        {:error, {:invalid_skills, invalid_skills}}
      end
    end
  end

  defp validate_single_skill(skill) do
    case skill do
      %{name: name, action: action} when is_atom(name) and is_atom(action) ->
        Map.merge(skill, %{
          validated: true,
          workflow_compatible: true
        })

      skill_atom when is_atom(skill_atom) ->
        %{
          name: skill_atom,
          action: skill_atom,
          validated: true,
          workflow_compatible: true
        }

      _ ->
        Map.merge(skill, %{
          validated: false,
          workflow_compatible: false,
          issue: :invalid_skill_format
        })
    end
  end

  defp validate_skills_group({group_name, group_skills}) do
    case validate_skills_for_composition(group_skills) do
      {:ok, validated_skills} -> {group_name, validated_skills}
      {:error, _reason} -> {group_name, []}  # Empty group on validation failure
    end
  end

  defp convert_skills_to_workflow_steps(validated_skills, execution_pattern) do
    case execution_pattern do
      :sequential ->
        convert_to_sequential_steps(validated_skills)

      :parallel ->
        convert_to_parallel_steps(validated_skills)

      _ ->
        {:error, {:unsupported_execution_pattern, execution_pattern}}
    end
  end

  defp convert_to_sequential_steps(skills) do
    workflow_steps =
      skills
      |> Enum.with_index()
      |> Enum.map(fn {skill, index} ->
        %{
          name: skill.name,
          action: skill.action,
          step_index: index,
          depends_on: if(index > 0, do: [index - 1], else: []),
          skill_metadata: Map.take(skill, [:validated, :workflow_compatible])
        }
      end)

    {:ok, workflow_steps}
  end

  defp convert_to_parallel_steps(skills) do
    workflow_steps =
      skills
      |> Enum.with_index()
      |> Enum.map(fn {skill, index} ->
        %{
          name: skill.name,
          action: skill.action,
          step_index: index,
          parallel_group: :main_execution,
          skill_metadata: Map.take(skill, [:validated, :workflow_compatible])
        }
      end)

    {:ok, workflow_steps}
  end

  defp build_skills_workflow_spec(workflow_steps, composition_config) do
    workflow_spec = %{
      id: generate_workflow_id("skills_chain"),
      type: :skills_composition,
      steps: workflow_steps,
      composition_metadata: %{
        original_skills_count: length(workflow_steps),
        composition_pattern: :sequential_skills,
        created_at: DateTime.utc_now()
      },
      error_handling: Map.get(composition_config, :error_handling, :comprehensive),
      timeout: Map.get(composition_config, :timeout, 300_000)
    }

    {:ok, workflow_spec}
  end

  defp create_aggregation_step(aggregation_config) do
    strategy = Map.get(aggregation_config, :strategy, :merge_results)

    aggregation_step = %{
      name: :aggregate_parallel_results,
      action: :aggregate_skill_results,
      aggregation_strategy: strategy,
      depends_on: :all_parallel_complete,
      step_type: :aggregation
    }

    {:ok, aggregation_step}
  end

  defp build_parallel_workflow_spec(parallel_steps, aggregation_step, config) do
    all_steps = parallel_steps ++ [aggregation_step]

    workflow_spec = %{
      id: generate_workflow_id("skills_parallel"),
      type: :parallel_skills_composition,
      steps: all_steps,
      composition_metadata: %{
        parallel_skills_count: length(parallel_steps),
        aggregation_strategy: aggregation_step.aggregation_strategy,
        created_at: DateTime.utc_now()
      },
      error_handling: Map.get(config, :error_handling, :partial_recovery),
      timeout: Map.get(config, :timeout, 240_000)
    }

    {:ok, workflow_spec}
  end

  defp validate_skills_groups(skills_groups) do
    if map_size(skills_groups) == 0 do
      {:error, :no_skills_groups}
    else
      # Validate each group
      validated_groups = Map.new(skills_groups, &validate_skills_group/1)

      # Check if any groups have skills
      non_empty_groups =
        Enum.filter(validated_groups, fn {_name, skills} -> not Enum.empty?(skills) end)

      if Enum.empty?(non_empty_groups) do
        {:error, :no_valid_skills_groups}
      else
        {:ok, Map.new(non_empty_groups)}
      end
    end
  end

  defp build_orchestration_steps(skills_groups, coordination_logic) do
    # Build orchestration steps from Skills groups
    group_steps =
      Enum.flat_map(skills_groups, fn {group_name, group_skills} ->
        Enum.with_index(group_skills, fn skill, index ->
          %{
            name: String.to_atom("#{group_name}_#{skill.name}"),
            action: skill.action,
            group: group_name,
            group_index: index,
            skill_metadata: skill
          }
        end)
      end)

    # Add coordination steps
    coordination_steps = build_coordination_steps(coordination_logic, skills_groups)

    all_steps = group_steps ++ coordination_steps
    {:ok, all_steps}
  end

  defp build_coordination_steps(coordination_logic, skills_groups) do
    # Build coordination steps based on logic specification
    coordination_type = Map.get(coordination_logic, :type, :simple_coordination)

    case coordination_type do
      :simple_coordination ->
        [%{name: :coordinate_groups, action: :simple_group_coordination}]

      :conditional_coordination ->
        [
          %{name: :evaluate_conditions, action: :evaluate_coordination_conditions},
          %{name: :execute_conditional_logic, action: :execute_conditional_coordination}
        ]

      :advanced_orchestration ->
        [
          %{name: :analyze_group_dependencies, action: :analyze_dependencies},
          %{name: :optimize_execution_order, action: :optimize_coordination},
          %{name: :monitor_group_execution, action: :monitor_coordination},
          %{name: :handle_coordination_errors, action: :handle_orchestration_errors}
        ]

      _ ->
        []
    end
  end

  defp build_orchestration_workflow_spec(orchestration_steps, config) do
    workflow_spec = %{
      id: generate_workflow_id("skills_orchestration"),
      type: :orchestrated_skills_composition,
      steps: orchestration_steps,
      composition_metadata: %{
        orchestration_steps_count: length(orchestration_steps),
        orchestration_complexity: calculate_orchestration_complexity(orchestration_steps),
        created_at: DateTime.utc_now()
      },
      error_handling: Map.get(config, :error_handling, :orchestrated_recovery),
      timeout: Map.get(config, :timeout, 600_000)
    }

    {:ok, workflow_spec}
  end

  defp validate_pipeline_stages(pipeline_stages) do
    if Enum.empty?(pipeline_stages) do
      {:error, :no_pipeline_stages}
    else
      # Validate pipeline stage format
      validated_stages = Enum.map(pipeline_stages, &validate_pipeline_stage/1)

      invalid_stages = Enum.filter(validated_stages, &(!&1.validated))

      if Enum.empty?(invalid_stages) do
        {:ok, validated_stages}
      else
        {:error, {:invalid_pipeline_stages, invalid_stages}}
      end
    end
  end

  defp validate_pipeline_stage(stage) do
    case stage do
      %{name: _name, skill: _skill, transformation: _transform} ->
        Map.merge(stage, %{validated: true})

      %{name: _name, skill: _skill} ->
        Map.merge(stage, %{validated: true, transformation: :identity})

      _ ->
        Map.merge(stage, %{validated: false, issue: :invalid_stage_format})
    end
  end

  defp build_pipeline_steps(validated_stages, transformation_logic) do
    # Build pipeline steps with data transformation
    pipeline_steps =
      validated_stages
      |> Enum.with_index()
      |> Enum.map(fn {stage, index} ->
        %{
          name: stage.name,
          action: stage.skill,
          stage_index: index,
          transformation: stage.transformation,
          depends_on: if(index > 0, do: [index - 1], else: []),
          pipeline_metadata: %{
            stage_type: Map.get(stage, :type, :processing),
            data_flow: Map.get(transformation_logic, stage.name, :pass_through)
          }
        }
      end)

    {:ok, pipeline_steps}
  end

  defp build_pipeline_workflow_spec(pipeline_steps, config) do
    workflow_spec = %{
      id: generate_workflow_id("skills_pipeline"),
      type: :skills_data_pipeline,
      steps: pipeline_steps,
      composition_metadata: %{
        pipeline_stages_count: length(pipeline_steps),
        pipeline_complexity: calculate_pipeline_complexity(pipeline_steps),
        created_at: DateTime.utc_now()
      },
      error_handling: Map.get(config, :error_handling, :pipeline_recovery),
      timeout: Map.get(config, :timeout, 420_000)
    }

    {:ok, workflow_spec}
  end

  # Performance and complexity assessment

  defp calculate_composition_performance(skills, execution_pattern) do
    # Estimate performance characteristics of Skills composition
    base_performance = %{
      estimated_execution_time: estimate_skills_execution_time(skills),
      memory_requirements: estimate_memory_requirements(skills),
      cpu_intensity: estimate_cpu_intensity(skills),
      coordination_overhead: estimate_coordination_overhead(execution_pattern, length(skills))
    }

    # Pattern-specific adjustments
    pattern_adjustment =
      case execution_pattern do
        :sequential -> %{parallelization_opportunity: 0.0, coordination_complexity: 0.3}
        :parallel -> %{parallelization_opportunity: 0.8, coordination_complexity: 0.6}
        :orchestrated -> %{parallelization_opportunity: 0.6, coordination_complexity: 0.9}
        :pipeline -> %{parallelization_opportunity: 0.4, coordination_complexity: 0.5}
      end

    Map.merge(base_performance, pattern_adjustment)
  end

  defp estimate_skills_execution_time(skills) do
    # Simple estimation based on Skills count and complexity
    # 1 second base time
    base_time_per_skill = 1000
    # Additional time for coordination
    complexity_factor = length(skills) * 0.1

    estimated_time = length(skills) * base_time_per_skill * (1 + complexity_factor)
    round(estimated_time)
  end

  defp estimate_memory_requirements(skills) do
    # Estimate memory needs for Skills composition
    # 10MB base
    base_memory_per_skill = 10
    # 2MB per skill for coordination
    coordination_memory = length(skills) * 2

    base_memory_per_skill * length(skills) + coordination_memory
  end

  defp estimate_cpu_intensity(skills) do
    # Estimate CPU intensity (0.0 - 1.0)
    # More skills = higher intensity
    base_intensity = min(length(skills) / 10, 0.8)
    # Coordination overhead
    coordination_intensity = min(length(skills) * 0.05, 0.2)

    min(base_intensity + coordination_intensity, 1.0)
  end

  defp estimate_coordination_overhead(pattern, skills_count) do
    # Estimate coordination overhead based on pattern
    base_overhead =
      case pattern do
        # Low overhead
        :sequential -> 0.1
        # Moderate overhead for synchronization
        :parallel -> 0.3
        # High overhead for complex coordination
        :orchestrated -> 0.5
        # Moderate overhead for data flow
        :pipeline -> 0.2
      end

    # Scale with skills count
    scaled_overhead = base_overhead * (1 + skills_count * 0.05)
    # Cap at 80% overhead
    min(scaled_overhead, 0.8)
  end

  defp calculate_orchestration_complexity(coordination_logic) do
    # Calculate complexity of orchestration logic
    logic_type = Map.get(coordination_logic, :type, :simple)
    conditions = length(Map.get(coordination_logic, :conditions, []))
    branches = length(Map.get(coordination_logic, :branches, []))

    base_complexity =
      case logic_type do
        :simple -> 0.2
        :conditional -> 0.5
        :advanced -> 0.8
      end

    complexity_factors = conditions * 0.1 + branches * 0.15
    total_complexity = base_complexity + complexity_factors

    Float.round(min(total_complexity, 1.0), 2)
  end

  defp calculate_pipeline_complexity(pipeline_steps) do
    # Calculate complexity of data pipeline
    # Normalize to 10 steps
    steps_complexity = length(pipeline_steps) / 10

    transformation_complexity =
      Enum.count(pipeline_steps, &(&1.transformation != :identity)) /
        max(length(pipeline_steps), 1)

    total_complexity = (steps_complexity + transformation_complexity) / 2
    Float.round(min(total_complexity, 1.0), 2)
  end

  defp assess_orchestration_complexity(coordination_logic) do
    conditions_count = length(Map.get(coordination_logic, :conditions, []))
    branches_count = length(Map.get(coordination_logic, :branches, []))

    # Normalize
    complexity_score = (conditions_count + branches_count) / 10
    Float.round(min(complexity_score, 1.0), 2)
  end

  defp estimate_pipeline_efficiency(stages) do
    # Estimate pipeline processing efficiency
    transformation_stages = Enum.count(stages, &Map.has_key?(&1, :transformation))
    total_stages = length(stages)

    if total_stages > 0 do
      # Transformations add overhead
      efficiency = 1.0 - transformation_stages / total_stages * 0.2
      Float.round(max(efficiency, 0.1), 2)
    else
      0.0
    end
  end

  defp generate_workflow_id(prefix) do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}_#{timestamp}_#{random}"
  end
end
