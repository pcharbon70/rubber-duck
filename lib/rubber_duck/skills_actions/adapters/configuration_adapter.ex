defmodule RubberDuck.SkillsActions.Adapters.ConfigurationAdapter do
  @moduledoc """
  Configuration adapter for Skills & Actions system integration with three-tier preferences.
  
  This adapter enables sophisticated preference-driven behavior for skills and actions
  including:
  - User-specific skill preferences and action behavior customization  
  - Project-level skills/actions configuration and workflow templates
  - System-wide skills registry settings and performance optimization
  - Integration with existing three-tier configuration resolution
  - Constitutional AI configuration for safety-critical skills
  """
  
  require Logger
  
  alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver
  alias RubberDuck.Preferences.PreferenceResolver
  
  @configuration_domains [:skills, :actions, :workflows, :orchestration]
  @skill_preference_keys [
    :preferred_skills,
    :skill_performance_tolerance,
    :skill_timeout_ms,
    :llm_assistance_enabled,
    :constitutional_ai_for_skills,
    :skill_caching_enabled
  ]
  @action_preference_keys [
    :preferred_actions,
    :action_coordination_strategy,
    :parallel_execution_limit,
    :workflow_timeout_ms,
    :error_recovery_strategy,
    :performance_monitoring_enabled
  ]
  
  @doc """
  Resolve skills & actions configuration for user and project context.
  """
  def resolve_skills_actions_configuration(user_id, project_id \\ nil) do
    Logger.debug("Resolving skills & actions configuration for user #{user_id}")
    
    with {:ok, system_config} <- resolve_system_skills_config(),
         {:ok, user_config} <- resolve_user_skills_config(user_id),
         {:ok, project_config} <- resolve_project_skills_config(project_id),
         {:ok, merged_config} <- merge_configuration_hierarchy(system_config, user_config, project_config) do
      
      {:ok, merged_config}
    else
      error ->
        Logger.error("Skills & actions configuration resolution failed: #{inspect(error)}")
        # Fallback to default configuration
        {:ok, get_default_skills_actions_configuration()}
    end
  end
  
  @doc """
  Get skill-specific preferences for execution optimization.
  """
  def get_skill_preferences(skill_module, user_id, project_id \\ nil) do
    case resolve_skills_actions_configuration(user_id, project_id) do
      {:ok, config} ->
        skill_name = extract_skill_name(skill_module)
        
        skill_preferences = %{
          llm_assistance_enabled: Map.get(config.skills, :llm_assistance_enabled, true),
          constitutional_ai_enabled: Map.get(config.skills, :constitutional_ai_for_skills, false),
          performance_tolerance: Map.get(config.skills, :skill_performance_tolerance, 0.8),
          timeout_ms: Map.get(config.skills, :skill_timeout_ms, 10_000),
          caching_enabled: Map.get(config.skills, :skill_caching_enabled, true),
          preferred_execution_mode: get_skill_execution_mode(skill_name, config)
        }
        
        {:ok, skill_preferences}
      
      error -> error
    end
  end
  
  @doc """
  Get action orchestration preferences for workflow coordination.
  """
  def get_orchestration_preferences(user_id, project_id \\ nil) do
    case resolve_skills_actions_configuration(user_id, project_id) do
      {:ok, config} ->
        orchestration_preferences = %{
          coordination_strategy: Map.get(config.actions, :action_coordination_strategy, :balanced),
          parallel_execution_limit: Map.get(config.actions, :parallel_execution_limit, 5),
          workflow_timeout_ms: Map.get(config.actions, :workflow_timeout_ms, 30_000),
          error_recovery_strategy: Map.get(config.actions, :error_recovery_strategy, :graceful_degradation),
          performance_monitoring: Map.get(config.actions, :performance_monitoring_enabled, true),
          llm_optimization_enabled: Map.get(config.orchestration, :llm_optimization_enabled, true)
        }
        
        {:ok, orchestration_preferences}
      
      error -> error
    end
  end
  
  @doc """
  Get workflow template preferences for specific use cases.
  """
  def get_workflow_template_preferences(workflow_type, user_id, project_id \\ nil) do
    case resolve_skills_actions_configuration(user_id, project_id) do
      {:ok, config} ->
        workflow_templates = Map.get(config.workflows, :templates, %{})
        
        template_preferences = case Map.get(workflow_templates, workflow_type) do
          nil -> get_default_workflow_template(workflow_type)
          template -> template
        end
        
        {:ok, Map.merge(template_preferences, %{
          llm_optimization: Map.get(config.workflows, :llm_optimization_enabled, true),
          constitutional_ai_compliance: Map.get(config.workflows, :constitutional_ai_compliance, false),
          performance_tracking: Map.get(config.workflows, :performance_tracking_enabled, true)
        })}
      
      error -> error
    end
  end
  
  @doc """
  Update skills & actions configuration preferences.
  """
  def update_skills_actions_preferences(user_id, project_id \\ nil, preferences_update) do
    Logger.info("Updating skills & actions preferences for user #{user_id}")
    
    # Update preferences through existing three-tier system
    case preferences_update do
      %{level: :user} = update ->
        update_user_skills_preferences(user_id, update.preferences)
      
      %{level: :project} = update when not is_nil(project_id) ->
        update_project_skills_preferences(project_id, update.preferences)
      
      %{level: :system} = update ->
        update_system_skills_preferences(update.preferences)
      
      _ ->
        {:error, "Invalid preferences update format"}
    end
  end
  
  @doc """
  Validate skills & actions configuration for consistency and compatibility.
  """
  def validate_skills_actions_configuration(config) do
    with :ok <- validate_skills_configuration(Map.get(config, :skills, %{})),
         :ok <- validate_actions_configuration(Map.get(config, :actions, %{})),
         :ok <- validate_workflows_configuration(Map.get(config, :workflows, %{})),
         :ok <- validate_orchestration_configuration(Map.get(config, :orchestration, %{})) do
      :ok
    else
      error -> error
    end
  end
  
  # Private implementation
  
  defp resolve_system_skills_config do
    # Resolve system-level skills & actions configuration
    {:ok, %{
      skills: %{
        registry_cache_ttl: 300_000,  # 5 minutes
        capability_matching_algorithm: :weighted_overlap,
        performance_monitoring_enabled: true,
        llm_assistance_enabled: true,
        constitutional_ai_for_skills: false
      },
      actions: %{
        action_coordination_strategy: :balanced,
        parallel_execution_limit: 10,
        workflow_timeout_ms: 60_000,
        error_recovery_strategy: :retry_with_fallback,
        performance_monitoring_enabled: true
      },
      workflows: %{
        llm_optimization_enabled: true,
        performance_tracking_enabled: true,
        constitutional_ai_compliance: false,
        default_execution_pattern: :sequential
      },
      orchestration: %{
        max_concurrent_workflows: 20,
        workflow_result_caching: true,
        dependency_resolution_strategy: :lazy,
        llm_optimization_enabled: true
      }
    }}
  end
  
  defp resolve_user_skills_config(user_id) do
    # Use existing preference resolution for user-level skills preferences
    case PreferenceResolver.get_preference("skills_actions", user_id) do
      {:ok, user_prefs} ->
        {:ok, %{
          skills: extract_user_skills_preferences(user_prefs),
          actions: extract_user_actions_preferences(user_prefs),
          workflows: extract_user_workflow_preferences(user_prefs),
          orchestration: extract_user_orchestration_preferences(user_prefs)
        }}
      
      {:error, :not_found} ->
        {:ok, get_default_user_skills_config()}
      
      error -> error
    end
  end
  
  defp resolve_project_skills_config(nil), do: {:ok, %{}}
  defp resolve_project_skills_config(project_id) do
    # Resolve project-level skills & actions configuration
    case PreferenceResolver.get_preference("skills_actions", nil, project_id) do
      {:ok, project_prefs} ->
        {:ok, %{
          skills: extract_project_skills_preferences(project_prefs),
          actions: extract_project_actions_preferences(project_prefs),
          workflows: extract_project_workflow_preferences(project_prefs),
          orchestration: extract_project_orchestration_preferences(project_prefs)
        }}
      
      {:error, :not_found} ->
        {:ok, %{}}
      
      error -> error
    end
  end
  
  defp merge_configuration_hierarchy(system_config, user_config, project_config) do
    # Merge configurations following three-tier hierarchy: System -> User -> Project
    merged_config = %{
      skills: merge_domain_config(:skills, system_config, user_config, project_config),
      actions: merge_domain_config(:actions, system_config, user_config, project_config),
      workflows: merge_domain_config(:workflows, system_config, user_config, project_config),
      orchestration: merge_domain_config(:orchestration, system_config, user_config, project_config)
    }
    
    case validate_skills_actions_configuration(merged_config) do
      :ok -> {:ok, merged_config}
      error -> error
    end
  end
  
  defp merge_domain_config(domain, system_config, user_config, project_config) do
    system_domain = Map.get(system_config, domain, %{})
    user_domain = Map.get(user_config, domain, %{})
    project_domain = Map.get(project_config, domain, %{})
    
    # Project overrides user, user overrides system
    system_domain
    |> Map.merge(user_domain)
    |> Map.merge(project_domain)
  end
  
  defp extract_skill_name(skill_module) do
    skill_module
    |> to_string()
    |> String.replace("Elixir.RubberDuck.Skills.", "")
    |> String.replace("Skill", "")
    |> Macro.underscore()
  end
  
  defp get_skill_execution_mode(skill_name, config) do
    skill_specific_config = Map.get(config.skills, :skill_specific, %{})
    
    case Map.get(skill_specific_config, skill_name) do
      nil -> :standard
      skill_config -> Map.get(skill_config, :execution_mode, :standard)
    end
  end
  
  defp get_default_skills_actions_configuration do
    %{
      skills: %{
        llm_assistance_enabled: true,
        constitutional_ai_for_skills: false,
        skill_performance_tolerance: 0.8,
        skill_timeout_ms: 10_000,
        skill_caching_enabled: true
      },
      actions: %{
        action_coordination_strategy: :balanced,
        parallel_execution_limit: 5,
        workflow_timeout_ms: 30_000,
        error_recovery_strategy: :graceful_degradation,
        performance_monitoring_enabled: true
      },
      workflows: %{
        llm_optimization_enabled: true,
        performance_tracking_enabled: true,
        constitutional_ai_compliance: false,
        default_execution_pattern: :sequential
      },
      orchestration: %{
        max_concurrent_workflows: 10,
        workflow_result_caching: true,
        dependency_resolution_strategy: :eager,
        llm_optimization_enabled: true
      }
    }
  end
  
  defp get_default_user_skills_config do
    %{
      skills: %{
        preferred_skills: [],
        skill_performance_tolerance: 0.8,
        llm_assistance_preference: :enabled
      },
      actions: %{
        preferred_coordination_strategy: :balanced,
        parallel_preference: :moderate
      },
      workflows: %{
        workflow_style_preference: :efficient,
        llm_optimization_preference: :enabled
      },
      orchestration: %{
        orchestration_style: :standard,
        performance_priority: :balanced
      }
    }
  end
  
  defp get_default_workflow_template(workflow_type) do
    case workflow_type do
      :code_evaluation ->
        %{
          skills: ["code_analysis_skill"],
          actions: ["analyze_entity"],
          execution_pattern: :sequential,
          constitutional_ai_required: true
        }
      
      :security_audit ->
        %{
          skills: ["threat_detection_skill", "policy_enforcement_skill"],
          actions: ["security_monitoring"],
          execution_pattern: :parallel,
          constitutional_ai_required: true
        }
      
      :project_coordination ->
        %{
          skills: ["project_management_skill", "user_management_skill"],
          actions: ["create_entity", "analyze_entity"],
          execution_pattern: :sequential,
          constitutional_ai_required: false
        }
      
      _ ->
        %{
          skills: [],
          actions: [],
          execution_pattern: :sequential,
          constitutional_ai_required: false
        }
    end
  end
  
  # Configuration extraction helpers
  
  defp extract_user_skills_preferences(user_prefs) do
    %{
      preferred_skills: Map.get(user_prefs, "preferred_skills", []),
      skill_performance_tolerance: Map.get(user_prefs, "skill_performance_tolerance", 0.8),
      skill_timeout_ms: Map.get(user_prefs, "skill_timeout_ms", 10_000),
      llm_assistance_enabled: Map.get(user_prefs, "llm_assistance_enabled", true),
      constitutional_ai_for_skills: Map.get(user_prefs, "constitutional_ai_for_skills", false)
    }
  end
  
  defp extract_user_actions_preferences(user_prefs) do
    %{
      preferred_actions: Map.get(user_prefs, "preferred_actions", []),
      action_coordination_strategy: Map.get(user_prefs, "action_coordination_strategy", :balanced),
      parallel_execution_limit: Map.get(user_prefs, "parallel_execution_limit", 5),
      workflow_timeout_ms: Map.get(user_prefs, "workflow_timeout_ms", 30_000)
    }
  end
  
  defp extract_user_workflow_preferences(user_prefs) do
    %{
      workflow_style_preference: Map.get(user_prefs, "workflow_style_preference", :efficient),
      llm_optimization_enabled: Map.get(user_prefs, "llm_optimization_enabled", true),
      performance_tracking_enabled: Map.get(user_prefs, "performance_tracking_enabled", true)
    }
  end
  
  defp extract_user_orchestration_preferences(user_prefs) do
    %{
      orchestration_style: Map.get(user_prefs, "orchestration_style", :standard),
      performance_priority: Map.get(user_prefs, "performance_priority", :balanced),
      max_concurrent_workflows: Map.get(user_prefs, "max_concurrent_workflows", 10)
    }
  end
  
  defp extract_project_skills_preferences(project_prefs) do
    %{
      project_preferred_skills: Map.get(project_prefs, "project_preferred_skills", []),
      project_skill_standards: Map.get(project_prefs, "project_skill_standards", %{}),
      constitutional_ai_required: Map.get(project_prefs, "constitutional_ai_required", false)
    }
  end
  
  defp extract_project_actions_preferences(project_prefs) do
    %{
      project_action_templates: Map.get(project_prefs, "project_action_templates", %{}),
      project_coordination_strategy: Map.get(project_prefs, "project_coordination_strategy", :balanced),
      project_workflow_patterns: Map.get(project_prefs, "project_workflow_patterns", [])
    }
  end
  
  defp extract_project_workflow_preferences(project_prefs) do
    %{
      project_workflow_templates: Map.get(project_prefs, "project_workflow_templates", %{}),
      constitutional_ai_compliance: Map.get(project_prefs, "constitutional_ai_compliance", false),
      project_performance_standards: Map.get(project_prefs, "project_performance_standards", %{})
    }
  end
  
  defp extract_project_orchestration_preferences(project_prefs) do
    %{
      project_orchestration_style: Map.get(project_prefs, "project_orchestration_style", :standard),
      team_coordination_patterns: Map.get(project_prefs, "team_coordination_patterns", []),
      resource_allocation_strategy: Map.get(project_prefs, "resource_allocation_strategy", :fair_share)
    }
  end
  
  # Configuration validation
  
  defp validate_skills_configuration(skills_config) do
    required_fields = [:skill_performance_tolerance, :skill_timeout_ms]
    missing_fields = Enum.filter(required_fields, &(!Map.has_key?(skills_config, &1)))
    
    case missing_fields do
      [] ->
        # Validate field values
        performance_tolerance = Map.get(skills_config, :skill_performance_tolerance, 0.8)
        timeout_ms = Map.get(skills_config, :skill_timeout_ms, 10_000)
        
        cond do
          performance_tolerance < 0 or performance_tolerance > 1 ->
            {:error, "Skill performance tolerance must be between 0 and 1"}
          
          timeout_ms < 1000 or timeout_ms > 300_000 ->
            {:error, "Skill timeout must be between 1 second and 5 minutes"}
          
          true -> :ok
        end
      
      fields ->
        {:error, "Missing required skills configuration fields: #{inspect(fields)}"}
    end
  end
  
  defp validate_actions_configuration(actions_config) do
    parallel_limit = Map.get(actions_config, :parallel_execution_limit, 5)
    workflow_timeout = Map.get(actions_config, :workflow_timeout_ms, 30_000)
    
    cond do
      parallel_limit < 1 or parallel_limit > 50 ->
        {:error, "Parallel execution limit must be between 1 and 50"}
      
      workflow_timeout < 5000 or workflow_timeout > 600_000 ->
        {:error, "Workflow timeout must be between 5 seconds and 10 minutes"}
      
      true -> :ok
    end
  end
  
  defp validate_workflows_configuration(workflows_config) do
    # Validate workflow configuration settings
    default_pattern = Map.get(workflows_config, :default_execution_pattern, :sequential)
    
    if default_pattern in [:parallel, :sequential, :conditional, :pipeline] do
      :ok
    else
      {:error, "Invalid default execution pattern: #{default_pattern}"}
    end
  end
  
  defp validate_orchestration_configuration(orchestration_config) do
    max_workflows = Map.get(orchestration_config, :max_concurrent_workflows, 10)
    
    if max_workflows >= 1 and max_workflows <= 100 do
      :ok
    else
      {:error, "Max concurrent workflows must be between 1 and 100"}
    end
  end
  
  # Configuration update helpers
  
  defp update_user_skills_preferences(user_id, new_preferences) do
    # Update user preferences using existing preference system
    preference_key = "skills_actions"
    
    case PreferenceResolver.get_preference(preference_key, user_id) do
      {:ok, current_prefs} ->
        updated_prefs = Map.merge(current_prefs, new_preferences)
        PreferenceResolver.set_preference(preference_key, user_id, updated_prefs)
      
      {:error, :not_found} ->
        # Create new user preference
        PreferenceResolver.set_preference(preference_key, user_id, new_preferences)
      
      error -> error
    end
  end
  
  defp update_project_skills_preferences(project_id, new_preferences) do
    # Update project preferences
    preference_key = "skills_actions"
    
    case PreferenceResolver.get_preference(preference_key, nil, project_id) do
      {:ok, current_prefs} ->
        updated_prefs = Map.merge(current_prefs, new_preferences)
        PreferenceResolver.set_preference(preference_key, nil, project_id, updated_prefs)
      
      {:error, :not_found} ->
        PreferenceResolver.set_preference(preference_key, nil, project_id, new_preferences)
      
      error -> error
    end
  end
  
  defp update_system_skills_preferences(new_preferences) do
    # Update system-level preferences
    # Would integrate with system configuration management
    Logger.info("System skills preferences update requested: #{inspect(new_preferences)}")
    {:ok, :system_update_noted}
  end
  
  # Integration utilities
  
  @doc """
  Check if Constitutional AI is required for skill execution.
  """
  def constitutional_ai_required?(skill_module, user_id, project_id \\ nil) do
    case get_skill_preferences(skill_module, user_id, project_id) do
      {:ok, preferences} ->
        skill_name = extract_skill_name(skill_module)
        
        # Constitutional AI required for safety-critical skills or user preference
        safety_critical_skills = ["threat_detection", "policy_enforcement", "authentication"]
        
        preferences.constitutional_ai_enabled or skill_name in safety_critical_skills
      
      _ -> false
    end
  end
  
  @doc """
  Get LLM provider preferences for skills execution.
  """
  def get_llm_provider_preferences_for_skills(user_id, project_id \\ nil) do
    case resolve_skills_actions_configuration(user_id, project_id) do
      {:ok, config} ->
        {:ok, %{
          llm_assistance_enabled: Map.get(config.skills, :llm_assistance_enabled, true),
          constitutional_ai_for_skills: Map.get(config.skills, :constitutional_ai_for_skills, false),
          llm_optimization_enabled: Map.get(config.orchestration, :llm_optimization_enabled, true),
          cost_optimization_priority: Map.get(config.orchestration, :cost_optimization_priority, :medium)
        }}
      
      error -> error
    end
  end
  
  @doc """
  Build execution context enhanced with configuration preferences.
  """
  def build_enhanced_execution_context(base_context, user_id, project_id \\ nil) do
    case resolve_skills_actions_configuration(user_id, project_id) do
      {:ok, config} ->
        enhanced_context = Map.merge(base_context, %{
          skills_config: config.skills,
          actions_config: config.actions,
          workflows_config: config.workflows,
          orchestration_config: config.orchestration,
          configuration_resolved_at: DateTime.utc_now()
        })
        
        {:ok, enhanced_context}
      
      error ->
        Logger.warning("Failed to enhance context with configuration: #{inspect(error)}")
        # Return base context with defaults
        {:ok, Map.merge(base_context, %{
          skills_config: %{},
          configuration_source: :default_fallback
        })}
    end
  end
  
  @doc """
  Get workflow execution preferences based on configuration.
  """
  def get_workflow_execution_preferences(workflow_type, user_id, project_id \\ nil) do
    case get_orchestration_preferences(user_id, project_id) do
      {:ok, orchestration_prefs} ->
        workflow_prefs = case get_workflow_template_preferences(workflow_type, user_id, project_id) do
          {:ok, template_prefs} -> template_prefs
          _ -> %{}
        end
        
        {:ok, %{
          coordination_strategy: orchestration_prefs.coordination_strategy,
          parallel_limit: orchestration_prefs.parallel_execution_limit,
          timeout_ms: orchestration_prefs.workflow_timeout_ms,
          llm_optimization: workflow_prefs[:llm_optimization] || false,
          constitutional_ai_compliance: workflow_prefs[:constitutional_ai_compliance] || false,
          performance_tracking: workflow_prefs[:performance_tracking] || true,
          execution_pattern: workflow_prefs[:execution_pattern] || :sequential
        }}
      
      error -> error
    end
  end
  
  # Configuration caching and performance
  
  @doc """
  Cache frequently accessed configuration to improve performance.
  """
  def cache_configuration(user_id, project_id, config) do
    cache_key = build_config_cache_key(user_id, project_id)
    cache_ttl = 300_000  # 5 minutes
    
    # Would integrate with existing cache system
    Logger.debug("Caching skills & actions configuration for #{cache_key}")
    
    # Store in process dictionary for simple caching (would use ETS in production)
    Process.put({:skills_actions_config_cache, cache_key}, {config, DateTime.utc_now()})
    
    :ok
  end
  
  @doc """
  Get cached configuration if available and not expired.
  """
  def get_cached_configuration(user_id, project_id \\ nil) do
    cache_key = build_config_cache_key(user_id, project_id)
    
    case Process.get({:skills_actions_config_cache, cache_key}) do
      {cached_config, cached_at} ->
        if DateTime.diff(DateTime.utc_now(), cached_at, :millisecond) < 300_000 do
          {:ok, cached_config}
        else
          {:error, :cache_expired}
        end
      
      nil ->
        {:error, :cache_miss}
    end
  end
  
  defp build_config_cache_key(user_id, project_id) do
    if project_id do
      "skills_actions_#{user_id}_#{project_id}"
    else
      "skills_actions_#{user_id}"
    end
  end
  
  @doc """
  Invalidate configuration cache when preferences change.
  """
  def invalidate_configuration_cache(user_id, project_id \\ nil) do
    cache_key = build_config_cache_key(user_id, project_id)
    Process.delete({:skills_actions_config_cache, cache_key})
    
    Logger.debug("Invalidated skills & actions configuration cache for #{cache_key}")
    :ok
  end
end