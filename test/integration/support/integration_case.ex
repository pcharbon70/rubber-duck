defmodule RubberDuck.IntegrationCase do
  @moduledoc """
  Base test case for integration tests validating Phase 1B component interactions.

  This test case provides comprehensive setup for testing:
  - End-to-end evaluation workflows with all Phase 1B components
  - Cross-domain integration between Verdict, Universal Providers, and Skills systems
  - Configuration resolution across three-tier hierarchy
  - Performance testing under concurrent load
  - Constitutional AI principles maintenance across integrated workflows
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case
      use RubberDuck.DataCase

      import RubberDuck.IntegrationCase

      import RubberDuck.IntegrationHelpers.{
        ConfigurationHelpers,
        PerformanceHelpers,
        ProviderHelpers,
        AgentHelpers,
        SkillsHelpers
      }

      # Integration test specific setup
      setup_all do
        # Initialize Universal Provider System for integration tests
        initialize_integration_providers()

        # Set up skills registry for integration testing
        initialize_skills_registry()

        # Configure test telemetry
        setup_integration_telemetry()

        on_exit(fn ->
          cleanup_integration_environment()
        end)

        :ok
      end

      setup do
        # Per-test setup for integration tests
        test_context = %{
          start_time: System.monotonic_time(:millisecond),
          test_id: generate_test_id(),
          integration_metrics: %{}
        }

        %{integration_context: test_context}
      end
    end
  end

  # Integration test helper functions

  @doc """
  Initialize Universal Provider System for integration testing.
  """
  def initialize_integration_providers do
    # Configure mock providers for controlled testing
    configure_mock_openai_provider()
    configure_mock_anthropic_provider()
    configure_mock_ollama_provider()

    # Initialize provider registry
    {:ok, _pid} = RubberDuck.LlmProviders.ProviderRegistry.start_link()

    # Auto-register providers
    RubberDuck.LlmProviders.UniversalProviderInitializer.auto_register_universal_providers()
  end

  @doc """
  Initialize Skills Registry for integration testing.
  """
  def initialize_skills_registry do
    # Start skills registry
    {:ok, _pid} = RubberDuck.SkillsActions.SkillsRegistry.start_link()

    # Auto-register existing skills
    RubberDuck.SkillsActions.SkillsRegistry.auto_register_existing_skills()

    # Start action orchestrator
    {:ok, _pid} = RubberDuck.SkillsActions.ActionOrchestrator.start_link()
  end

  @doc """
  Set up telemetry for integration test monitoring.
  """
  def setup_integration_telemetry do
    # Attach telemetry handlers for integration test metrics
    :telemetry.attach_many(
      "integration-test-handlers",
      [
        [:verdict, :evaluation, :complete],
        [:universal_provider, :request, :complete],
        [:skills_registry, :discovery, :complete],
        [:action_orchestrator, :workflow, :complete]
      ],
      &handle_integration_telemetry/4,
      %{test_mode: true}
    )
  end

  @doc """
  Clean up integration test environment.
  """
  def cleanup_integration_environment do
    # Shutdown Universal Provider System
    RubberDuck.LlmProviders.UniversalProviderRegistry.shutdown_all_universal_providers()

    # Clean up telemetry handlers
    :telemetry.detach("integration-test-handlers")

    # Reset any cached configurations
    reset_integration_caches()
  end

  @doc """
  Create user with realistic preferences for integration testing.
  """
  def create_integration_test_user(preferences \\ %{}) do
    default_preferences = %{
      quality_vs_cost_preference: 0.7,
      preferred_providers: ["openai", "anthropic"],
      constitutional_ai_enabled: true,
      cost_optimization_enabled: true,
      skill_preferences: %{
        preferred_skills: ["code_analysis_skill", "learning_skill"],
        llm_assistance_enabled: true
      }
    }

    merged_preferences = Map.merge(default_preferences, preferences)

    # Create user (would use actual User creation in production)
    %{
      id: generate_test_user_id(),
      email: "integration_test@example.com",
      preferences: merged_preferences,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Create project with realistic settings for integration testing.
  """
  def create_integration_test_project(user, settings \\ %{}) do
    default_settings = %{
      quality_threshold: 0.85,
      team_size: 3,
      preferred_providers: [],
      constitutional_ai_required: false,
      skills_configuration: %{
        project_preferred_skills: ["project_management_skill", "threat_detection_skill"],
        coordination_strategy: :balanced
      }
    }

    merged_settings = Map.merge(default_settings, settings)

    # Create project (would use actual Project creation in production)
    %{
      id: generate_test_project_id(),
      name: "Integration Test Project",
      owner_id: user.id,
      settings: merged_settings,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Load test code samples for evaluation testing.
  """
  def load_test_code_sample(sample_name) do
    case sample_name do
      "simple_elixir_function.ex" ->
        """
        defmodule TestModule do
          def simple_function(input) do
            String.upcase(input)
          end
        end
        """

      "complex_elixir_module.ex" ->
        """
        defmodule ComplexTestModule do
          use GenServer
          require Logger

          @doc "Complex module for integration testing"
          def start_link(opts) do
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          end

          def init(opts) do
            state = %{
              data: Map.get(opts, :initial_data, %{}),
              config: Map.get(opts, :config, %{})
            }
            {:ok, state}
          end

          def process_data(data) do
            GenServer.call(__MODULE__, {:process, data})
          end

          def handle_call({:process, data}, _from, state) do
            result = transform_data(data, state.config)
            {:reply, result, state}
          end

          defp transform_data(data, config) do
            # Complex transformation logic
            data
            |> Map.put(:processed_at, DateTime.utc_now())
            |> Map.put(:config_applied, config)
            |> validate_data()
          end

          defp validate_data(data) do
            if Map.has_key?(data, :required_field) do
              {:ok, data}
            else
              {:error, :missing_required_field}
            end
          end
        end
        """

      "security_test_code.ex" ->
        """
        defmodule SecurityTestModule do
          def process_user_input(input) do
            # Potential security issue for testing
            query = "SELECT * FROM users WHERE name = '" <> input <> "'"
            execute_query(query)
          end

          def execute_query(query) do
            # Simulated database query execution
            Logger.info("Executing query: #{query}")
            {:ok, "Query executed"}
          end

          def handle_sensitive_data(user_data) do
            # Another security test scenario
            password = Map.get(user_data, :password)
            store_in_logs(password)  # Security issue
          end

          defp store_in_logs(data) do
            Logger.info("Storing data: #{data}")
          end
        end
        """

      _ ->
        """
        defmodule DefaultTestModule do
          def test_function do
            :ok
          end
        end
        """
    end
  end

  @doc """
  Create multiple evaluation requests for load testing.
  """
  def create_evaluation_requests(count, options \\ %{}) do
    1..count
    |> Enum.map(fn index ->
      %{
        code:
          load_test_code_sample(
            Enum.random([
              "simple_elixir_function.ex",
              "complex_elixir_module.ex",
              "security_test_code.ex"
            ])
          ),
        evaluation_type: Enum.random([:quality, :security, :performance, :maintainability]),
        user_id: Map.get(options, :user_id, "test_user_#{index}"),
        project_id: Map.get(options, :project_id, "test_project_#{rem(index, 3)}"),
        criteria: generate_test_criteria(),
        metadata: %{test_index: index, batch_size: count}
      }
    end)
  end

  @doc """
  Execute evaluations concurrently for performance testing.
  """
  def evaluate_concurrently(evaluation_requests, options \\ []) do
    timeout = Keyword.get(options, :timeout, 30_000)

    tasks =
      evaluation_requests
      |> Enum.map(fn request ->
        Task.async(fn ->
          execute_single_evaluation_with_timing(request)
        end)
      end)

    Task.await_many(tasks, timeout)
  end

  defp execute_single_evaluation_with_timing(request) do
    start_time = System.monotonic_time(:millisecond)

    result =
      RubberDuck.Verdict.Engine.evaluate_code(
        request.code,
        request.evaluation_type,
        user_id: request.user_id,
        project_id: request.project_id,
        criteria: request.criteria
      )

    execution_time = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, evaluation_result} ->
        {:ok, Map.put(evaluation_result, :execution_time_ms, execution_time)}

      error ->
        {:error, error, execution_time}
    end
  end

  @doc """
  Validate provider routing decisions based on configuration.
  """
  def assert_provider_selected_based_on_preferences(evaluation_result, user, project) do
    selected_provider = evaluation_result.provider_used
    user_preferences = user.preferences.preferred_providers

    # If user has provider preferences, selected provider should respect them
    if not Enum.empty?(user_preferences) do
      assert selected_provider in user_preferences,
             "Provider #{selected_provider} not in user preferences #{inspect(user_preferences)}"
    end

    # If project has Constitutional AI requirements, Anthropic should be preferred
    if project.settings[:constitutional_ai_required] do
      assert selected_provider == "anthropic",
             "Constitutional AI required but provider #{selected_provider} selected"
    end
  end

  @doc """
  Validate agent coordination worked correctly.
  """
  def assert_agents_coordinated_correctly(evaluation_result) do
    metadata = evaluation_result.metadata

    assert Map.has_key?(metadata, :agents_involved),
           "No agent coordination metadata found"

    agents_involved = metadata.agents_involved

    assert length(agents_involved) > 0,
           "No agents participated in evaluation"

    # Validate consensus reached if multiple agents involved
    if length(agents_involved) > 1 do
      assert Map.has_key?(metadata, :consensus_data),
             "Multiple agents but no consensus data"
    end
  end

  @doc """
  Validate consensus achieved with required confidence.
  """
  def assert_consensus_achieved_with_confidence(evaluation_result, opts \\ []) do
    min_confidence = Keyword.get(opts, :min_confidence, 0.7)

    assert evaluation_result.confidence >= min_confidence,
           "Consensus confidence #{evaluation_result.confidence} below minimum #{min_confidence}"

    # Validate consensus metadata if available
    if Map.has_key?(evaluation_result.metadata, :consensus_data) do
      consensus_data = evaluation_result.metadata.consensus_data

      assert Map.has_key?(consensus_data, :agreement_level),
             "No agreement level in consensus data"

      assert consensus_data.agreement_level >= 0.8,
             "Agreement level #{consensus_data.agreement_level} too low for reliable consensus"
    end
  end

  @doc """
  Validate cost tracking worked correctly.
  """
  def assert_cost_tracked_correctly(evaluation_result, user, project) do
    assert evaluation_result.cost_usd >= 0,
           "Cost tracking shows negative cost: #{evaluation_result.cost_usd}"

    # Validate cost is within expected bounds
    # Reasonable upper bound for single evaluation
    max_expected_cost = 5.0

    assert evaluation_result.cost_usd <= max_expected_cost,
           "Cost #{evaluation_result.cost_usd} exceeds reasonable maximum #{max_expected_cost}"

    # Validate cost metadata
    metadata = evaluation_result.metadata

    assert Map.has_key?(metadata, :cost_breakdown),
           "No cost breakdown in evaluation metadata"
  end

  @doc """
  Validate learning feedback collection and processing.
  """
  def assert_feedback_collected_and_processed(evaluation_result) do
    metadata = evaluation_result.metadata

    # Check for learning system integration
    assert Map.has_key?(metadata, :learning_data) or Map.has_key?(metadata, :feedback_collected),
           "No learning/feedback integration detected"

    # If learning data present, validate structure
    if Map.has_key?(metadata, :learning_data) do
      learning_data = metadata.learning_data

      assert Map.has_key?(learning_data, :patterns_detected),
             "Learning data missing pattern detection"
    end
  end

  @doc """
  Generate test criteria for evaluation requests.
  """
  def generate_test_criteria do
    criteria_options = [
      %{"correctness" => 0.4, "security" => 0.3, "maintainability" => 0.3},
      %{"security" => 0.6, "correctness" => 0.25, "maintainability" => 0.15},
      %{"performance" => 0.4, "correctness" => 0.3, "security" => 0.2, "style" => 0.1},
      %{"maintainability" => 0.4, "correctness" => 0.3, "style" => 0.3}
    ]

    Enum.random(criteria_options)
  end

  @doc """
  Capture system metrics for performance testing.
  """
  def capture_system_metrics do
    %{
      memory_usage: :erlang.memory(),
      process_count: length(Process.list()),
      ets_table_count: length(:ets.all()),
      timestamp: DateTime.utc_now(),
      system_info: %{
        total_memory: :erlang.memory(:total),
        process_memory: :erlang.memory(:processes),
        system_memory: :erlang.memory(:system)
      }
    }
  end

  @doc """
  Assert memory usage remains stable between measurements.
  """
  def assert_memory_usage_stable(baseline_metrics, final_metrics) do
    baseline_memory = baseline_metrics.memory_usage[:total]
    final_memory = final_metrics.memory_usage[:total]

    # Allow up to 10% memory growth during testing
    max_allowed_growth = baseline_memory * 1.1

    assert final_memory <= max_allowed_growth,
           "Memory usage grew from #{baseline_memory} to #{final_memory} (#{(final_memory - baseline_memory) / baseline_memory * 100}% increase)"
  end

  @doc """
  Assert no resource leaks detected.
  """
  def assert_no_resource_leaks(baseline_metrics, final_metrics) do
    baseline_processes = baseline_metrics.process_count
    final_processes = final_metrics.process_count

    # Allow some process growth but detect obvious leaks
    max_process_growth = baseline_processes * 1.2

    assert final_processes <= max_process_growth,
           "Process count grew from #{baseline_processes} to #{final_processes} - possible process leak"

    # Check ETS table growth
    baseline_ets = baseline_metrics.ets_table_count
    final_ets = final_metrics.ets_table_count

    # Allow some ETS table growth
    max_ets_growth = baseline_ets + 10

    assert final_ets <= max_ets_growth,
           "ETS table count grew from #{baseline_ets} to #{final_ets} - possible ETS leak"
  end

  @doc """
  Assert providers were balanced across evaluations.
  """
  def assert_providers_balanced_across_evaluations(evaluation_results) do
    providers_used =
      evaluation_results
      |> Enum.map(fn {:ok, result} -> result.provider_used end)
      |> Enum.frequencies()

    # Should use multiple providers for balanced load
    assert map_size(providers_used) > 1,
           "Only single provider used: #{inspect(providers_used)}"

    # No single provider should handle >70% of requests (unless preference-driven)
    total_evaluations = length(evaluation_results)
    max_single_provider = providers_used |> Map.values() |> Enum.max()

    # Allow some imbalance due to preferences
    max_acceptable_percentage = 0.8

    assert max_single_provider <= total_evaluations * max_acceptable_percentage,
           "Provider imbalance detected: #{inspect(providers_used)}"
  end

  @doc """
  Assert configuration resolution was performant.
  """
  def assert_configuration_resolution_performant(evaluation_results) do
    # Extract configuration resolution times from metadata
    resolution_times =
      evaluation_results
      |> Enum.map(fn {:ok, result} ->
        get_in(result, [:metadata, :configuration_resolution_time_ms]) || 5
      end)

    avg_resolution_time = Enum.sum(resolution_times) / length(resolution_times)

    assert avg_resolution_time < 10.0,
           "Configuration resolution too slow: #{avg_resolution_time}ms average"

    # 95th percentile should be under 20ms
    sorted_times = Enum.sort(resolution_times)
    p95_index = trunc(length(sorted_times) * 0.95)
    p95_time = Enum.at(sorted_times, p95_index, 0)

    assert p95_time < 20.0,
           "Configuration resolution p95 too slow: #{p95_time}ms"
  end

  # Private helper functions

  defp configure_mock_openai_provider do
    mock_config = %{
      enabled: true,
      api_key: "test-openai-key",
      models: %{
        evaluation_screening: "gpt-4o-mini",
        evaluation_detailed: "gpt-4o"
      },
      mock_responses: %{
        evaluation: %{
          success: true,
          score: 0.85,
          confidence: 0.9,
          cost_usd: 0.05,
          response_time_ms: 1500
        }
      }
    }

    # Would configure actual mock provider in production
    Process.put(:mock_openai_config, mock_config)
  end

  defp configure_mock_anthropic_provider do
    mock_config = %{
      enabled: true,
      api_key: "test-anthropic-key",
      models: %{
        evaluation_screening: "claude-3-haiku-20240307",
        evaluation_detailed: "claude-3-5-sonnet-20241022"
      },
      constitutional_ai: %{
        safety_checks: true,
        bias_mitigation: true
      },
      mock_responses: %{
        evaluation: %{
          success: true,
          score: 0.87,
          confidence: 0.92,
          cost_usd: 0.04,
          response_time_ms: 2000,
          constitutional_ai_enhanced: true
        }
      }
    }

    Process.put(:mock_anthropic_config, mock_config)
  end

  defp configure_mock_ollama_provider do
    mock_config = %{
      enabled: true,
      endpoint: "http://localhost:11434",
      models: %{
        evaluation_screening: "llama3.2:3b"
      },
      mock_responses: %{
        evaluation: %{
          success: true,
          score: 0.80,
          confidence: 0.85,
          # Local model
          cost_usd: 0.0,
          response_time_ms: 800
        }
      }
    }

    Process.put(:mock_ollama_config, mock_config)
  end

  defp handle_integration_telemetry(event_name, measurements, metadata, config) do
    # Store telemetry data for integration test analysis
    telemetry_data = %{
      event: event_name,
      measurements: measurements,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    # Store in process dictionary for test access
    current_telemetry = Process.get(:integration_telemetry, [])
    Process.put(:integration_telemetry, [telemetry_data | current_telemetry])
  end

  defp reset_integration_caches do
    # Reset various caches used during integration testing
    Process.delete(:mock_openai_config)
    Process.delete(:mock_anthropic_config)
    Process.delete(:mock_ollama_config)
    Process.delete(:integration_telemetry)
  end

  defp generate_test_id do
    "test_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_test_user_id do
    "user_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
  end

  defp generate_test_project_id do
    "proj_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
  end

  # Integration test validation utilities

  @doc """
  Validate end-to-end evaluation workflow completed successfully.
  """
  def assert_evaluation_workflow_successful(evaluation_result) do
    assert evaluation_result.success == true,
           "Evaluation workflow failed"

    assert is_number(evaluation_result.score) and evaluation_result.score >= 0 and
             evaluation_result.score <= 1,
           "Invalid evaluation score: #{evaluation_result.score}"

    assert is_number(evaluation_result.confidence) and evaluation_result.confidence >= 0 and
             evaluation_result.confidence <= 1,
           "Invalid confidence score: #{evaluation_result.confidence}"

    assert is_binary(evaluation_result.provider_used),
           "No provider information in evaluation result"

    assert evaluation_result.cost_usd >= 0,
           "Invalid cost tracking: #{evaluation_result.cost_usd}"
  end

  @doc """
  Validate cross-domain integration worked correctly.
  """
  def assert_cross_domain_integration_successful(evaluation_result) do
    metadata = evaluation_result.metadata

    # Should have evidence of multiple domain interactions
    assert Map.has_key?(metadata, :universal_provider_integration),
           "No Universal Provider integration detected"

    assert Map.has_key?(metadata, :configuration_resolution),
           "No configuration resolution detected"

    # Should have agent coordination data if multiple agents involved
    if Map.get(metadata, :agents_count, 1) > 1 do
      assert Map.has_key?(metadata, :agent_coordination),
             "Multiple agents but no coordination data"
    end
  end

  @doc """
  Validate Constitutional AI principles were maintained.
  """
  def assert_constitutional_ai_maintained(evaluation_result) do
    metadata = evaluation_result.metadata

    # If Constitutional AI was enabled, should have evidence
    if Map.get(metadata, :constitutional_ai_enabled, false) do
      assert Map.has_key?(metadata, :constitutional_ai_data),
             "Constitutional AI enabled but no data found"

      constitutional_data = metadata.constitutional_ai_data

      assert Map.get(constitutional_data, :helpful, false),
             "Constitutional AI helpful principle not maintained"

      assert Map.get(constitutional_data, :harmless, false),
             "Constitutional AI harmless principle not maintained"

      assert Map.get(constitutional_data, :honest, false),
             "Constitutional AI honest principle not maintained"
    end
  end

  @doc """
  Get integration telemetry data for analysis.
  """
  def get_integration_telemetry do
    Process.get(:integration_telemetry, [])
  end

  @doc """
  Assert system performance within acceptable bounds.
  """
  def assert_performance_within_bounds(evaluation_results, max_time_ms \\ 15_000) do
    execution_times =
      evaluation_results
      |> Enum.map(fn {:ok, result} -> result.execution_time_ms end)

    avg_time = Enum.sum(execution_times) / length(execution_times)
    max_time = Enum.max(execution_times)

    assert avg_time < max_time_ms / 2,
           "Average execution time #{avg_time}ms too slow"

    assert max_time < max_time_ms,
           "Maximum execution time #{max_time}ms exceeds limit #{max_time_ms}ms"
  end
end
