defmodule RubberDuck.Prompts.Services.WorkflowPromptSelector do
  @moduledoc """
  Workflow context-aware prompt selection service.

  Extends the LlmPromptSelector service for Reactor workflow contexts, providing
  workflow step-specific prompt selection, context variable integration, and
  workflow-optimized prompt recommendations for improved productivity.

  Features:
  - Workflow context-aware prompt selection with step parameter integration
  - Extension of Section 6.1 LlmPromptSelector for workflow environments
  - Workflow context variable identification and substitution support
  - Performance optimization for workflow execution with minimal overhead
  """

  require Logger

  alias RubberDuck.Prompts.Integrations.PromptVariableSubstitution
  alias RubberDuck.Prompts.Services.LlmPromptSelector

  @doc """
  Get prompts suitable for workflow step execution with context filtering.
  """
  def get_workflow_suitable_prompts(user_id, workflow_context, options \\ %{}) do
    project_id = Map.get(workflow_context, :project_id)
    workflow_type = Map.get(workflow_context, :workflow_type, :general)

    Logger.debug("WorkflowPromptSelector: Getting workflow-suitable prompts",
      user_id: user_id,
      workflow_type: workflow_type,
      project_id: project_id
    )

    case LlmPromptSelector.get_available_prompts(user_id, project_id, options) do
      {:ok, available_prompts} ->
        # Filter and rank prompts based on workflow context
        workflow_optimized_prompts =
          optimize_prompts_for_workflow(available_prompts, workflow_context)

        Logger.debug("WorkflowPromptSelector: Workflow-suitable prompts retrieved",
          total_prompts: available_prompts.total_count,
          workflow_optimized: workflow_optimized_prompts.total_count
        )

        {:ok, workflow_optimized_prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search prompts with workflow context relevance ranking.
  """
  def search_workflow_prompts(user_id, search_query, workflow_context, search_options \\ %{}) do
    project_id = Map.get(workflow_context, :project_id)

    # Enhance search options with workflow context
    enhanced_search_options =
      Map.merge(search_options, %{
        workflow_context: workflow_context,
        rank_by_workflow_relevance: true
      })

    Logger.debug("WorkflowPromptSelector: Searching workflow prompts",
      user_id: user_id,
      search_query: search_query,
      workflow_type: Map.get(workflow_context, :workflow_type)
    )

    case LlmPromptSelector.search_prompts(
           user_id,
           search_query,
           project_id,
           enhanced_search_options
         ) do
      {:ok, search_results} ->
        # Re-rank results based on workflow relevance
        workflow_ranked_results = rank_by_workflow_relevance(search_results, workflow_context)
        {:ok, workflow_ranked_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get prompts recommended for specific workflow step types.
  """
  def get_recommended_prompts_for_step(user_id, step_type, workflow_context, options \\ %{}) do
    project_id = Map.get(workflow_context, :project_id)

    Logger.debug("WorkflowPromptSelector: Getting recommended prompts for step",
      user_id: user_id,
      step_type: step_type,
      workflow_type: Map.get(workflow_context, :workflow_type)
    )

    case LlmPromptSelector.get_available_prompts(user_id, project_id, options) do
      {:ok, available_prompts} ->
        # Filter prompts relevant to step type
        step_relevant_prompts =
          filter_prompts_for_step_type(available_prompts, step_type, workflow_context)

        {:ok, step_relevant_prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Prepare prompt for workflow execution with context variable substitution.
  """
  def prepare_prompt_for_workflow(prompt_content, workflow_context, variable_values \\ %{}) do
    Logger.debug("WorkflowPromptSelector: Preparing prompt for workflow execution",
      content_length: String.length(prompt_content),
      workflow_variables: Map.keys(workflow_context),
      user_variables: Map.keys(variable_values)
    )

    # Extract workflow context variables that can be used for substitution
    workflow_variables = extract_workflow_context_variables(workflow_context)

    # Merge user-provided values with workflow context variables
    all_variables = Map.merge(workflow_variables, variable_values)

    case PromptVariableSubstitution.substitute_variables(prompt_content, all_variables) do
      {:ok, substituted_content} ->
        preparation_result = %{
          prepared_content: substituted_content,
          original_content: prompt_content,
          workflow_context_applied: true,
          variables_substituted: map_size(all_variables),
          workflow_metadata: %{
            workflow_type: Map.get(workflow_context, :workflow_type),
            step_name: Map.get(workflow_context, :step_name),
            prepared_at: DateTime.utc_now()
          }
        }

        {:ok, preparation_result}

      {:error, reason} ->
        {:error, {:workflow_preparation_failed, reason}}
    end
  end

  @doc """
  Get workflow context variables available for prompt substitution.
  """
  def get_available_workflow_variables(workflow_context) do
    # Extract variables available from workflow context
    available_variables = extract_workflow_context_variables(workflow_context)

    # Add metadata about variable sources
    variables_with_metadata =
      Map.new(available_variables, fn {var_name, var_value} ->
        {var_name,
         %{
           value: var_value,
           source: :workflow_context,
           type: determine_variable_type(var_value),
           description: generate_variable_description(var_name, workflow_context)
         }}
      end)

    {:ok, variables_with_metadata}
  end

  # Private implementation functions

  defp optimize_prompts_for_workflow(available_prompts, workflow_context) do
    # Optimize prompt collections for workflow context
    workflow_type = Map.get(workflow_context, :workflow_type, :general)

    optimized_system =
      filter_prompts_by_workflow_relevance(available_prompts.system_prompts, workflow_type)

    optimized_project =
      filter_prompts_by_workflow_relevance(available_prompts.project_prompts, workflow_type)

    optimized_user =
      filter_prompts_by_workflow_relevance(available_prompts.user_prompts, workflow_type)

    %{
      system_prompts: optimized_system,
      project_prompts: optimized_project,
      user_prompts: optimized_user,
      total_count: length(optimized_system) + length(optimized_project) + length(optimized_user),
      workflow_optimized: true,
      workflow_type: workflow_type
    }
  end

  defp filter_prompts_by_workflow_relevance(prompts, workflow_type) do
    # Filter prompts based on workflow type relevance
    workflow_keywords = get_workflow_type_keywords(workflow_type)

    prompts
    |> Enum.filter(fn prompt ->
      content_relevance = calculate_workflow_content_relevance(prompt, workflow_keywords)
      name_relevance = calculate_workflow_name_relevance(prompt, workflow_keywords)

      # Include prompt if it has some relevance to workflow type
      content_relevance > 0.1 or name_relevance > 0.2
    end)
    |> Enum.map(fn prompt ->
      # Add workflow relevance score to prompt metadata
      relevance_score = calculate_total_workflow_relevance(prompt, workflow_keywords)
      Map.put(prompt, :workflow_relevance_score, relevance_score)
    end)
    |> Enum.sort_by(fn prompt -> prompt.workflow_relevance_score end, :desc)
  end

  defp rank_by_workflow_relevance(search_results, workflow_context) do
    # Re-rank search results based on workflow relevance
    workflow_type = Map.get(workflow_context, :workflow_type, :general)
    workflow_keywords = get_workflow_type_keywords(workflow_type)

    search_results
    |> Enum.map(fn prompt ->
      workflow_relevance = calculate_total_workflow_relevance(prompt, workflow_keywords)
      original_relevance = Map.get(prompt, :relevance_score, 0.5)

      # Combine original search relevance with workflow relevance
      combined_score = original_relevance * 0.7 + workflow_relevance * 0.3

      Map.put(prompt, :combined_relevance_score, combined_score)
    end)
    |> Enum.sort_by(fn prompt -> prompt.combined_relevance_score end, :desc)
  end

  defp filter_prompts_for_step_type(available_prompts, step_type, workflow_context) do
    # Filter prompts relevant to specific step type
    step_keywords = get_step_type_keywords(step_type)

    all_prompts =
      (available_prompts.system_prompts || []) ++
        (available_prompts.project_prompts || []) ++
        (available_prompts.user_prompts || [])

    relevant_prompts =
      all_prompts
      |> Enum.filter(fn prompt ->
        step_relevance = calculate_step_type_relevance(prompt, step_keywords)
        step_relevance > 0.2
      end)
      |> Enum.map(fn prompt ->
        relevance_score = calculate_step_type_relevance(prompt, step_keywords)
        Map.put(prompt, :step_relevance_score, relevance_score)
      end)
      |> Enum.sort_by(fn prompt -> prompt.step_relevance_score end, :desc)

    %{
      recommended_prompts: relevant_prompts,
      step_type: step_type,
      recommendation_count: length(relevant_prompts),
      workflow_context: workflow_context
    }
  end

  defp extract_workflow_context_variables(workflow_context) do
    # Extract variables from workflow context that can be used in prompt substitution
    base_variables = %{
      "workflow_type" => to_string(Map.get(workflow_context, :workflow_type, :general)),
      "step_name" => Map.get(workflow_context, :step_name, "unknown_step"),
      "project_id" => Map.get(workflow_context, :project_id, ""),
      "execution_time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add workflow-specific variables
    workflow_specific =
      case Map.get(workflow_context, :workflow_type) do
        :code_review ->
          %{
            "review_type" => Map.get(workflow_context, :review_type, "general"),
            "code_language" => Map.get(workflow_context, :code_language, "unknown")
          }

        :documentation ->
          %{
            "doc_type" => Map.get(workflow_context, :documentation_type, "general"),
            "target_audience" => Map.get(workflow_context, :target_audience, "developers")
          }

        :testing ->
          %{
            "test_type" => Map.get(workflow_context, :test_type, "unit"),
            "test_framework" => Map.get(workflow_context, :test_framework, "exunit")
          }

        _ ->
          %{}
      end

    # Add custom context variables if provided
    custom_variables = Map.get(workflow_context, :custom_variables, %{})

    Map.merge(base_variables, workflow_specific) |> Map.merge(custom_variables)
  end

  # Helper functions

  defp get_workflow_type_keywords(workflow_type) do
    case workflow_type do
      :code_review -> ["review", "code", "quality", "analysis", "critique", "feedback"]
      :documentation -> ["document", "explain", "describe", "guide", "tutorial", "reference"]
      :testing -> ["test", "spec", "verify", "validate", "check", "assert"]
      :refactoring -> ["refactor", "improve", "optimize", "restructure", "clean"]
      :debugging -> ["debug", "troubleshoot", "diagnose", "fix", "error", "issue"]
      _ -> ["general", "help", "assistance", "guidance"]
    end
  end

  defp get_step_type_keywords(step_type) do
    case step_type do
      :analysis -> ["analyze", "examine", "investigate", "study", "evaluate"]
      :generation -> ["generate", "create", "produce", "build", "make"]
      :validation -> ["validate", "verify", "check", "confirm", "ensure"]
      :transformation -> ["transform", "convert", "modify", "change", "adapt"]
      _ -> ["process", "handle", "manage", "execute"]
    end
  end

  defp calculate_workflow_content_relevance(prompt, workflow_keywords) do
    # Calculate relevance of prompt content to workflow type
    content_lower = String.downcase(prompt.content)

    matching_keywords =
      Enum.count(workflow_keywords, fn keyword ->
        String.contains?(content_lower, keyword)
      end)

    matching_keywords / length(workflow_keywords)
  end

  defp calculate_workflow_name_relevance(prompt, workflow_keywords) do
    # Calculate relevance of prompt name to workflow type
    name_lower = String.downcase(prompt.name)

    matching_keywords =
      Enum.count(workflow_keywords, fn keyword ->
        String.contains?(name_lower, keyword)
      end)

    matching_keywords / length(workflow_keywords)
  end

  defp calculate_total_workflow_relevance(prompt, workflow_keywords) do
    # Calculate total workflow relevance score
    content_relevance = calculate_workflow_content_relevance(prompt, workflow_keywords)
    name_relevance = calculate_workflow_name_relevance(prompt, workflow_keywords)

    # Weight name relevance higher than content relevance
    name_relevance * 0.6 + content_relevance * 0.4
  end

  defp calculate_step_type_relevance(prompt, step_keywords) do
    # Calculate relevance to specific step type
    content_lower = String.downcase(prompt.content)
    name_lower = String.downcase(prompt.name)

    content_matches =
      Enum.count(step_keywords, fn keyword ->
        String.contains?(content_lower, keyword)
      end)

    name_matches =
      Enum.count(step_keywords, fn keyword ->
        String.contains?(name_lower, keyword)
      end)

    # Weight name matches higher
    total_matches = content_matches + name_matches * 2
    total_matches / (length(step_keywords) * 2)
  end

  defp determine_variable_type(value) do
    # Determine variable type for workflow context
    cond do
      is_binary(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_map(value) -> :map
      is_list(value) -> :list
      true -> :unknown
    end
  end

  defp generate_variable_description(var_name, _workflow_context) do
    # Generate helpful description for workflow variables
    get_standard_variable_description(var_name)
  end

  defp get_standard_variable_description(var_name) do
    case var_name do
      "workflow_type" -> "Type of workflow being executed"
      "step_name" -> "Name of the current workflow step"
      "project_id" -> "Current project identifier"
      "execution_time" -> "Workflow execution timestamp"
      _ -> get_workflow_specific_description(var_name)
    end
  end

  defp get_workflow_specific_description(var_name) do
    case var_name do
      "review_type" -> "Type of code review being performed"
      "code_language" -> "Programming language being reviewed"
      "doc_type" -> "Type of documentation being generated"
      "target_audience" -> "Intended audience for the documentation"
      "test_type" -> "Type of test being executed"
      "test_framework" -> "Testing framework being used"
      _ -> "Custom workflow variable: #{var_name}"
    end
  end
end
