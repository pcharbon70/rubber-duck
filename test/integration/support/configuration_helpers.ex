defmodule RubberDuck.IntegrationHelpers.ConfigurationHelpers do
  @moduledoc """
  Helper functions for testing three-tier configuration system integration.
  
  Provides utilities for:
  - Creating realistic configuration scenarios across system/user/project tiers
  - Testing configuration resolution and inheritance behavior
  - Validating configuration performance under load
  - Testing configuration change propagation in integrated scenarios
  """
  
  @doc """
  Create comprehensive three-tier configuration scenario.
  """
  def create_three_tier_configuration_scenario(scenario_type \\ :balanced) do
    case scenario_type do
      :cost_focused ->
        create_cost_focused_configuration()
      
      :quality_focused ->
        create_quality_focused_configuration()
      
      :constitutional_ai_focused ->
        create_constitutional_ai_configuration()
      
      :performance_focused ->
        create_performance_focused_configuration()
      
      _ ->
        create_balanced_configuration()
    end
  end
  
  @doc """
  Test configuration resolution across all domains.
  """
  def test_configuration_resolution(user_id, project_id, domain) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case domain do
      :verdict ->
        RubberDuck.Verdict.Configuration.VerdictConfigurationResolver.resolve_configuration(user_id, project_id)
      
      :skills_actions ->
        RubberDuck.SkillsActions.Adapters.ConfigurationAdapter.resolve_skills_actions_configuration(user_id, project_id)
      
      :universal_providers ->
        RubberDuck.LlmProviders.UniversalProviderService.resolve_provider_config(domain, user_id, project_id)
      
      _ ->
        {:error, "Unknown domain: #{domain}"}
    end
    
    resolution_time = System.monotonic_time(:millisecond) - start_time
    
    case result do
      {:ok, config} ->
        {:ok, %{
          config: config,
          resolution_time_ms: resolution_time,
          domain: domain,
          user_id: user_id,
          project_id: project_id
        }}
      
      error ->
        {:error, error, resolution_time}
    end
  end
  
  @doc """
  Validate configuration inheritance working correctly.
  """
  def assert_configuration_inheritance_correct(system_config, user_config, project_config, resolved_config) do
    # Test that project overrides user, user overrides system
    
    # Check provider preferences inheritance
    if Map.has_key?(project_config, :preferred_providers) do
      assert resolved_config.preferred_providers == project_config.preferred_providers,
             "Project provider preferences not applied"
    else
      if Map.has_key?(user_config, :preferred_providers) do
        assert resolved_config.preferred_providers == user_config.preferred_providers,
               "User provider preferences not applied"
      end
    end
    
    # Check quality threshold inheritance
    if Map.has_key?(project_config, :quality_threshold) do
      assert resolved_config.quality_threshold == project_config.quality_threshold,
             "Project quality threshold not applied"
    else
      if Map.has_key?(user_config, :quality_threshold) do
        assert resolved_config.quality_threshold == user_config.quality_threshold,
               "User quality threshold not applied"
      end
    end
  end
  
  @doc """
  Create configuration change scenario for real-time testing.
  """
  def create_configuration_change_scenario do
    %{
      initial_config: %{
        preferred_providers: ["openai"],
        quality_threshold: 0.8,
        constitutional_ai_enabled: false
      },
      configuration_changes: [
        %{
          delay_ms: 1000,
          change: %{preferred_providers: ["anthropic"]},
          level: :user
        },
        %{
          delay_ms: 2000,
          change: %{quality_threshold: 0.9},
          level: :project
        },
        %{
          delay_ms: 3000,
          change: %{constitutional_ai_enabled: true},
          level: :user
        }
      ],
      expected_final_config: %{
        preferred_providers: ["anthropic"],
        quality_threshold: 0.9,
        constitutional_ai_enabled: true
      }
    }
  end
  
  @doc """
  Execute configuration change scenario with timing validation.
  """
  def execute_configuration_change_scenario(scenario, user_id, project_id) do
    # Apply initial configuration
    apply_configuration_changes(scenario.initial_config, user_id, project_id, :system)
    
    # Start background task to apply changes
    change_task = Task.async(fn ->
      apply_scheduled_configuration_changes(scenario.configuration_changes, user_id, project_id)
    end)
    
    # Execute evaluations during configuration changes
    evaluation_results = []
    
    # Monitor configuration during changes
    monitoring_task = Task.async(fn ->
      monitor_configuration_changes(user_id, project_id, 5000)  # Monitor for 5 seconds
    end)
    
    # Wait for completion
    Task.await(change_task)
    monitoring_data = Task.await(monitoring_task)
    
    # Validate final configuration
    {:ok, final_config} = RubberDuck.Verdict.Configuration.VerdictConfigurationResolver.resolve_configuration(user_id, project_id)
    
    %{
      final_config: final_config,
      monitoring_data: monitoring_data,
      evaluation_results: evaluation_results,
      change_scenario: scenario
    }
  end
  
  # Private implementation
  
  defp create_cost_focused_configuration do
    %{
      system: %{
        default_provider: "openai",
        cost_optimization_enabled: true,
        quality_threshold: 0.7
      },
      user: %{
        cost_preference: 0.9,  # High cost focus
        preferred_providers: ["openai"],
        budget_limit: 50.0
      },
      project: %{
        cost_control: :strict,
        budget_allocation: :conservative
      }
    }
  end
  
  defp create_quality_focused_configuration do
    %{
      system: %{
        default_provider: "anthropic",
        quality_threshold: 0.9
      },
      user: %{
        quality_preference: 0.9,  # High quality focus
        preferred_providers: ["anthropic"],
        constitutional_ai_preference: true
      },
      project: %{
        quality_standards: :high,
        constitutional_ai_required: true
      }
    }
  end
  
  defp create_constitutional_ai_configuration do
    %{
      system: %{
        constitutional_ai_enabled: true,
        bias_mitigation_enabled: true
      },
      user: %{
        constitutional_ai_preference: true,
        safety_priority: :high
      },
      project: %{
        constitutional_ai_required: true,
        safety_compliance: :strict
      }
    }
  end
  
  defp create_performance_focused_configuration do
    %{
      system: %{
        performance_optimization: true,
        cache_ttl: 3600
      },
      user: %{
        speed_preference: :high,
        caching_enabled: true
      },
      project: %{
        performance_targets: %{
          max_evaluation_time: 5000,
          max_configuration_resolution: 10
        }
      }
    }
  end
  
  defp create_balanced_configuration do
    %{
      system: %{
        default_provider: "openai",
        quality_threshold: 0.8,
        cost_optimization_enabled: true
      },
      user: %{
        cost_quality_balance: 0.5,
        preferred_providers: ["openai", "anthropic"]
      },
      project: %{
        coordination_strategy: :balanced
      }
    }
  end
  
  defp apply_configuration_changes(config, user_id, project_id, level) do
    # Apply configuration changes at specified level
    # Would integrate with actual preference system
    Logger.debug("Applying #{level} configuration for user #{user_id}, project #{project_id}")
    Process.put({:applied_config, level, user_id, project_id}, {config, DateTime.utc_now()})
  end
  
  defp apply_scheduled_configuration_changes(changes, user_id, project_id) do
    Enum.each(changes, fn change ->
      Process.sleep(change.delay_ms)
      apply_configuration_changes(change.change, user_id, project_id, change.level)
    end)
  end
  
  defp monitor_configuration_changes(user_id, project_id, duration_ms) do
    start_time = System.monotonic_time(:millisecond)
    monitoring_data = []
    
    monitoring_data = Stream.iterate(0, &(&1 + 100))
    |> Stream.take_while(fn elapsed ->
      elapsed < duration_ms
    end)
    |> Enum.reduce(monitoring_data, fn elapsed, acc ->
      Process.sleep(100)
      
      # Capture configuration state
      config_snapshot = capture_configuration_snapshot(user_id, project_id)
      
      [%{
        timestamp: DateTime.utc_now(),
        elapsed_ms: elapsed,
        config_snapshot: config_snapshot
      } | acc]
    end)
    
    Enum.reverse(monitoring_data)
  end
  
  defp capture_configuration_snapshot(user_id, project_id) do
    case RubberDuck.Verdict.Configuration.VerdictConfigurationResolver.resolve_configuration(user_id, project_id) do
      {:ok, config} ->
        %{
          preferred_providers: Map.get(config, :preferred_providers, []),
          quality_threshold: Map.get(config, :quality_threshold, 0.8),
          constitutional_ai_enabled: Map.get(config, :constitutional_ai_enabled, false),
          resolution_successful: true
        }
      
      {:error, reason} ->
        %{
          resolution_successful: false,
          error: reason
        }
    end
  end
end