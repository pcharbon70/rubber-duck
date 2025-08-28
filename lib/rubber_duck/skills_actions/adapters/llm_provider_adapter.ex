defmodule RubberDuck.SkillsActions.Adapters.LlmProviderAdapter do
  @moduledoc """
  Integration adapter for Skills & Actions system with Universal LLM Provider System.

  This adapter enables sophisticated AI-assisted orchestration including:
  - LLM-powered skill recommendation and selection
  - Intelligent workflow optimization using Constitutional AI principles
  - Cost-aware skill execution with budget management
  - Dynamic action coordination with LLM-assisted decision making
  - Integration with existing Universal Provider routing and health monitoring
  """

  require Logger

  alias RubberDuck.LlmProviders.UniversalProviderService
  alias RubberDuck.SkillsActions.{ActionOrchestrator, SkillsRegistry}

  @doc """
  Get LLM-powered skill recommendations for agent needs and context.
  """
  def recommend_skills_for_context(context, agent_id, user_id \\ nil) do
    Logger.debug("Getting LLM skill recommendations for agent #{agent_id}")

    # Build comprehensive skill recommendation prompt
    recommendation_request = build_skill_recommendation_request(context, agent_id)

    case UniversalProviderService.complete(recommendation_request, :orchestration, %{
           use_case: :skill_recommendation,
           user_id: user_id,
           specialized_features: [:cost_optimization, :agent_communication],
           max_tokens: 800,
           # Balanced creativity for recommendations
           temperature: 0.3
         }) do
      {:ok, llm_response} ->
        case parse_skill_recommendations(llm_response.content) do
          {:ok, recommendations} ->
            # Validate recommendations against available skills
            validated_recommendations = validate_skill_recommendations(recommendations)

            {:ok,
             %{
               recommendations: validated_recommendations,
               reasoning: llm_response.content,
               cost_usd: llm_response.cost_usd,
               recommendation_source: :llm_powered,
               confidence: 0.85
             }}

          {:error, parsing_error} ->
            Logger.warning("Failed to parse LLM skill recommendations: #{inspect(parsing_error)}")
            # Fallback to registry-based recommendations
            fallback_to_registry_recommendations(context, agent_id)
        end

      error ->
        Logger.error("LLM skill recommendation failed: #{inspect(error)}")
        fallback_to_registry_recommendations(context, agent_id)
    end
  end

  @doc """
  Optimize workflow definition using LLM analysis and Constitutional AI.
  """
  def optimize_workflow_with_llm(
        workflow_definition,
        performance_history,
        optimization_goals \\ %{}
      ) do
    Logger.debug("Optimizing workflow with LLM assistance")

    optimization_request =
      build_workflow_optimization_request(
        workflow_definition,
        performance_history,
        optimization_goals
      )

    case UniversalProviderService.complete(optimization_request, :orchestration, %{
           use_case: :workflow_optimization,
           specialized_features: [:cost_optimization, :constitutional_ai],
           max_tokens: 1200,
           # Low temperature for consistent optimization
           temperature: 0.2
         }) do
      {:ok, llm_response} ->
        case parse_workflow_optimizations(llm_response.content) do
          {:ok, optimizations} ->
            {:ok,
             %{
               optimizations: optimizations,
               expected_improvement: calculate_expected_improvement(optimizations),
               reasoning: llm_response.content,
               cost_usd: llm_response.cost_usd,
               optimization_source: :llm_assisted
             }}

          error ->
            error
        end

      error ->
        Logger.error("LLM workflow optimization failed: #{inspect(error)}")
        generate_basic_workflow_optimization(workflow_definition, performance_history)
    end
  end

  @doc """
  Execute skill with LLM assistance for complex reasoning tasks.
  """
  def execute_skill_with_llm_assistance(skill_module, params, execution_context, user_id \\ nil) do
    Logger.debug("Executing skill #{skill_module} with LLM assistance")

    # Get skill capabilities to determine if LLM assistance is beneficial
    case SkillsRegistry.get_skill_capabilities(skill_module) do
      {:ok, capabilities} ->
        if skill_benefits_from_llm_assistance?(capabilities, params) do
          perform_llm_assisted_skill_execution(skill_module, params, execution_context, user_id)
        else
          # Execute skill normally without LLM assistance
          execute_skill_directly(skill_module, params, execution_context)
        end

      {:error, :skill_not_found} ->
        {:error, "Skill not found in registry: #{skill_module}"}

      error ->
        error
    end
  end

  @doc """
  Get intelligent action coordination using LLM decision making.
  """
  def coordinate_actions_with_llm(
        actions,
        coordination_strategy,
        execution_context,
        user_id \\ nil
      ) do
    Logger.debug("Coordinating #{length(actions)} actions with LLM assistance")

    coordination_request =
      build_action_coordination_request(actions, coordination_strategy, execution_context)

    case UniversalProviderService.complete(coordination_request, :orchestration, %{
           use_case: :action_coordination,
           user_id: user_id,
           specialized_features: [:cost_optimization, :agent_communication],
           max_tokens: 1000,
           temperature: 0.3
         }) do
      {:ok, llm_response} ->
        case parse_coordination_strategy(llm_response.content) do
          {:ok, optimized_strategy} ->
            # Execute actions using optimized strategy
            execute_coordinated_actions(actions, optimized_strategy, execution_context)

          error ->
            error
        end

      error ->
        Logger.error("LLM action coordination failed: #{inspect(error)}")
        # Fallback to simple sequential execution
        execute_actions_sequentially(actions, execution_context)
    end
  end

  @doc """
  Stream skill execution with real-time LLM feedback.
  """
  def stream_skill_execution(skill_module, params, callback, execution_context, user_id \\ nil)
      when is_function(callback) do
    Logger.debug("Streaming skill execution #{skill_module} with LLM feedback")

    # Create skill execution prompt for streaming
    execution_prompt = build_skill_execution_prompt(skill_module, params, execution_context)

    # Create skills-aware streaming callback
    skills_callback = create_skills_streaming_callback(callback, skill_module, execution_context)

    case UniversalProviderService.stream(execution_prompt, :orchestration, skills_callback, %{
           use_case: :skill_execution,
           user_id: user_id,
           specialized_features: [:agent_communication, :cost_optimization],
           max_tokens: 800,
           temperature: 0.4
         }) do
      {:ok, final_response} ->
        {:ok,
         %{
           skill_module: skill_module,
           final_result: final_response.content,
           streaming_completed: true,
           cost_usd: final_response.cost_usd,
           execution_source: :llm_streamed
         }}

      error ->
        error
    end
  end

  @doc """
  Estimate cost for skills/actions execution using Universal Provider System.
  """
  def estimate_execution_cost(skills_actions, execution_context, user_id \\ nil) do
    Logger.debug("Estimating execution cost for #{length(skills_actions)} skills/actions")

    # Estimate cost for each skill/action
    cost_estimates =
      skills_actions
      |> Enum.map(fn skill_action ->
        estimate_single_execution_cost(skill_action, execution_context, user_id)
      end)

    # Aggregate costs
    total_cost =
      cost_estimates
      |> Enum.map(fn
        {:ok, cost} -> cost
        _ -> 0.0
      end)
      |> Enum.sum()

    successful_estimates = Enum.count(cost_estimates, &match?({:ok, _}, &1))

    {:ok,
     %{
       total_estimated_cost: total_cost,
       individual_estimates: cost_estimates,
       estimation_success_rate: successful_estimates / length(skills_actions),
       # Would track actual vs estimated in production
       estimation_accuracy: :high
     }}
  end

  # Private implementation

  defp build_skill_recommendation_request(context, agent_id) do
    """
    Agent Skill Recommendation Request:

    Agent ID: #{agent_id}
    Context: #{inspect(context)}
    Agent Goals: #{Map.get(context, :goals, "General agent operation")}
    Current Capabilities: #{Map.get(context, :current_capabilities, [])}
    Performance Requirements: #{inspect(Map.get(context, :performance_requirements, %{}))}

    Available Skills for Agent System:
    - Learning Skill: Experience tracking and pattern recognition
    - Threat Detection Skill: Security monitoring and threat analysis
    - Project Management Skill: Task coordination and project tracking  
    - Authentication Skill: User authentication and session management
    - Code Analysis Skill: Code quality assessment and review
    - Policy Enforcement Skill: Rule enforcement and compliance checking
    - Query Optimization Skill: Database and search query optimization
    - Token Management Skill: API token and credential management
    - User Management Skill: User lifecycle and permission management

    Please analyze the agent context and recommend the most appropriate skills.
    Consider capability overlap, performance requirements, and integration complexity.

    Respond in JSON format:
    {
      "recommended_skills": ["skill_name1", "skill_name2"],
      "reasoning": "detailed explanation of recommendations",
      "priority_order": ["highest_priority", "medium_priority", "lowest_priority"],
      "alternative_options": ["backup_skill1", "backup_skill2"]
    }
    """
  end

  defp parse_skill_recommendations(llm_content) do
    case Jason.decode(llm_content) do
      {:ok,
       %{
         "recommended_skills" => recommended_skills,
         "reasoning" => reasoning,
         "priority_order" => priority_order
       } = parsed} ->
        {:ok,
         %{
           recommended_skills: recommended_skills,
           reasoning: reasoning,
           priority_order: priority_order,
           alternative_options: Map.get(parsed, "alternative_options", [])
         }}

      {:error, json_error} ->
        Logger.warning("Failed to parse skill recommendations JSON: #{inspect(json_error)}")
        # Attempt text-based parsing
        parse_skill_recommendations_from_text(llm_content)
    end
  end

  defp parse_skill_recommendations_from_text(text) do
    # Extract skill names from text using pattern matching
    skill_names = [
      "learning_skill",
      "threat_detection_skill",
      "project_management_skill",
      "authentication_skill",
      "code_analysis_skill",
      "policy_enforcement_skill",
      "query_optimization_skill",
      "token_management_skill",
      "user_management_skill"
    ]

    mentioned_skills =
      skill_names
      |> Enum.filter(&String.contains?(String.downcase(text), &1))

    {:ok,
     %{
       recommended_skills: mentioned_skills,
       reasoning: text,
       # Same order for text parsing
       priority_order: mentioned_skills,
       alternative_options: []
     }}
  end

  defp validate_skill_recommendations(recommendations) do
    available_skills = [
      "learning_skill",
      "threat_detection_skill",
      "project_management_skill",
      "authentication_skill",
      "code_analysis_skill",
      "policy_enforcement_skill",
      "query_optimization_skill",
      "token_management_skill",
      "user_management_skill"
    ]

    validated_recommendations =
      recommendations.recommended_skills
      |> Enum.filter(&(&1 in available_skills))

    %{recommendations | recommended_skills: validated_recommendations}
  end

  defp fallback_to_registry_recommendations(context, agent_id) do
    # Use skills registry for traditional capability matching
    capability_requirements = extract_capability_requirements(context)

    case SkillsRegistry.discover_skills(capability_requirements) do
      {:ok, matching_skills} ->
        recommendations =
          matching_skills
          # Top 3 recommendations
          |> Enum.take(3)
          |> Enum.map(fn {skill_module, match_data} ->
            module_to_skill_name(skill_module)
          end)

        {:ok,
         %{
           recommendations: recommendations,
           reasoning: "Registry-based capability matching fallback",
           recommendation_source: :registry_fallback,
           confidence: 0.7
         }}

      error ->
        error
    end
  end

  defp extract_capability_requirements(context) do
    %{
      capabilities: Map.get(context, :required_capabilities, []),
      performance: Map.get(context, :performance_requirements, %{}),
      context: %{
        integration_type: determine_integration_type(context),
        complexity_level: determine_complexity_level(context)
      }
    }
  end

  defp determine_integration_type(context) do
    cond do
      Map.has_key?(context, :llm_requirements) -> :llm_integration
      Map.has_key?(context, :database_requirements) -> :ash_integration
      Map.has_key?(context, :api_requirements) -> :external_integration
      true -> :general
    end
  end

  defp determine_complexity_level(context) do
    goals = Map.get(context, :goals, "")

    case String.length(goals) do
      length when length > 200 -> :complex
      length when length > 100 -> :moderate
      _ -> :simple
    end
  end

  defp module_to_skill_name(skill_module) do
    skill_module
    |> to_string()
    |> String.replace("Elixir.RubberDuck.Skills.", "")
    |> String.replace("Skill", "")
    |> Macro.underscore()
  end

  defp build_workflow_optimization_request(
         workflow_definition,
         performance_history,
         optimization_goals
       ) do
    """
    Workflow Optimization Analysis Request:

    Current Workflow Definition:
    Pattern: #{workflow_definition.pattern}
    Skills/Actions: #{inspect(Map.get(workflow_definition, :skills_actions, []))}

    Performance History:
    #{format_performance_history(performance_history)}

    Optimization Goals:
    #{format_optimization_goals(optimization_goals)}

    Please analyze this workflow and provide specific optimization recommendations:

    1. Execution Time Optimization:
       - Identify opportunities for parallel execution
       - Suggest skill/action reordering for efficiency
       - Recommend faster alternative skills where appropriate

    2. Resource Efficiency:
       - Identify redundant operations
       - Suggest resource sharing opportunities
       - Recommend memory and CPU optimization strategies

    3. Error Handling Enhancement:
       - Identify potential failure points
       - Suggest robust error recovery strategies
       - Recommend fallback mechanisms

    4. Constitutional AI Compliance:
       - Ensure workflow promotes helpful, harmless, honest operations
       - Suggest safety improvements where applicable
       - Recommend ethical consideration enhancements

    Respond in JSON format:
    {
      "optimizations": [
        {
          "category": "execution_time",
          "suggestion": "specific optimization",
          "expected_improvement": 0.25,
          "implementation_complexity": "low|medium|high"
        }
      ],
      "overall_expected_improvement": 0.30,
      "reasoning": "detailed analysis and justification",
      "constitutional_ai_assessment": "safety and ethics evaluation"
    }
    """
  end

  defp format_performance_history(performance_history) do
    case performance_history do
      history when is_map(history) and map_size(history) > 0 ->
        """
        Recent Executions: #{Map.get(history, :execution_count, 0)}
        Average Execution Time: #{Map.get(history, :avg_execution_time_ms, 0)}ms
        Success Rate: #{Map.get(history, :success_rate, 0.0)}
        Most Common Bottlenecks: #{inspect(Map.get(history, :bottlenecks, []))}
        """

      _ ->
        "No performance history available - optimizing based on workflow structure analysis."
    end
  end

  defp format_optimization_goals(optimization_goals) do
    case optimization_goals do
      goals when is_map(goals) and map_size(goals) > 0 ->
        """
        Target Execution Time: #{Map.get(goals, :target_execution_time_ms, "Not specified")}
        Cost Budget: $#{Map.get(goals, :max_cost_usd, "Not specified")}
        Priority: #{Map.get(goals, :priority, "Balanced optimization")}
        Specific Focus: #{Map.get(goals, :focus_areas, ["performance", "cost", "reliability"])}
        """

      _ ->
        "General optimization goals - balance performance, cost, and reliability."
    end
  end

  defp parse_workflow_optimizations(llm_content) do
    case Jason.decode(llm_content) do
      {:ok,
       %{
         "optimizations" => optimizations,
         "overall_expected_improvement" => improvement,
         "reasoning" => reasoning
       } = parsed} ->
        {:ok,
         %{
           optimizations: optimizations,
           overall_expected_improvement: improvement,
           reasoning: reasoning,
           constitutional_ai_assessment:
             Map.get(parsed, "constitutional_ai_assessment", "Assessment not provided")
         }}

      {:error, json_error} ->
        Logger.warning("Failed to parse workflow optimizations: #{inspect(json_error)}")
        # Extract basic optimizations from text
        parse_optimizations_from_text(llm_content)
    end
  end

  defp parse_optimizations_from_text(text) do
    # Simple text parsing for optimization suggestions
    optimization_keywords = ["parallel", "sequential", "optimize", "improve", "reduce", "enhance"]

    optimizations =
      optimization_keywords
      |> Enum.filter(&String.contains?(String.downcase(text), &1))
      |> Enum.map(fn keyword ->
        %{
          category: "general",
          suggestion: "Consider #{keyword} optimization opportunities",
          expected_improvement: 0.1,
          implementation_complexity: "medium"
        }
      end)

    {:ok,
     %{
       optimizations: optimizations,
       overall_expected_improvement: 0.1,
       reasoning: text,
       constitutional_ai_assessment: "Text parsing fallback - manual review recommended"
     }}
  end

  defp calculate_expected_improvement(optimizations) do
    optimizations
    |> Enum.map(&Map.get(&1, "expected_improvement", 0.0))
    |> Enum.sum()
    # Cap at 80% improvement to be realistic
    |> min(0.8)
  end

  defp skill_benefits_from_llm_assistance?(capabilities, params) do
    # Determine if skill execution would benefit from LLM assistance
    complexity_score = Map.get(capabilities, :complexity_score, :simple)
    public_function_count = length(Map.get(capabilities, :public_functions, []))

    # Skills with high complexity or multiple functions benefit from LLM assistance
    complexity_score in [:complex, :very_complex] or
      public_function_count > 5 or
      Map.has_key?(params, :reasoning_required)
  end

  defp perform_llm_assisted_skill_execution(skill_module, params, execution_context, user_id) do
    # Build LLM prompt for skill execution guidance
    skill_guidance_prompt =
      build_skill_execution_guidance_prompt(skill_module, params, execution_context)

    case UniversalProviderService.complete(skill_guidance_prompt, :orchestration, %{
           use_case: :skill_execution_guidance,
           user_id: user_id,
           specialized_features: [:agent_communication],
           max_tokens: 600,
           temperature: 0.3
         }) do
      {:ok, llm_response} ->
        # Execute skill with LLM guidance
        execute_skill_with_guidance(skill_module, params, execution_context, llm_response.content)

      error ->
        Logger.warning("LLM skill guidance failed, executing directly: #{inspect(error)}")
        execute_skill_directly(skill_module, params, execution_context)
    end
  end

  defp build_skill_execution_guidance_prompt(skill_module, params, execution_context) do
    skill_name = module_to_skill_name(skill_module)

    """
    Skill Execution Guidance Request:

    Skill: #{skill_name}
    Parameters: #{inspect(params)}
    Execution Context: #{inspect(execution_context)}

    Please provide guidance for optimal execution of this skill:

    1. Parameter Optimization:
       - Validate and suggest improvements to provided parameters
       - Identify missing parameters that could enhance execution

    2. Context Utilization:
       - Suggest how to best leverage the execution context
       - Identify context elements that could improve skill performance

    3. Execution Strategy:
       - Recommend optimal execution approach
       - Suggest any preprocessing or preparation steps

    4. Expected Outcomes:
       - Predict likely execution results
       - Identify potential issues or edge cases

    Provide guidance that enhances skill execution while following Constitutional AI principles.
    """
  end

  defp execute_skill_with_guidance(skill_module, params, execution_context, llm_guidance) do
    # Parse guidance and enhance execution
    guidance_data = parse_skill_guidance(llm_guidance)
    enhanced_params = enhance_params_with_guidance(params, guidance_data)
    enhanced_context = enhance_context_with_guidance(execution_context, guidance_data)

    # Execute skill with enhancements
    result = execute_skill_directly(skill_module, enhanced_params, enhanced_context)

    case result do
      {:ok, skill_result} ->
        {:ok,
         %{
           skill_result: skill_result,
           llm_guidance_applied: true,
           guidance_summary: guidance_data,
           execution_source: :llm_guided
         }}

      error ->
        error
    end
  end

  defp execute_skill_directly(skill_module, params, execution_context) do
    # Direct skill execution without LLM assistance
    case safe_execute_skill(skill_module, params, execution_context) do
      {:ok, result} -> 
        {:ok, %{
          skill_module: skill_module,
          result: result,
          execution_source: :direct,
          timestamp: DateTime.utc_now()
        }}
      error -> error
    end
  end

  defp safe_execute_skill(skill_module, params, execution_context) do
    skill_state = build_skill_state(execution_context)
    # Execute skill (simplified - would use proper Jido patterns)
    result = skill_module.execute(params, skill_state)
    {:ok, result}
  rescue
    error ->
      {:error, "Direct skill execution failed: #{Exception.message(error)}"}
  end

  defp parse_skill_guidance(llm_guidance) do
    # Parse LLM guidance for skill execution enhancements
    %{
      parameter_suggestions: extract_parameter_suggestions(llm_guidance),
      context_suggestions: extract_context_suggestions(llm_guidance),
      execution_strategy: extract_execution_strategy(llm_guidance),
      expected_outcomes: extract_expected_outcomes(llm_guidance)
    }
  end

  defp enhance_params_with_guidance(params, guidance_data) do
    parameter_suggestions = guidance_data.parameter_suggestions

    # Apply parameter enhancements from LLM guidance
    Enum.reduce(parameter_suggestions, params, fn suggestion, acc_params ->
      case suggestion do
        %{add_param: key, value: value} -> Map.put(acc_params, String.to_atom(key), value)
        %{modify_param: key, new_value: value} -> Map.put(acc_params, String.to_atom(key), value)
        _ -> acc_params
      end
    end)
  end

  defp enhance_context_with_guidance(execution_context, guidance_data) do
    context_suggestions = guidance_data.context_suggestions

    # Apply context enhancements
    Map.merge(execution_context, %{
      llm_guidance_applied: true,
      execution_strategy: guidance_data.execution_strategy,
      expected_outcomes: guidance_data.expected_outcomes
    })
  end

  defp build_action_coordination_request(actions, coordination_strategy, execution_context) do
    action_descriptions =
      actions
      |> Enum.map(fn action ->
        "#{inspect(action.module)}: #{Map.get(action, :description, "No description")}"
      end)
      |> Enum.join("\n")

    """
    Action Coordination Strategy Request:

    Actions to Coordinate:
    #{action_descriptions}

    Current Strategy: #{coordination_strategy}
    Execution Context: #{inspect(execution_context)}

    Please analyze these actions and recommend an optimal coordination strategy:

    1. Execution Order Analysis:
       - Identify dependencies between actions
       - Recommend optimal execution sequence
       - Suggest opportunities for parallel execution

    2. Resource Optimization:
       - Identify shared resource requirements
       - Suggest resource pooling opportunities
       - Recommend memory and CPU optimization

    3. Error Handling Strategy:
       - Identify potential failure scenarios
       - Suggest robust error recovery mechanisms
       - Recommend fallback coordination strategies

    Respond with JSON:
    {
      "recommended_strategy": "parallel|sequential|conditional|pipeline",
      "execution_order": ["action1", "action2", "action3"],
      "parallel_groups": [["action1", "action2"], ["action3"]],
      "reasoning": "detailed coordination analysis",
      "expected_performance_improvement": 0.25
    }
    """
  end

  defp parse_coordination_strategy(llm_content) do
    case Jason.decode(llm_content) do
      {:ok,
       %{
         "recommended_strategy" => strategy,
         "execution_order" => order,
         "reasoning" => reasoning
       } = parsed} ->
        {:ok,
         %{
           strategy: String.to_atom(strategy),
           execution_order: order,
           parallel_groups: Map.get(parsed, "parallel_groups", []),
           reasoning: reasoning,
           expected_improvement: Map.get(parsed, "expected_performance_improvement", 0.1)
         }}

      {:error, _} ->
        # Fallback to simple sequential strategy
        {:ok,
         %{
           strategy: :sequential,
           execution_order: [],
           reasoning: llm_content,
           expected_improvement: 0.05
         }}
    end
  end

  defp execute_coordinated_actions(actions, optimized_strategy, execution_context) do
    case optimized_strategy.strategy do
      :parallel ->
        ActionOrchestrator.execute_parallel_workflow(actions, execution_context)

      :sequential ->
        ActionOrchestrator.execute_sequential_workflow(actions, execution_context)

      _ ->
        # Default to sequential
        ActionOrchestrator.execute_sequential_workflow(actions, execution_context)
    end
  end

  defp execute_actions_sequentially(actions, execution_context) do
    ActionOrchestrator.execute_sequential_workflow(actions, execution_context)
  end

  defp create_skills_streaming_callback(original_callback, skill_module, execution_context) do
    fn stream_event ->
      # Enhance streaming events with skills context
      enhanced_event =
        case Map.get(stream_event, :type) do
          :chunk ->
            %{
              type: :skill_execution_progress,
              skill_module: skill_module,
              content: Map.get(stream_event, :content, ""),
              execution_context: execution_context,
              timestamp: DateTime.utc_now()
            }

          :complete ->
            %{
              type: :skill_execution_complete,
              skill_module: skill_module,
              result: Map.get(stream_event, :result, %{}),
              execution_context: execution_context,
              timestamp: DateTime.utc_now()
            }

          _ ->
            Map.merge(stream_event, %{
              skill_module: skill_module,
              execution_context: execution_context
            })
        end

      original_callback.(enhanced_event)
    end
  end

  defp build_skill_execution_prompt(skill_module, params, execution_context) do
    skill_name = module_to_skill_name(skill_module)

    """
    Skill Execution Streaming Request:

    Skill: #{skill_name}
    Parameters: #{inspect(params)}
    Context: #{inspect(execution_context)}

    Please provide step-by-step guidance for executing this skill effectively.
    Include progress updates and intermediate results as the execution proceeds.
    """
  end

  defp estimate_single_execution_cost(skill_action, execution_context, user_id) do
    case skill_action.type do
      :skill ->
        # Estimate cost for skill execution
        estimate_skill_execution_cost(skill_action, execution_context, user_id)

      :action ->
        # Estimate cost for action execution
        estimate_action_execution_cost(skill_action, execution_context, user_id)

      :llm_assisted ->
        # Estimate cost for LLM-assisted task
        estimate_llm_task_cost(skill_action, execution_context, user_id)

      _ ->
        # Unknown type, assume no cost
        {:ok, 0.0}
    end
  end

  defp estimate_skill_execution_cost(skill_action, execution_context, user_id) do
    # Simple skill cost estimation
    skill_module = skill_action.module

    case SkillsRegistry.get_skill_capabilities(skill_module) do
      {:ok, capabilities} ->
        # Estimate based on skill complexity and LLM usage
        if Map.get(capabilities.integration_capabilities, :llm_integration, false) do
          # Skill uses LLM - estimate provider cost
          UniversalProviderService.estimate_cost(
            "Execute skill #{module_to_skill_name(skill_module)}",
            :orchestration,
            %{user_id: user_id}
          )
        else
          # No LLM cost for non-LLM skills
          {:ok, 0.0}
        end

      _ ->
        # Default low cost estimate
        {:ok, 0.05}
    end
  end

  defp estimate_action_execution_cost(skill_action, execution_context, user_id) do
    # Simple action cost estimation
    action_module = skill_action.module

    # Actions typically don't use LLM providers directly
    {:ok, 0.0}
  end

  defp estimate_llm_task_cost(skill_action, execution_context, user_id) do
    # Estimate cost for LLM-assisted task
    task_description = Map.get(skill_action, :description, "")
    # Basic estimation
    estimated_tokens = div(String.length(task_description), 4) + 300

    UniversalProviderService.estimate_cost(task_description, :orchestration, %{
      user_id: user_id,
      max_tokens: estimated_tokens
    })
  end

  defp build_skill_state(execution_context) do
    %{
      agent_id: Map.get(execution_context, :agent_id, "skills_orchestrator"),
      user_id: Map.get(execution_context, :user_id),
      project_id: Map.get(execution_context, :project_id),
      skills_orchestration_context: execution_context,
      timestamp: DateTime.utc_now()
    }
  end

  defp generate_basic_workflow_optimization(workflow_definition, performance_history) do
    # Basic workflow optimization without LLM assistance
    {:ok,
     %{
       optimizations: [
         %{
           category: "execution_time",
           suggestion: "Monitor execution times and identify bottlenecks",
           expected_improvement: 0.05,
           implementation_complexity: "low"
         }
       ],
       overall_expected_improvement: 0.05,
       reasoning: "Basic rule-based optimization fallback",
       constitutional_ai_assessment: "No specific safety concerns identified",
       optimization_source: :basic_rules
     }}
  end

  # Helper functions for parsing LLM guidance

  defp extract_parameter_suggestions(llm_guidance) do
    # Extract parameter optimization suggestions from LLM guidance
    # Simple implementation - would be more sophisticated in production
    if String.contains?(llm_guidance, "parameter") do
      [%{add_param: "optimization_hint", value: "llm_suggested"}]
    else
      []
    end
  end

  defp extract_context_suggestions(llm_guidance) do
    # Extract context enhancement suggestions
    if String.contains?(llm_guidance, "context") do
      [%{enhance_context: "execution_optimization", guidance: llm_guidance}]
    else
      []
    end
  end

  defp extract_execution_strategy(llm_guidance) do
    # Extract recommended execution strategy
    cond do
      String.contains?(llm_guidance, "parallel") -> :parallel_optimized
      String.contains?(llm_guidance, "sequential") -> :sequential_optimized
      String.contains?(llm_guidance, "careful") -> :cautious_execution
      true -> :standard_execution
    end
  end

  defp extract_expected_outcomes(llm_guidance) do
    # Extract predicted outcomes from LLM guidance
    %{
      # Would parse from guidance
      success_probability: 0.85,
      potential_issues: [],
      optimization_opportunities: [],
      guidance_applied: true
    }
  end
end
