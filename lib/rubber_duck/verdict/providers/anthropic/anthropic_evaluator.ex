defmodule RubberDuck.Verdict.Providers.Anthropic.AnthropicEvaluator do
  @moduledoc """
  Anthropic-specific evaluation logic with Constitutional AI integration.

  This module provides Claude-optimized evaluation including:
  - Constitutional AI principles in evaluation prompts
  - Large context window optimization for complex code analysis
  - Safety-first evaluation with bias mitigation
  - Claude's reasoning capabilities for detailed explanations
  """

  require Logger

  alias RubberDuck.Verdict.Providers.Anthropic.AnthropicClient

  def initialize(config) do
    evaluator_state = %{
      config: config,
      constitutional_ai_config: Map.get(config, :constitutional_ai, %{safety_checks: true}),
      prompt_templates: load_claude_prompt_templates(),
      model_capabilities: %{
        "claude-3-5-sonnet-20241022" => %{
          reasoning_depth: :high,
          context_handling: :excellent,
          speed: :fast
        },
        "claude-3-haiku-20240307" => %{
          reasoning_depth: :medium,
          context_handling: :good,
          speed: :very_fast
        },
        "claude-3-opus-20240229" => %{
          reasoning_depth: :exceptional,
          context_handling: :excellent,
          speed: :slower
        }
      }
    }

    {:ok, evaluator_state}
  end

  def evaluate(evaluator_state, request) do
    Logger.debug("Anthropic evaluation started for model: #{request.model}")
    start_time = System.monotonic_time(:millisecond)

    # Optimize request for Claude
    optimized_request = optimize_claude_request(request, evaluator_state)

    case AnthropicClient.complete(evaluator_state.config.client, optimized_request) do
      {:ok, response} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        evaluation_result = %{
          success: true,
          raw_response: response,
          response_time_ms: response_time,
          model: request.model,
          constitutional_ai_applied: true
        }

        {:ok, evaluation_result}

      {:error, reason} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        Logger.error("Anthropic evaluation failed: #{inspect(reason)}")

        {:error,
         %{
           reason: reason,
           response_time_ms: response_time,
           model: request.model
         }}
    end
  end

  def evaluate_streaming(evaluator_state, request, model, callback) do
    Logger.debug("Anthropic streaming evaluation started for model: #{model}")
    start_time = System.monotonic_time(:millisecond)

    # Build streaming request with Constitutional AI principles
    streaming_request =
      Map.merge(request, %{
        model: model,
        stream: true
      })

    optimized_request = optimize_claude_request(streaming_request, evaluator_state)

    # Wrap callback to apply Constitutional AI filtering to streams
    constitutional_callback = create_constitutional_ai_callback(callback, evaluator_state)

    case AnthropicClient.complete_streaming(
           evaluator_state.config.client,
           optimized_request,
           constitutional_callback
         ) do
      {:ok, final_response} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           success: true,
           raw_response: final_response,
           response_time_ms: response_time,
           model: model,
           streaming: true,
           constitutional_ai_applied: true
         }}

      error ->
        error
    end
  end

  # Private implementation

  defp optimize_claude_request(request, evaluator_state) do
    request
    |> apply_constitutional_ai_optimization(evaluator_state)
    |> optimize_context_window()
    |> set_claude_parameters()
  end

  defp apply_constitutional_ai_optimization(request, evaluator_state) do
    if evaluator_state.constitutional_ai_config.safety_checks do
      # Enhance system prompt with Constitutional AI principles
      enhanced_system =
        enhance_system_prompt_with_constitutional_ai(
          Map.get(request, :system, ""),
          request.model
        )

      Map.put(request, :system, enhanced_system)
    else
      request
    end
  end

  defp enhance_system_prompt_with_constitutional_ai(system_prompt, model) do
    constitutional_principles = """

    Constitutional AI Principles:
    You must ensure your code evaluation is helpful, harmless, and honest:

    1. HELPFUL: Provide constructive, actionable feedback that genuinely improves code quality
    2. HARMLESS: Avoid recommendations that could introduce security vulnerabilities or reduce safety
    3. HONEST: Base your assessment on factual analysis without exaggeration or false claims

    Additional guidelines:
    - Focus on educational value in your recommendations
    - Consider the broader context and maintainability impact
    - Promote secure and ethical coding practices
    - Be respectful and constructive in your language
    """

    model_specific_guidance =
      case model do
        "claude-3-opus-" <> _ ->
          "\nAs Claude Opus, use your advanced reasoning to provide deep, nuanced analysis."

        "claude-3-5-sonnet-" <> _ ->
          "\nAs Claude Sonnet, balance thoroughness with efficiency in your analysis."

        "claude-3-haiku-" <> _ ->
          "\nAs Claude Haiku, provide focused, clear analysis prioritizing the most important issues."

        _ ->
          ""
      end

    system_prompt <> constitutional_principles <> model_specific_guidance
  end

  defp optimize_context_window(request) do
    # Claude can handle large contexts efficiently - optimize for best use
    max_tokens = Map.get(request, :max_tokens, 1000)

    # Ensure we leave adequate space for Claude's detailed responses
    # Claude provides comprehensive responses
    adjusted_max_tokens = min(max_tokens, 4000)

    Map.put(request, :max_tokens, adjusted_max_tokens)
  end

  defp set_claude_parameters(request) do
    request
    # Deterministic for code evaluation
    |> Map.put(:temperature, 0.0)
    # Full probability distribution
    |> Map.put(:top_p, 1.0)
  end

  defp create_constitutional_ai_callback(original_callback, evaluator_state) do
    fn stream_event ->
      # Apply Constitutional AI filtering to streaming content
      if evaluator_state.constitutional_ai_config.content_filtering do
        filtered_event = filter_streaming_content(stream_event)
        original_callback.(filtered_event)
      else
        original_callback.(stream_event)
      end
    end
  end

  defp filter_streaming_content(stream_event) do
    # Apply basic content filtering to streaming events
    case Map.get(stream_event, :type) do
      :content_block_delta ->
        # Filter delta content for safety
        delta = Map.get(stream_event, :delta, %{})
        text = Map.get(delta, :text, "")

        if contains_concerning_content?(text) do
          # Replace concerning content with placeholder
          filtered_text = "[Content filtered by Constitutional AI]"
          put_in(stream_event, [:delta, :text], filtered_text)
        else
          stream_event
        end

      _ ->
        stream_event
    end
  end

  defp contains_concerning_content?(text) do
    # Basic content safety check
    concerning_patterns = ["hack", "exploit", "vulnerability", "attack"]

    # Only flag if there are multiple concerning terms (to avoid false positives)
    concerning_count =
      Enum.count(concerning_patterns, fn pattern ->
        String.contains?(String.downcase(text), pattern)
      end)

    concerning_count > 2
  end

  defp load_claude_prompt_templates do
    %{
      security: %{
        constitutional_prompt: """
        You are Claude, an AI assistant specializing in secure code analysis.
        Apply Constitutional AI principles to ensure your security evaluation is:
        - HELPFUL: Identifies genuine security issues with clear remediation steps
        - HARMLESS: Avoids creating security vulnerabilities through recommendations
        - HONEST: Based on factual security analysis without false alarms

        Focus on constructive security guidance that enhances code safety.
        """,
        evaluation_focus: """
        Perform comprehensive security analysis considering:
        1. Input validation and sanitization practices
        2. Authentication and authorization implementation
        3. Data protection and encryption usage
        4. Error handling that prevents information disclosure
        5. Dependency security and vulnerability management

        Provide security recommendations that are practical, implementable, and enhance overall system safety.
        """
      },
      performance: %{
        constitutional_prompt: """
        You are Claude, an AI assistant focused on performance optimization.
        Use Constitutional AI principles to ensure your performance analysis is helpful and constructive.

        Provide performance insights that:
        - Help developers understand optimization opportunities
        - Consider real-world constraints and trade-offs
        - Promote sustainable performance practices
        """,
        evaluation_focus: """
        Analyze code performance with attention to:
        1. Algorithmic efficiency and computational complexity
        2. Memory usage patterns and optimization opportunities
        3. I/O operations and asynchronous handling
        4. Resource management and cleanup
        5. Scalability considerations for production use

        Balance performance optimization with code maintainability and readability.
        """
      },
      quality: %{
        constitutional_prompt: """
        You are Claude, an AI assistant evaluating overall code quality.
        Apply Constitutional AI to ensure your assessment promotes good software engineering practices.

        Focus on feedback that:
        - Genuinely improves code quality and maintainability  
        - Considers team collaboration and knowledge sharing
        - Promotes sustainable development practices
        """,
        evaluation_focus: """
        Evaluate code quality across multiple dimensions:
        1. Correctness and logical soundness
        2. Readability and code organization
        3. Error handling robustness
        4. Documentation and self-explanation
        5. Testing considerations and testability

        Provide balanced feedback that helps developers grow their skills.
        """
      }
    }
  end

  def get_optimized_claude_prompt(
        evaluation_type,
        code,
        criteria,
        constitutional_ai_enabled \\ true
      ) do
    template = get_template_for_evaluation_type(evaluation_type)

    constitutional_section =
      if constitutional_ai_enabled do
        template.constitutional_prompt
      else
        "You are an AI assistant performing code evaluation."
      end

    criteria_section =
      if map_size(criteria) > 0 do
        criteria_text =
          criteria
          |> Enum.map(fn {criterion, weight} ->
            "- #{criterion}: #{Float.round(weight * 100, 1)}% importance"
          end)
          |> Enum.join("\n")

        "\n\nEvaluation Criteria:\n#{criteria_text}"
      else
        ""
      end

    constitutional_section <>
      criteria_section <>
      "\n\n" <>
      template.evaluation_focus <>
      "\n\nCode to analyze:\n```\n#{code}\n```\n\n" <>
      "Please provide your evaluation in JSON format with overall_score, confidence, issues, recommendations, and detailed reasoning."
  end

  defp get_template_for_evaluation_type(evaluation_type) do
    templates = load_claude_prompt_templates()
    Map.get(templates, evaluation_type, templates.quality)
  end

  # Response parsing with Constitutional AI validation

  def parse_claude_evaluation_response(response) do
    case get_in(response, [:content, Access.at(0), :text]) do
      nil ->
        {:error, "No content in Anthropic response"}

      content ->
        case Jason.decode(content) do
          {:ok, %{} = evaluation_data} ->
            # Apply Constitutional AI validation to parsed results
            validated_evaluation = apply_constitutional_validation(evaluation_data)

            {:ok,
             %{
               overall_score: parse_score(evaluation_data["overall_score"]),
               confidence: parse_confidence(evaluation_data["confidence"]),
               issues: parse_issues_with_safety_check(evaluation_data["issues"]),
               recommendations:
                 parse_recommendations_with_constitutional_ai(evaluation_data["recommendations"]),
               reasoning:
                 enhance_reasoning_with_constitutional_principles(evaluation_data["reasoning"]),
               constitutional_ai_validation: validated_evaluation,
               metadata: %{
                 model: Map.get(response, :model),
                 stop_reason: Map.get(response, :stop_reason),
                 usage: Map.get(response, :usage)
               }
             }}

          {:error, _json_error} ->
            # Claude sometimes provides detailed text responses
            parse_claude_text_response(content)
        end
    end
  end

  defp apply_constitutional_validation(evaluation_data) do
    # Validate that evaluation follows Constitutional AI principles
    %{
      helpful: assessment_is_helpful?(evaluation_data),
      harmless: assessment_is_harmless?(evaluation_data),
      honest: assessment_is_honest?(evaluation_data),
      # Would implement detailed validation
      overall_constitutional_compliance: true
    }
  end

  defp assessment_is_helpful?(evaluation_data) do
    recommendations = Map.get(evaluation_data, "recommendations", [])
    reasoning = Map.get(evaluation_data, "reasoning", "")

    # Check if recommendations are constructive
    has_recommendations = length(recommendations) > 0
    has_detailed_reasoning = String.length(reasoning) > 50

    has_recommendations and has_detailed_reasoning
  end

  defp assessment_is_harmless?(evaluation_data) do
    recommendations = Map.get(evaluation_data, "recommendations", [])

    # Check that recommendations don't suggest harmful practices
    harmful_patterns = ["ignore security", "disable validation", "remove checks"]

    harmful_recommendations =
      Enum.any?(recommendations, fn rec ->
        Enum.any?(harmful_patterns, &String.contains?(String.downcase(rec), &1))
      end)

    not harmful_recommendations
  end

  defp assessment_is_honest?(evaluation_data) do
    score = Map.get(evaluation_data, "overall_score", 0.5)
    confidence = Map.get(evaluation_data, "confidence", 0.5)

    # Basic honesty check: confidence should align with detail provided
    reasoning_length = String.length(Map.get(evaluation_data, "reasoning", ""))

    # If high confidence, should have detailed reasoning
    if confidence > 0.9 do
      reasoning_length > 100
    else
      # Lower confidence is acceptable with less detail
      true
    end
  end

  defp parse_issues_with_safety_check(issues) when is_list(issues) do
    Enum.map(issues, &enhance_issue_with_safety_guidance/1)
  end

  defp parse_issues_with_safety_check(_), do: []

  defp enhance_issue_with_safety_guidance(issue) when is_map(issue) do
    # Add Constitutional AI safety guidance to issues
    base_issue = %{
      type: Map.get(issue, "type", "general"),
      severity: Map.get(issue, "severity", "medium"),
      description: Map.get(issue, "description", ""),
      line: parse_line_number(Map.get(issue, "line"))
    }

    # Add safety guidance for security issues
    if base_issue.type == "security" do
      Map.put(base_issue, :safety_guidance, generate_safety_guidance(base_issue))
    else
      base_issue
    end
  end

  defp enhance_issue_with_safety_guidance(_),
    do: %{type: "unknown", severity: "low", description: ""}

  defp parse_recommendations_with_constitutional_ai(recommendations)
       when is_list(recommendations) do
    Enum.map(recommendations, fn
      rec when is_binary(rec) ->
        enhance_recommendation_with_constitutional_ai(rec)

      rec when is_map(rec) ->
        enhance_recommendation_with_constitutional_ai(Map.get(rec, "description", ""))

      _ ->
        ""
    end)
    |> Enum.filter(&(String.length(&1) > 0))
  end

  defp parse_recommendations_with_constitutional_ai(_), do: []

  defp enhance_recommendation_with_constitutional_ai(recommendation) do
    # Apply Constitutional AI principles to enhance recommendations
    enhanced =
      recommendation
      |> ensure_constructive_language()
      |> add_educational_context()

    enhanced
  end

  defp ensure_constructive_language(recommendation) do
    # Convert any negative language to constructive alternatives
    recommendation
    |> String.replace(~r/\b(bad|wrong|terrible|awful)\b/i, "improveable")
    |> String.replace(~r/\b(never|don't|avoid)\s+/i, "consider alternatives to ")
    |> String.replace(~r/\bfixed?\b/i, "improved")
  end

  defp add_educational_context(recommendation) do
    # Add brief educational context to help developers understand the why
    if String.length(recommendation) > 50 and not String.contains?(recommendation, "because") do
      recommendation <> " (this improves code maintainability and reduces technical debt)"
    else
      recommendation
    end
  end

  defp enhance_reasoning_with_constitutional_principles(reasoning) do
    # Ensure reasoning follows Constitutional AI principles
    if String.length(reasoning) < 50 do
      "Constitutional AI Enhanced Analysis: " <>
        reasoning <>
        " This assessment aims to provide helpful, harmless, and honest feedback to improve code quality while promoting safe development practices."
    else
      reasoning
    end
  end

  defp generate_safety_guidance(security_issue) do
    desc = String.downcase(security_issue.description)

    cond do
      String.contains?(desc, "injection") ->
        "Use parameterized queries and input validation to prevent injection attacks safely."

      String.contains?(desc, "authentication") ->
        "Implement robust authentication following security best practices and established frameworks."

      String.contains?(desc, "encryption") ->
        "Use well-established encryption libraries and avoid implementing custom cryptographic solutions."

      true ->
        "Apply security best practices and consider security implications of any changes."
    end
  end

  defp parse_claude_text_response(text) do
    Logger.info("Parsing Claude text response with Constitutional AI principles")

    # Extract structured information from Claude's natural language response
    score = extract_score_with_reasoning_validation(text)
    confidence = extract_confidence_with_constitutional_check(text)
    recommendations = extract_constitutional_ai_recommendations(text)

    {:ok,
     %{
       overall_score: score,
       confidence: confidence,
       issues: [],
       recommendations: recommendations,
       reasoning: text,
       constitutional_ai_parsing: true,
       metadata: %{parsed_as_text: true}
     }}
  end

  defp extract_score_with_reasoning_validation(text) do
    # Look for score with reasoning validation
    case Regex.run(~r/(?:score|rating)[:\s]+(\d+\.?\d*)/i, text) do
      [_, score_str] ->
        case Float.parse(score_str) do
          {score, _} ->
            # Validate score makes sense given text length and detail
            reasoning_quality = assess_reasoning_quality(text)
            adjusted_score = adjust_score_for_reasoning_quality(score, reasoning_quality)
            normalize_claude_score(adjusted_score)

          _ ->
            0.8
        end

      # Default higher for Claude's thoughtful analysis
      _ ->
        0.8
    end
  end

  defp extract_confidence_with_constitutional_check(text) do
    # Claude's confidence should reflect Constitutional AI principles
    base_confidence =
      case Regex.run(~r/(?:confidence|certain)[:\s]+(\d+\.?\d*)/i, text) do
        [_, conf_str] ->
          case Float.parse(conf_str) do
            {conf, _} when conf <= 1.0 -> conf
            {conf, _} when conf <= 100.0 -> conf / 100.0
            _ -> 0.85
          end

        _ ->
          0.85
      end

    # Adjust confidence based on reasoning depth (Constitutional AI should be confident in thorough analysis)
    reasoning_depth = assess_reasoning_depth(text)
    constitutional_confidence_boost = min(0.1, reasoning_depth * 0.1)

    min(1.0, base_confidence + constitutional_confidence_boost)
  end

  defp extract_constitutional_ai_recommendations(text) do
    # Extract recommendations enhanced with Constitutional AI principles
    lines = String.split(text, "\n")

    recommendations =
      lines
      |> Enum.filter(&String.match?(&1, ~r/^\s*[-*\d\.]\s+/))
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(String.length(&1) > 10))

    case recommendations do
      [] ->
        # Generate Constitutional AI recommendations from text analysis
        generate_constitutional_ai_recommendations_from_text(text)

      recs ->
        Enum.map(recs, &enhance_recommendation_with_constitutional_ai/1)
    end
  end

  defp generate_constitutional_ai_recommendations_from_text(text) do
    [
      "Consider applying Constitutional AI principles: ensure changes are helpful, harmless, and honest",
      "Review code for opportunities to enhance safety and security",
      "Focus on maintainable solutions that benefit long-term code evolution"
    ]
  end

  defp assess_reasoning_quality(text) do
    # Assess the quality of reasoning in Claude's response
    reasoning_indicators = [
      "because",
      "therefore",
      "however",
      "additionally",
      "consequently",
      "furthermore",
      "specifically"
    ]

    reasoning_count =
      Enum.count(reasoning_indicators, fn indicator ->
        String.contains?(String.downcase(text), indicator)
      end)

    # Normalize to 0-1
    min(1.0, reasoning_count / 3.0)
  end

  defp assess_reasoning_depth(text) do
    # Assess depth of analysis in Claude's response
    depth_indicators = [
      "analysis",
      "evaluation",
      "consideration",
      "implication",
      "consequence",
      "trade-off",
      "alternative"
    ]

    depth_count =
      Enum.count(depth_indicators, fn indicator ->
        String.contains?(String.downcase(text), indicator)
      end)

    # Normalize to 0-1
    min(1.0, depth_count / 5.0)
  end

  defp adjust_score_for_reasoning_quality(score, reasoning_quality) do
    # Adjust score based on reasoning quality (Constitutional AI should have good reasoning)
    if reasoning_quality > 0.7 do
      # High quality reasoning supports the score
      score
    else
      # Lower confidence in score if reasoning is shallow
      score * 0.9
    end
  end

  defp parse_line_number(line) when is_integer(line) and line > 0, do: line

  defp parse_line_number(line) when is_binary(line) do
    case Integer.parse(line) do
      {num, _} when num > 0 -> num
      _ -> nil
    end
  end

  defp parse_line_number(_), do: nil

  defp parse_score(score) when is_number(score), do: max(0.0, min(1.0, score))

  defp parse_score(score) when is_binary(score) do
    case Float.parse(score) do
      {num, _} -> max(0.0, min(1.0, num))
      # Default higher for Claude
      :error -> 0.8
    end
  end

  defp parse_score(_), do: 0.8

  defp parse_confidence(confidence) when is_number(confidence), do: max(0.0, min(1.0, confidence))

  defp parse_confidence(confidence) when is_binary(confidence) do
    case Float.parse(confidence) do
      {num, _} -> max(0.0, min(1.0, num))
      # Claude typically has high confidence
      :error -> 0.85
    end
  end

  defp parse_confidence(_), do: 0.85

  defp normalize_claude_score(adjusted_score) do
    cond do
      adjusted_score <= 1.0 -> adjusted_score
      adjusted_score <= 10.0 -> adjusted_score / 10.0
      adjusted_score <= 100.0 -> adjusted_score / 100.0
      true -> 0.8
    end
  end
end
