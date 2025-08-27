defmodule RubberDuck.Verdict.Providers.OpenAI.OpenAIEvaluator do
  @moduledoc """
  OpenAI-specific evaluation logic and prompt optimization.

  This module handles:
  - OpenAI-optimized evaluation prompts for different code analysis types
  - Response parsing and validation
  - Model-specific optimization strategies
  - Integration with OpenAI's latest features like structured outputs
  """

  require Logger

  alias RubberDuck.Verdict.Providers.OpenAI.OpenAIClient

  def initialize(config) do
    evaluator_state = %{
      config: config,
      prompt_templates: load_openai_prompt_templates(),
      model_preferences: %{
        # Security needs detailed analysis
        security: "gpt-4o",
        # Performance analysis benefits from reasoning
        performance: "gpt-4o",
        # General quality can use efficient model
        quality: "gpt-4o-mini",
        maintainability: "gpt-4o-mini",
        style: "gpt-4o-mini"
      }
    }

    {:ok, evaluator_state}
  end

  def evaluate(evaluator_state, request) do
    Logger.debug("OpenAI evaluation started for model: #{request.model}")
    start_time = System.monotonic_time(:millisecond)

    # Optimize request for OpenAI
    optimized_request = optimize_openai_request(request, evaluator_state)

    case OpenAIClient.complete(evaluator_state.config.client, optimized_request) do
      {:ok, response} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        evaluation_result = %{
          success: true,
          raw_response: response,
          response_time_ms: response_time,
          model: request.model
        }

        {:ok, evaluation_result}

      {:error, reason} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        Logger.error("OpenAI evaluation failed: #{inspect(reason)}")

        {:error,
         %{
           reason: reason,
           response_time_ms: response_time,
           model: request.model
         }}
    end
  end

  def evaluate_streaming(evaluator_state, request, model, callback) do
    Logger.debug("OpenAI streaming evaluation started for model: #{model}")
    start_time = System.monotonic_time(:millisecond)

    # Build streaming request
    streaming_request =
      Map.merge(request, %{
        model: model,
        stream: true
      })

    optimized_request = optimize_openai_request(streaming_request, evaluator_state)

    case OpenAIClient.complete_streaming(
           evaluator_state.config.client,
           optimized_request,
           callback
         ) do
      {:ok, final_response} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           success: true,
           raw_response: final_response,
           response_time_ms: response_time,
           model: model,
           streaming: true
         }}

      error ->
        error
    end
  end

  # Private implementation

  defp optimize_openai_request(request, evaluator_state) do
    # Apply OpenAI-specific optimizations
    request
    |> ensure_structured_output()
    |> optimize_temperature_for_evaluation()
    |> add_openai_specific_params()
    |> apply_token_optimization()
  end

  defp ensure_structured_output(request) do
    # Use OpenAI's structured output format for consistent JSON
    Map.put(request, :response_format, %{type: "json_object"})
  end

  defp optimize_temperature_for_evaluation(request) do
    # Use low temperature for consistent code evaluation
    Map.put(request, :temperature, 0.1)
  end

  defp add_openai_specific_params(request) do
    request
    # Use full probability distribution
    |> Map.put(:top_p, 1.0)
    # Slightly discourage repetition
    |> Map.put(:frequency_penalty, 0.1)
    # No creativity penalty for code analysis
    |> Map.put(:presence_penalty, 0.0)
  end

  defp apply_token_optimization(request) do
    # Ensure we leave enough tokens for response
    max_tokens = Map.get(request, :max_tokens, 1500)

    # Estimate tokens in prompt
    prompt_token_estimate = estimate_prompt_tokens(request)

    # Adjust max_tokens to leave room for response
    available_tokens = max_tokens - prompt_token_estimate
    response_tokens = min(1000, max(200, available_tokens))

    Map.put(request, :max_tokens, response_tokens)
  end

  defp estimate_prompt_tokens(request) do
    # Rough estimation of tokens in the prompt
    messages = Map.get(request, :messages, [])

    total_chars =
      messages
      |> Enum.map(fn msg -> String.length(Map.get(msg, :content, "")) end)
      |> Enum.sum()

    # Approximate: 4 characters per token
    div(total_chars, 4)
  end

  defp load_openai_prompt_templates do
    %{
      security: %{
        system_prompt: """
        You are a cybersecurity expert with deep knowledge of secure coding practices.
        Analyze code for security vulnerabilities including but not limited to:
        - SQL injection and NoSQL injection vulnerabilities
        - Cross-site scripting (XSS) issues
        - Authentication and authorization flaws
        - Data exposure and privacy concerns
        - Input validation weaknesses
        - Cryptographic implementation issues

        Focus on actionable recommendations with specific code examples.
        """,
        evaluation_template: """
        Perform a comprehensive security analysis of the provided code.

        Look for:
        1. Input validation and sanitization
        2. Authentication and authorization mechanisms
        3. Data handling and encryption
        4. Error handling that might leak information
        5. Dependencies with known vulnerabilities

        For each issue found, provide:
        - Severity level (critical, high, medium, low)
        - Detailed description of the vulnerability
        - Specific remediation steps
        - Code examples showing the fix
        """
      },
      performance: %{
        system_prompt: """
        You are a performance optimization expert with deep understanding of algorithms,
        data structures, and system performance characteristics.

        Analyze code for performance issues including:
        - Algorithmic complexity problems (O(n²) where O(n) possible)
        - Memory usage inefficiencies
        - Database query optimization opportunities
        - Caching and memoization opportunities
        - Resource cleanup and management
        """,
        evaluation_template: """
        Perform detailed performance analysis of the provided code.

        Evaluate:
        1. Algorithmic efficiency and complexity
        2. Memory allocation patterns
        3. I/O operations and blocking behavior
        4. Resource management and cleanup
        5. Scalability characteristics

        Provide specific optimization recommendations with:
        - Performance impact estimation
        - Implementation complexity
        - Trade-offs and considerations
        """
      },
      quality: %{
        system_prompt: """
        You are an experienced software engineer focused on code quality,
        correctness, and maintainability.

        Analyze code for:
        - Logic errors and edge case handling
        - Code organization and structure
        - Readability and clarity
        - Error handling robustness
        - Testing considerations
        """,
        evaluation_template: """
        Perform comprehensive code quality evaluation.

        Assess:
        1. Correctness and logic flow
        2. Error handling completeness
        3. Code organization and modularity
        4. Documentation and comments
        5. Testability and maintainability

        Provide actionable improvements that enhance overall code quality.
        """
      },
      maintainability: %{
        system_prompt: """
        You are a software architecture expert specializing in long-term code maintainability
        and system evolution.
        """,
        evaluation_template: """
        Evaluate code maintainability focusing on:
        1. Code organization and structure
        2. Dependency management
        3. Modularity and coupling
        4. Documentation quality
        5. Future extension points
        """
      },
      style: %{
        system_prompt: """
        You are a code style expert with deep knowledge of language-specific
        conventions and best practices.
        """,
        evaluation_template: """
        Review code style and formatting:
        1. Naming conventions
        2. Code formatting and consistency
        3. Language-specific idioms
        4. Comment style and placement
        5. Overall code organization
        """
      }
    }
  end

  def get_optimized_prompt(evaluation_type, code, criteria) do
    template = get_template_for_type(evaluation_type)

    criteria_section =
      if map_size(criteria) > 0 do
        criteria_text =
          criteria
          |> Enum.map(fn {criterion, weight} ->
            "- #{criterion}: #{Float.round(weight * 100, 1)}%"
          end)
          |> Enum.join("\n")

        "\nEvaluation Criteria Weights:\n#{criteria_text}\n"
      else
        ""
      end

    template.system_prompt <>
      criteria_section <>
      "\n\n" <>
      template.evaluation_template <>
      "\n\nCode to evaluate:\n```\n#{code}\n```"
  end

  defp get_template_for_type(evaluation_type) do
    templates = load_openai_prompt_templates()
    Map.get(templates, evaluation_type, templates.quality)
  end

  # Response parsing and validation

  def parse_openai_evaluation_response(response) do
    case get_in(response, [:choices, Access.at(0), :message, :content]) do
      nil ->
        {:error, "No content in OpenAI response"}

      content ->
        case Jason.decode(content) do
          {:ok, %{} = evaluation_data} ->
            {:ok,
             %{
               overall_score: parse_score(evaluation_data["overall_score"]),
               confidence: parse_confidence(evaluation_data["confidence"]),
               issues: parse_issues(evaluation_data["issues"]),
               recommendations: parse_recommendations(evaluation_data["recommendations"]),
               reasoning: Map.get(evaluation_data, "reasoning", ""),
               metadata: %{
                 model: Map.get(response, :model),
                 finish_reason: get_in(response, [:choices, Access.at(0), :finish_reason]),
                 usage: Map.get(response, :usage)
               }
             }}

          {:error, _json_error} ->
            # Fallback to text parsing
            parse_text_response(content)
        end
    end
  end

  defp parse_score(score) when is_number(score), do: max(0.0, min(1.0, score))

  defp parse_score(score) when is_binary(score) do
    case Float.parse(score) do
      {num, _} -> max(0.0, min(1.0, num))
      :error -> 0.5
    end
  end

  defp parse_score(_), do: 0.5

  defp parse_confidence(confidence) when is_number(confidence), do: max(0.0, min(1.0, confidence))

  defp parse_confidence(confidence) when is_binary(confidence) do
    case Float.parse(confidence) do
      {num, _} -> max(0.0, min(1.0, num))
      :error -> 0.7
    end
  end

  defp parse_confidence(_), do: 0.7

  defp parse_issues(issues) when is_list(issues) do
    Enum.map(issues, &parse_single_issue/1)
  end

  defp parse_issues(_), do: []

  defp parse_single_issue(issue) when is_map(issue) do
    %{
      type: Map.get(issue, "type", "general"),
      severity: Map.get(issue, "severity", "medium"),
      description: Map.get(issue, "description", ""),
      line: parse_line_number(Map.get(issue, "line"))
    }
  end

  defp parse_single_issue(_), do: %{type: "unknown", severity: "low", description: ""}

  defp parse_line_number(line) when is_integer(line) and line > 0, do: line

  defp parse_line_number(line) when is_binary(line) do
    case Integer.parse(line) do
      {num, _} when num > 0 -> num
      _ -> nil
    end
  end

  defp parse_line_number(_), do: nil

  defp parse_recommendations(recommendations) when is_list(recommendations) do
    Enum.map(recommendations, fn
      rec when is_binary(rec) -> rec
      rec when is_map(rec) -> Map.get(rec, "description", "")
      _ -> ""
    end)
    |> Enum.filter(&(String.length(&1) > 0))
  end

  defp parse_recommendations(_), do: []

  defp parse_text_response(text) do
    # Fallback text parsing for non-JSON responses
    Logger.info("Parsing OpenAI text response as fallback")

    {:ok,
     %{
       overall_score: extract_score_from_text(text),
       confidence: 0.7,
       issues: [],
       recommendations: extract_recommendations_from_text(text),
       reasoning: text,
       metadata: %{parsed_as_text: true}
     }}
  end

  defp extract_score_from_text(text) do
    # Look for score indicators in text
    case Regex.run(~r/score[:\s]+(\d+\.?\d*)/i, text) do
      [_, score_str] ->
        case Float.parse(score_str) do
          {score, _} when score <= 1.0 -> score
          {score, _} when score <= 10.0 -> score / 10.0
          {score, _} when score <= 100.0 -> score / 100.0
          _ -> 0.7
        end

      _ ->
        0.7
    end
  end

  defp extract_recommendations_from_text(text) do
    # Extract bullet points and numbered lists as recommendations
    lines = String.split(text, "\n")

    recommendations =
      Enum.filter(lines, fn line ->
        String.match?(line, ~r/^\s*[-*\d\.]\s+/) and String.length(String.trim(line)) > 10
      end)

    case recommendations do
      [] -> ["Consider reviewing code structure and best practices"]
      recs -> Enum.map(recs, &String.trim/1)
    end
  end

  # Model selection and optimization

  def select_optimal_openai_model(evaluation_type, quality_threshold, code_complexity) do
    base_recommendation =
      case evaluation_type do
        type when type in [:security, :performance] -> "gpt-4o"
        _ -> "gpt-4o-mini"
      end

    # Upgrade model for high quality requirements
    model =
      if quality_threshold > 0.85 or code_complexity > 0.7 do
        "gpt-4o"
      else
        base_recommendation
      end

    model
  end

  def build_openai_messages(system_prompt, user_prompt) do
    [
      %{
        role: "system",
        content: system_prompt
      },
      %{
        role: "user",
        content: user_prompt
      }
    ]
  end

  def calculate_openai_cost(model, input_tokens, output_tokens) do
    rates =
      case model do
        # Per 1K tokens
        "gpt-4o" -> %{input: 0.03, output: 0.06}
        # Per 1K tokens
        "gpt-4o-mini" -> %{input: 0.01, output: 0.02}
        # Default fallback
        _ -> %{input: 0.015, output: 0.03}
      end

    input_cost = input_tokens / 1000 * rates.input
    output_cost = output_tokens / 1000 * rates.output

    input_cost + output_cost
  end
end
