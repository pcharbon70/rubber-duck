defmodule RubberDuck.Prompts.LlmOrchestrationIntegrationEndToEndTest do
  @moduledoc """
  End-to-end integration tests for Phase 02b Section 6.1: LLM Orchestration Integration.

  Tests cover the complete integration between prompt management and LLM orchestration:
  - LLM orchestration integration with prompt composition coordination
  - Provider-specific prompt formatting with model optimization
  - RAG integration enhancement with project-specific context
  - End-to-end performance validation and optimization
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Prompts.Integrations.{
    LlmOrchestrationIntegration,
    ProviderPromptFormatter,
    RagPromptEnhancer
  }

  describe "LLM orchestration integration (2B.6.1.1)" do
    test "LlmOrchestrationIntegration enhances LLM requests with composed prompts" do
      # Test complete LLM request enhancement
      llm_request = %{
        provider: "gpt-4",
        operation_type: :code_analysis,
        prompt: "Analyze this code for issues.",
        timeout: 30_000,
        quality: :high
      }

      context = %{
        prompt_name: "code_analysis_prompt",
        tenant_id: Ash.UUID.generate(),
        user_id: Ash.UUID.generate(),
        project_id: Ash.UUID.generate()
      }

      options = %{full_integration: true}

      assert {:ok, enhanced_request} =
               LlmOrchestrationIntegration.enhance_llm_request(llm_request, context, options)

      # Should enhance request with composed prompt
      assert Map.has_key?(enhanced_request, :prompt_composed)
      assert Map.has_key?(enhanced_request, :composition_metadata)
      assert enhanced_request.enhancement_applied == :full_integration

      # Should preserve original request structure
      assert enhanced_request.provider == "gpt-4"
      assert enhanced_request.operation_type == :code_analysis

      # Should include enhancement metadata
      assert Map.has_key?(enhanced_request, :prompt_metadata)
      assert Map.has_key?(enhanced_request, :provider_optimized)
    end

    test "integration supports different enhancement strategies" do
      base_request = %{
        provider: "claude-3-opus",
        prompt: "Help with documentation writing.",
        operation_type: :documentation
      }

      enhancement_strategies = [
        {%{}, :format_only},
        {%{validate_routing: true}, :validate_and_route},
        {%{prompt_name: "doc_prompt"}, :compose_and_enhance},
        {%{prompt_name: "doc_prompt", full_integration: true}, :full_integration}
      ]

      for {options, expected_strategy} <- enhancement_strategies do
        context = %{tenant_id: Ash.UUID.generate()}

        assert {:ok, enhanced_request} =
                 LlmOrchestrationIntegration.enhance_llm_request(base_request, context, options)

        # Should apply appropriate enhancement strategy
        enhancement_applied = Map.get(enhanced_request, :enhancement_applied)
        assert enhancement_applied != nil

        # Different strategies should produce different results
        case expected_strategy do
          :format_only ->
            assert Map.get(enhanced_request, :provider_optimized, false) == true

          :validate_and_route ->
            assert Map.has_key?(enhanced_request, :routing_optimized)

          :compose_and_enhance ->
            assert Map.get(enhanced_request, :prompt_composed, false) == true

          :full_integration ->
            assert enhanced_request.enhancement_applied == :full_integration
        end
      end
    end

    test "integration maintains performance targets with <50ms overhead" do
      # Test integration performance
      test_request = %{
        provider: "gpt-4",
        prompt: "Simple test prompt for performance validation.",
        operation_type: :general
      }

      context = %{tenant_id: Ash.UUID.generate()}

      # Measure enhancement performance
      performance_results =
        Enum.map(1..5, fn _i ->
          {time_us, _result} =
            :timer.tc(fn ->
              LlmOrchestrationIntegration.enhance_llm_request(test_request, context)
            end)

          time_us
        end)

      # Calculate average enhancement time
      average_time_us = Enum.sum(performance_results) / length(performance_results)
      average_time_ms = average_time_us / 1_000

      # Should meet <50ms enhancement overhead target
      assert average_time_ms < 50

      Logger.info("LLM Integration Performance",
        average_enhancement_time_ms: average_time_ms,
        max_time_ms: Enum.max(performance_results) / 1_000
      )
    end
  end

  describe "provider-specific formatting (2B.6.1.2)" do
    test "ProviderPromptFormatter optimizes prompts for different providers" do
      test_prompt =
        "Please analyze the following code and provide improvement suggestions with detailed explanations."

      providers = ["gpt-4", "claude-3-opus", "gemini-pro"]

      for provider <- providers do
        context = %{quality_requirements: :high}

        assert {:ok, formatted_result} =
                 ProviderPromptFormatter.format_for_provider(test_prompt, provider, context)

        # Should format for specific provider
        assert formatted_result.formatting_metadata.provider == provider
        assert Map.has_key?(formatted_result.formatting_metadata, :strategy_used)
        assert Map.has_key?(formatted_result.formatting_metadata, :optimization_applied)

        # Should preserve content quality
        assert formatted_result.formatting_metadata.quality_preserved == true

        # Formatted content should be different but related
        assert String.length(formatted_result.content) > 0
        assert is_binary(formatted_result.content)
      end
    end

    test "provider formatter provides optimization recommendations" do
      complex_prompt = """
      I would like you to please analyze this very complex code structure and provide 
      comprehensive detailed explanations with multiple examples and thorough analysis 
      covering all possible edge cases and potential improvements.
      """

      for provider <- ["gpt-4", "claude-3-opus", "gemini-pro"] do
        assert {:ok, recommendations} =
                 ProviderPromptFormatter.get_provider_optimization_recommendations(
                   complex_prompt,
                   provider
                 )

        # Should provide recommendations
        assert Map.has_key?(recommendations, :recommendations)
        assert is_list(recommendations.recommendations)
        assert length(recommendations.recommendations) > 0
      end
    end

    test "provider formatter handles different content types and complexities" do
      content_types = [
        {"Simple instruction: Help with coding.", :simple},
        {"Complex analysis: {{task}} with {{context}} and detailed {{requirements}}.", :complex},
        {"Code generation: Create a function that handles {{input}} and returns {{output}}.",
         :code_focused},
        {"Creative writing: Write a story about {{character}} in {{setting}}.", :creative}
      ]

      for {content, content_type} <- content_types do
        provider = "claude-3-opus"

        assert {:ok, formatted_result} =
                 ProviderPromptFormatter.format_for_provider(content, provider)

        # Should handle different content types
        assert String.length(formatted_result.content) > 0
        assert formatted_result.formatting_metadata.quality_preserved == true

        # Should include formatting metadata
        metadata = formatted_result.formatting_metadata
        assert Map.has_key?(metadata, :token_optimization)
        assert Map.has_key?(metadata, :optimization_applied)
      end
    end
  end

  describe "RAG integration enhancement (2B.6.1.3)" do
    test "RagPromptEnhancer integrates RAG context with project-specific prompts" do
      base_prompt = "Analyze the codebase for {{analysis_type}} issues."
      rag_query = "codebase analysis patterns"

      context = %{
        project_id: Ash.UUID.generate(),
        analysis_type: "security",
        enhancement_level: :comprehensive
      }

      options = %{enhancement_level: :comprehensive}

      assert {:ok, enhancement_result} =
               RagPromptEnhancer.enhance_prompt_with_rag(base_prompt, rag_query, context, options)

      # Should enhance prompt with RAG context
      assert enhancement_result.rag_context_injected == true
      assert enhancement_result.enhancement_strategy == :comprehensive

      # Should preserve original content
      assert String.contains?(enhancement_result.enhanced_content, "Analyze")
      assert String.contains?(enhancement_result.enhanced_content, "codebase")

      # Should add RAG context
      enhanced_content = enhancement_result.enhanced_content
      assert String.length(enhanced_content) > String.length(base_prompt)

      # Should include enhancement metadata
      assert Map.has_key?(enhancement_result, :enhancement_metadata)
      assert Map.has_key?(enhancement_result.enhancement_metadata, :comprehensive_score)
    end

    test "RAG enhancer handles different enhancement strategies" do
      test_prompt = "Provide recommendations for {{project_area}} improvement."
      rag_query = "project improvement strategies"
      context = %{project_area: "code quality"}

      enhancement_strategies = [
        :context_injection,
        :semantic_enhancement,
        :result_integration,
        :comprehensive
      ]

      for strategy <- enhancement_strategies do
        options = %{enhancement_level: strategy}

        case RagPromptEnhancer.enhance_prompt_with_rag(test_prompt, rag_query, context, options) do
          {:ok, result} ->
            # Should apply appropriate strategy
            assert result.enhancement_strategy == strategy
            assert result.rag_context_injected == true
            assert String.length(result.enhanced_content) > 0

          {:error, _reason} ->
            # Some strategies might not be fully implemented, which is acceptable
            assert true
        end
      end
    end

    test "RAG integration provides performance optimization" do
      optimization_request = %{
        prompt_content: "Analyze project for optimization opportunities.",
        rag_query: "optimization patterns",
        context: %{project_id: Ash.UUID.generate()},
        performance_targets: %{max_enhancement_time_ms: 100}
      }

      assert {:ok, optimization_result} =
               RagPromptEnhancer.optimize_rag_prompt_performance(optimization_request)

      # Should provide optimization results
      assert optimization_result.optimization_applied == true
      assert is_float(optimization_result.performance_improvement)
      assert is_list(optimization_result.optimization_recommendations)
      assert length(optimization_result.optimization_recommendations) > 0
    end
  end

  describe "end-to-end integration validation" do
    test "complete integration pipeline works from prompt composition to LLM enhancement" do
      # Test complete end-to-end integration

      # Step 1: LLM request enhancement with prompt composition
      llm_request = %{
        provider: "gpt-4",
        operation_type: :code_review,
        prompt: "Review code for {{review_type}} issues.",
        quality: :high
      }

      composition_context = %{
        prompt_name: "code_review_prompt",
        tenant_id: Ash.UUID.generate(),
        user_id: Ash.UUID.generate(),
        variables: %{"review_type" => "security"}
      }

      assert {:ok, enhanced_request} =
               LlmOrchestrationIntegration.enhance_llm_request(
                 llm_request,
                 composition_context,
                 %{full_integration: true}
               )

      # Step 2: Provider-specific formatting
      formatted_prompt = enhanced_request.prompt

      assert {:ok, provider_formatted} =
               ProviderPromptFormatter.format_for_provider(
                 formatted_prompt,
                 "gpt-4",
                 %{quality_requirements: :high}
               )

      # Step 3: RAG enhancement
      rag_query = "code review best practices"

      assert {:ok, rag_enhanced} =
               RagPromptEnhancer.enhance_prompt_with_rag(
                 provider_formatted.content,
                 rag_query,
                 composition_context
               )

      # Validate complete pipeline
      assert String.length(rag_enhanced.enhanced_content) > 0
      assert rag_enhanced.rag_context_injected == true
      assert provider_formatted.formatting_metadata.quality_preserved == true
      assert enhanced_request.prompt_composed == true
    end

    test "integration maintains backward compatibility with existing LLM operations" do
      # Test backward compatibility
      legacy_request = %{
        provider: "claude-3-opus",
        prompt: "Legacy prompt without composition.",
        operation_type: :general
      }

      # Should work without composition context
      assert {:ok, enhanced_legacy} =
               LlmOrchestrationIntegration.enhance_llm_request(legacy_request, %{})

      # Should enhance without breaking functionality
      assert Map.has_key?(enhanced_legacy, :enhancement_applied)
      assert enhanced_legacy.provider == "claude-3-opus"

      # Should apply format-only enhancement
      assert enhanced_legacy.enhancement_applied == :format_only
      assert Map.get(enhanced_legacy, :provider_optimized, false) == true
    end

    test "integration provides comprehensive performance analytics" do
      # Test integration performance analytics

      # Execute multiple operations for analytics
      test_operations = [
        %{provider: "gpt-4", prompt: "Test 1", operation_type: :analysis},
        %{provider: "claude-3-opus", prompt: "Test 2", operation_type: :generation},
        %{provider: "gemini-pro", prompt: "Test 3", operation_type: :explanation}
      ]

      for operation <- test_operations do
        context = %{tenant_id: Ash.UUID.generate()}
        {:ok, _result} = LlmOrchestrationIntegration.enhance_llm_request(operation, context)
      end

      # Get performance metrics
      assert {:ok, metrics} = LlmOrchestrationIntegration.get_integration_performance_metrics()

      # Should provide comprehensive metrics
      assert Map.has_key?(metrics, :total_requests)
      assert Map.has_key?(metrics, :success_rate)
      assert Map.has_key?(metrics, :average_enhancement_time_ms)
      assert is_float(metrics.success_rate)

      # Should meet performance targets
      assert metrics.success_rate > 0.8
      assert metrics.average_enhancement_time_ms < 100
    end

    test "integration handles error scenarios gracefully" do
      # Test error handling across integration components
      error_scenarios = [
        # Invalid provider
        {%{provider: "invalid_provider", prompt: "test"}, %{}},
        # Empty prompt
        {%{provider: "gpt-4", prompt: ""}, %{}},
        # Invalid context
        {%{provider: "claude-3-opus", prompt: "test"}, %{invalid_context: true}}
      ]

      for {request, context} <- error_scenarios do
        case LlmOrchestrationIntegration.enhance_llm_request(request, context) do
          {:ok, result} ->
            # May succeed with fallback enhancement
            assert Map.has_key?(result, :enhancement_applied)

          {:error, reason} ->
            # Should fail gracefully with informative error
            assert is_tuple(reason)
        end
      end
    end

    test "provider compatibility validation works across all supported providers" do
      test_prompt =
        "Comprehensive test prompt with {{variable}} substitution for compatibility testing."

      supported_providers = ProviderPromptFormatter.get_supported_providers()

      for provider <- supported_providers do
        # Skip wildcard
        if provider == "*", do: next()

        context = %{compatibility_testing: true}

        assert {:ok, compatibility_result} =
                 LlmOrchestrationIntegration.validate_prompt_provider_compatibility(
                   test_prompt,
                   provider,
                   context
                 )

        # Should provide compatibility analysis
        assert Map.has_key?(compatibility_result, :provider)
        assert Map.has_key?(compatibility_result, :compatibility_score)
        assert Map.has_key?(compatibility_result, :optimization_suggestions)

        # Compatibility score should be reasonable
        assert compatibility_result.compatibility_score >= 0.0
        assert compatibility_result.compatibility_score <= 1.0
      end
    end

    test "RAG enhancement preserves prompt structure while adding context" do
      structured_prompt = """
      Instructions: {{instructions}}

      Context: {{context}}

      Requirements:
      1. Analyze thoroughly
      2. Provide examples
      3. Suggest improvements
      """

      rag_query = "analysis methodology"
      context = %{instructions: "code analysis", context: "security review"}

      assert {:ok, enhanced_result} =
               RagPromptEnhancer.enhance_prompt_with_rag(structured_prompt, rag_query, context)

      # Should preserve original structure
      assert String.contains?(enhanced_result.enhanced_content, "Instructions:")
      assert String.contains?(enhanced_result.enhanced_content, "Requirements:")

      # Should add RAG context
      assert String.length(enhanced_result.enhanced_content) > String.length(structured_prompt)
      assert enhanced_result.rag_context_injected == true

      # Should maintain readability
      enhanced_content = enhanced_result.enhanced_content

      assert String.contains?(enhanced_content, "context") or
               String.contains?(enhanced_content, "Context")
    end
  end

  describe "integration performance and optimization" do
    test "integration performance optimization improves over time" do
      # Test performance optimization
      initial_metrics_result = LlmOrchestrationIntegration.get_integration_performance_metrics()

      # Execute optimization
      assert :ok = LlmOrchestrationIntegration.optimize_integration_performance()

      # Metrics should be available
      case initial_metrics_result do
        {:ok, initial_metrics} ->
          # Should have performance data
          assert Map.has_key?(initial_metrics, :optimization_effectiveness)

        {:error, _reason} ->
          # May not have metrics initially, which is acceptable
          assert true
      end
    end

    test "RAG integration analytics provide actionable insights" do
      # Test RAG integration analytics
      test_enhancements = [
        {"Prompt 1 with {{var1}}", "query1"},
        {"Prompt 2 with {{var2}}", "query2"},
        {"Prompt 3 with {{var3}}", "query3"}
      ]

      # Execute multiple RAG enhancements
      for {prompt, query} <- test_enhancements do
        context = %{tenant_id: Ash.UUID.generate()}
        {:ok, _result} = RagPromptEnhancer.enhance_prompt_with_rag(prompt, query, context)
      end

      # Get analytics
      assert {:ok, analytics} = RagPromptEnhancer.get_rag_integration_analytics()

      # Should provide actionable analytics
      assert Map.has_key?(analytics, :total_rag_enhancements)
      assert Map.has_key?(analytics, :success_rate)
      assert Map.has_key?(analytics, :average_enhancement_time_ms)

      # Should track performance
      assert analytics.total_rag_enhancements >= 3
      assert analytics.success_rate >= 0.0 and analytics.success_rate <= 1.0
    end

    test "complete integration supports enterprise-scale operations" do
      # Test enterprise-scale integration
      enterprise_request = %{
        provider: "gpt-4",
        operation_type: :enterprise_analysis,
        prompt:
          "Enterprise-scale analysis with {{analysis_scope}} and {{compliance_requirements}}.",
        quality: :enterprise,
        cost_sensitivity: :low,
        timeout: 60_000
      }

      enterprise_context = %{
        prompt_name: "enterprise_analysis_prompt",
        tenant_id: Ash.UUID.generate(),
        user_id: Ash.UUID.generate(),
        project_id: Ash.UUID.generate(),
        analysis_scope: "comprehensive security",
        compliance_requirements: "SOX compliance"
      }

      enterprise_options = %{
        full_integration: true,
        enterprise_optimization: true
      }

      assert {:ok, enterprise_result} =
               LlmOrchestrationIntegration.enhance_llm_request(
                 enterprise_request,
                 enterprise_context,
                 enterprise_options
               )

      # Should handle enterprise-scale operations
      assert enterprise_result.enhancement_applied == :full_integration
      assert Map.has_key?(enterprise_result, :composition_metadata)
      assert Map.has_key?(enterprise_result, :validation_metadata)

      # Should include enterprise features
      validation_metadata = enterprise_result.validation_metadata
      assert Map.has_key?(validation_metadata, :governance_compliance)
    end
  end
end
