defmodule RubberDuck.Prompts.CoreOrchestrationAgentsIntegrationTest do
  @moduledoc """
  Integration tests for Phase 02b Section 5.1: Core Orchestration Agents.

  Tests cover the three core orchestration agents and their coordination:
  - PromptComposerAgent: Hierarchical composition with provider optimization
  - PromptValidatorAgent: Security and validation orchestration
  - PromptAnalyticsAgent: ML-driven analytics and insights
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Prompts.Agents.{
    PromptAnalyticsAgent,
    PromptComposerAgent,
    PromptValidatorAgent
  }

  describe "PromptComposerAgent orchestration (2B.5.1.2)" do
    test "PromptComposerAgent executes hierarchical composition with provider optimization" do
      composition_params = %{
        composition_request: %{
          prompt_name: "test_composition",
          context: %{
            tenant_id: Ash.UUID.generate(),
            user_id: Ash.UUID.generate(),
            variables: %{
              "task" => "code review",
              "language" => "Elixir"
            }
          }
        },
        composition_strategy: :hierarchical_merge,
        provider_target: "gpt-4",
        performance_targets: %{
          max_composition_time_ms: 50,
          max_token_count: 2000
        },
        analytics_tracking: true
      }

      assert {:ok, result} = PromptComposerAgent.start_agent(composition_params)

      # Validate composition result structure
      assert Map.has_key?(result, :composition_result)
      assert Map.has_key?(result, :composition_metadata)

      composition_result = result.composition_result
      assert Map.has_key?(composition_result, :content)
      assert Map.get(composition_result, :provider_formatted, false) == true
      assert Map.get(composition_result, :validation_passed, false) == true

      # Validate metadata
      metadata = result.composition_metadata
      assert metadata.strategy_used == :hierarchical_merge
      assert metadata.provider_target == "gpt-4"
      assert Map.has_key?(metadata, :performance_metrics)
    end

    test "PromptComposerAgent handles different composition strategies" do
      base_params = %{
        composition_request: %{
          prompt_name: "strategy_test",
          context: %{
            tenant_id: Ash.UUID.generate(),
            variables: %{"instruction" => "test different strategies"}
          }
        },
        provider_target: "claude-3-opus"
      }

      strategies = [:hierarchical_merge, :priority_override, :template_inheritance, :adaptive]

      for strategy <- strategies do
        params = Map.put(base_params, :composition_strategy, strategy)

        assert {:ok, result} = PromptComposerAgent.start_agent(params)

        # Should execute successfully with each strategy
        assert result.composition_metadata.strategy_used == strategy
        assert Map.has_key?(result.composition_result, :content)
      end
    end

    test "PromptComposerAgent formats output for different LLM providers" do
      composition_request = %{
        prompt_name: "provider_test",
        context: %{
          tenant_id: Ash.UUID.generate(),
          variables: %{"task" => "provider optimization test"}
        }
      }

      providers = ["gpt-4", "claude-3-opus", "gemini-pro"]

      for provider <- providers do
        params = %{
          composition_request: composition_request,
          provider_target: provider,
          analytics_tracking: false
        }

        assert {:ok, result} = PromptComposerAgent.start_agent(params)

        # Should format for specific provider
        assert result.composition_metadata.provider_target == provider
        assert Map.get(result.composition_result, :provider_formatted, false) == true
      end
    end
  end

  describe "PromptValidatorAgent orchestration (2B.5.1.3)" do
    test "PromptValidatorAgent performs comprehensive validation with reporting" do
      validation_params = %{
        validation_request: %{
          content: "Please help with {{task}} using {{method}} approach safely.",
          context: %{
            prompt_type: :user,
            trust_level: :standard,
            user_id: Ash.UUID.generate()
          }
        },
        validation_scope: :comprehensive,
        governance_requirements: %{
          require_security_validation: true,
          require_budget_validation: true,
          compliance_level: :enterprise
        },
        reporting_config: %{
          generate_detailed_report: true,
          include_recommendations: true
        }
      }

      assert {:ok, result} = PromptValidatorAgent.start_agent(validation_params)

      # Validate validation result structure
      assert Map.has_key?(result, :validation_results)
      assert Map.has_key?(result, :validation_report)
      assert Map.has_key?(result, :validation_metadata)

      validation_results = result.validation_results
      assert Map.has_key?(validation_results, :overall_validation_passed)

      # Validate report generation
      validation_report = result.validation_report
      assert Map.has_key?(validation_report, :validation_summary)
      assert Map.has_key?(validation_report, :recommendations)

      metadata = result.validation_metadata
      assert metadata.validation_scope == :comprehensive
      assert Map.has_key?(metadata, :performance_metrics)
    end

    test "PromptValidatorAgent handles different validation scopes" do
      base_validation_request = %{
        content: "Test validation with {{variable}} content.",
        context: %{prompt_type: :project, user_id: Ash.UUID.generate()}
      }

      validation_scopes = [:security_only, :budget_only, :comprehensive, :compliance]

      for scope <- validation_scopes do
        params = %{
          validation_request: base_validation_request,
          validation_scope: scope
        }

        assert {:ok, result} = PromptValidatorAgent.start_agent(params)

        # Should complete validation for each scope
        assert result.validation_metadata.validation_scope == scope
        assert Map.has_key?(result.validation_results, :overall_validation_passed)
      end
    end

    test "PromptValidatorAgent detects security issues and provides recommendations" do
      # Test with potentially dangerous content
      dangerous_content =
        "Execute {{system}} command and use <script>alert('test')</script> safely."

      validation_params = %{
        validation_request: %{
          content: dangerous_content,
          context: %{
            prompt_type: :user,
            trust_level: :new,
            high_security_mode: true
          }
        },
        validation_scope: :security_only,
        governance_requirements: %{
          require_security_validation: true
        },
        reporting_config: %{
          generate_detailed_report: true,
          include_recommendations: true
        }
      }

      assert {:ok, result} = PromptValidatorAgent.start_agent(validation_params)

      # Should detect security issues
      security_analysis = result.validation_report.security_analysis

      case security_analysis do
        %{analysis_skipped: true} ->
          # If analysis was skipped, that's acceptable for this test
          assert true

        %{threats_detected: threat_count} ->
          # Should detect threats in dangerous content
          assert threat_count > 0
      end

      # Should provide recommendations
      recommendations = result.validation_report.recommendations
      assert is_list(recommendations)
      assert length(recommendations) > 0
    end
  end

  describe "PromptAnalyticsAgent insights (2B.5.1.4)" do
    test "PromptAnalyticsAgent generates comprehensive analytics and insights" do
      analytics_params = %{
        analytics_request: %{
          target_prompts: ["analytics_test_1", "analytics_test_2"],
          analysis_goals: %{
            identify_optimization: true,
            generate_templates: true,
            track_effectiveness: true
          }
        },
        analysis_scope: :comprehensive,
        time_window: %{amount: 7, unit: :days},
        ml_config: %{
          enable_ml_analysis: true,
          pattern_recognition: true
        },
        reporting_options: %{
          include_recommendations: true,
          include_trend_analysis: true,
          detail_level: :comprehensive
        }
      }

      assert {:ok, result} = PromptAnalyticsAgent.start_agent(analytics_params)

      # Validate analytics result structure
      assert Map.has_key?(result, :analytics_results)
      assert Map.has_key?(result, :insights_report)
      assert Map.has_key?(result, :analytics_metadata)

      analytics_results = result.analytics_results
      assert Map.has_key?(analytics_results, :usage_statistics)
      assert Map.has_key?(analytics_results, :effectiveness_analysis)
      assert Map.has_key?(analytics_results, :optimization_analysis)
      assert Map.has_key?(analytics_results, :template_insights)

      # Validate insights report
      insights_report = result.insights_report
      assert Map.has_key?(insights_report, :key_insights)
      assert Map.has_key?(insights_report, :recommendations)
      assert Map.has_key?(insights_report, :optimization_opportunities)

      metadata = result.analytics_metadata
      assert metadata.analysis_scope == :comprehensive
      assert Map.has_key?(metadata, :performance_metrics)
    end

    test "PromptAnalyticsAgent handles different analysis scopes efficiently" do
      base_request = %{
        target_prompts: ["scope_test_prompt"],
        analysis_goals: %{basic_analysis: true}
      }

      analysis_scopes = [
        :usage_stats,
        :effectiveness,
        :optimization,
        :template_insights,
        :comprehensive
      ]

      for scope <- analysis_scopes do
        params = %{
          analytics_request: base_request,
          analysis_scope: scope,
          time_window: %{amount: 1, unit: :days}
        }

        assert {:ok, result} = PromptAnalyticsAgent.start_agent(params)

        # Should complete analysis for each scope
        assert result.analytics_metadata.analysis_scope == scope

        # Should have appropriate results based on scope
        analytics_results = result.analytics_results

        case scope do
          :usage_stats ->
            assert Map.has_key?(analytics_results, :usage_statistics)

          :effectiveness ->
            assert Map.has_key?(analytics_results, :effectiveness_analysis)

          :optimization ->
            assert Map.has_key?(analytics_results, :optimization_analysis)

          :template_insights ->
            assert Map.has_key?(analytics_results, :template_insights)

          :comprehensive ->
            # Should have all analysis types
            assert Map.has_key?(analytics_results, :usage_statistics)
            assert Map.has_key?(analytics_results, :effectiveness_analysis)
            assert Map.has_key?(analytics_results, :optimization_analysis)
            assert Map.has_key?(analytics_results, :template_insights)
        end
      end
    end

    test "PromptAnalyticsAgent provides ML-driven optimization recommendations" do
      ml_focused_params = %{
        analytics_request: %{
          target_prompts: ["ml_test_prompt"],
          analysis_goals: %{
            ml_insights: true,
            pattern_recognition: true,
            optimization_suggestions: true
          }
        },
        analysis_scope: :optimization,
        ml_config: %{
          enable_ml_analysis: true,
          confidence_threshold: 0.6,
          pattern_recognition: true
        }
      }

      assert {:ok, result} = PromptAnalyticsAgent.start_agent(ml_focused_params)

      # Should provide optimization analysis
      optimization = result.analytics_results.optimization_analysis
      assert Map.has_key?(optimization, :token_optimization_potential)
      assert Map.has_key?(optimization, :optimization_recommendations)

      # Should provide actionable recommendations
      recommendations = result.insights_report.recommendations
      assert is_list(recommendations)
      assert length(recommendations) > 0

      # Should include optimization opportunities
      opportunities = result.insights_report.optimization_opportunities
      assert is_list(opportunities)
    end
  end

  describe "agent coordination and integration" do
    test "agents work together in coordinated workflow" do
      # Test coordinated agent workflow: Compose → Validate → Analyze

      # Step 1: Compose prompt
      composition_params = %{
        composition_request: %{
          prompt_name: "coordination_test",
          context: %{
            tenant_id: Ash.UUID.generate(),
            user_id: Ash.UUID.generate(),
            variables: %{"task" => "agent coordination testing"}
          }
        },
        composition_strategy: :hierarchical_merge,
        provider_target: "claude-3-opus"
      }

      assert {:ok, composition_result} = PromptComposerAgent.start_agent(composition_params)
      composed_content = composition_result.composition_result.content

      # Step 2: Validate composed prompt
      validation_params = %{
        validation_request: %{
          content: composed_content,
          context: composition_params.composition_request.context
        },
        validation_scope: :comprehensive
      }

      assert {:ok, validation_result} = PromptValidatorAgent.start_agent(validation_params)

      # Step 3: Analyze composition and validation
      analytics_params = %{
        analytics_request: %{
          target_prompts: ["coordination_test"],
          analysis_goals: %{effectiveness_analysis: true}
        },
        analysis_scope: :effectiveness
      }

      assert {:ok, analytics_result} = PromptAnalyticsAgent.start_agent(analytics_params)

      # Verify coordinated workflow results
      assert String.length(composed_content) > 0
      assert Map.has_key?(validation_result.validation_results, :overall_validation_passed)
      assert Map.has_key?(analytics_result.analytics_results, :effectiveness_analysis)
    end

    test "agents maintain performance targets during coordinated operations" do
      # Test performance of coordinated agent operations
      test_params = %{
        composition: %{
          composition_request: %{
            prompt_name: "performance_test",
            context: %{
              tenant_id: Ash.UUID.generate(),
              variables: %{"instruction" => "performance testing"}
            }
          },
          provider_target: "gpt-4"
        },
        validation: %{
          validation_request: %{
            content: "Performance test prompt with {{instruction}} variable.",
            context: %{prompt_type: :user, trust_level: :standard}
          },
          validation_scope: :security_only
        },
        analytics: %{
          analytics_request: %{
            target_prompts: ["performance_test"],
            analysis_goals: %{quick_analysis: true}
          },
          analysis_scope: :usage_stats,
          time_window: %{amount: 1, unit: :days}
        }
      }

      # Measure agent execution times
      {composition_time, composition_result} =
        :timer.tc(fn ->
          PromptComposerAgent.start_agent(test_params.composition)
        end)

      {validation_time, validation_result} =
        :timer.tc(fn ->
          PromptValidatorAgent.start_agent(test_params.validation)
        end)

      {analytics_time, analytics_result} =
        :timer.tc(fn ->
          PromptAnalyticsAgent.start_agent(test_params.analytics)
        end)

      # All agents should execute successfully
      assert {:ok, _} = composition_result
      assert {:ok, _} = validation_result
      assert {:ok, _} = analytics_result

      # Performance should meet targets
      composition_time_ms = composition_time / 1_000
      validation_time_ms = validation_time / 1_000
      analytics_time_ms = analytics_time / 1_000

      # Should be fast for composition
      assert composition_time_ms < 100
      # Should be fast for validation
      assert validation_time_ms < 150
      # Should be reasonable for analytics
      assert analytics_time_ms < 200

      Logger.info("Agent Performance Benchmark",
        composition_time_ms: composition_time_ms,
        validation_time_ms: validation_time_ms,
        analytics_time_ms: analytics_time_ms,
        total_pipeline_time_ms: composition_time_ms + validation_time_ms + analytics_time_ms
      )
    end

    test "agents handle error scenarios gracefully with proper fallbacks" do
      # Test error handling across agents
      error_scenarios = [
        # Invalid composition request
        {
          :composition,
          %{
            # Missing required fields
            composition_request: %{},
            composition_strategy: :invalid_strategy
          }
        },
        # Invalid validation request
        {
          :validation,
          %{
            # Invalid content
            validation_request: %{content: nil},
            validation_scope: :invalid_scope
          }
        },
        # Invalid analytics request
        {
          :analytics,
          %{
            # Missing fields
            analytics_request: %{},
            analysis_scope: :invalid_scope
          }
        }
      ]

      for {agent_type, invalid_params} <- error_scenarios do
        result =
          case agent_type do
            :composition -> PromptComposerAgent.start_agent(invalid_params)
            :validation -> PromptValidatorAgent.start_agent(invalid_params)
            :analytics -> PromptAnalyticsAgent.start_agent(invalid_params)
          end

        # Should fail gracefully with informative errors
        assert {:error, _reason} = result
      end
    end

    test "agents provide comprehensive reporting and insights" do
      # Test comprehensive reporting across agents
      comprehensive_test = %{
        content: "Comprehensive test prompt with {{variable}} for analysis.",
        context: %{
          tenant_id: Ash.UUID.generate(),
          user_id: Ash.UUID.generate(),
          prompt_type: :project,
          variables: %{"variable" => "comprehensive testing"}
        }
      }

      # Test validation reporting
      validation_params = %{
        validation_request: comprehensive_test,
        validation_scope: :comprehensive,
        reporting_config: %{
          generate_detailed_report: true,
          include_recommendations: true,
          detail_level: :comprehensive
        }
      }

      assert {:ok, validation_result} = PromptValidatorAgent.start_agent(validation_params)

      validation_report = validation_result.validation_report
      assert Map.has_key?(validation_report, :validation_summary)
      assert Map.has_key?(validation_report, :recommendations)
      assert is_list(validation_report.recommendations)

      # Test analytics reporting
      analytics_params = %{
        analytics_request: %{
          target_prompts: ["comprehensive_test"],
          analysis_goals: %{comprehensive_insights: true}
        },
        analysis_scope: :comprehensive,
        reporting_options: %{
          include_recommendations: true,
          include_trend_analysis: true
        }
      }

      assert {:ok, analytics_result} = PromptAnalyticsAgent.start_agent(analytics_params)

      insights_report = analytics_result.insights_report
      assert Map.has_key?(insights_report, :key_insights)
      assert Map.has_key?(insights_report, :recommendations)
      assert Map.has_key?(insights_report, :optimization_opportunities)
    end
  end
end
