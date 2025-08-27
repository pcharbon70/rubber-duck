defmodule RubberDuck.Verdict.Configuration.ConfigurationValidator do
  @moduledoc """
  Comprehensive validation module for Verdict configuration hierarchy.

  This module provides domain-specific validation for Verdict configurations
  across all three tiers (System -> User -> Project) including:
  - Budget and cost constraint validation
  - Model and provider compatibility validation
  - Evaluation criteria consistency validation
  - Security and compliance validation

  Integrates with the existing preference validation system while
  providing Verdict-specific validation logic and error reporting.
  """

  require Logger

  alias RubberDuck.Verdict.ProjectVerdictSettings
  alias RubberDuck.Verdict.UserVerdictPreferences
  alias RubberDuck.Verdict.VerdictSystemConfiguration

  @valid_providers ["openai", "anthropic", "ollama", "azure", "vertex"]
  @valid_models %{
    "openai" => ["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"],
    "anthropic" => ["claude-3-sonnet", "claude-3-haiku", "claude-3-opus"],
    "ollama" => ["llama2", "codellama", "mistral"]
  }
  @required_criteria ["correctness", "security", "maintainability"]

  @doc """
  Validate complete Verdict configuration hierarchy for a user/project.

  Performs comprehensive validation including:
  - Individual tier validation (system, user, project)
  - Cross-tier consistency validation
  - Domain-specific business rule validation
  - Performance and security validation
  """
  def validate_hierarchy(user_id, project_id \\ nil, _options \\ []) do
    Logger.debug("Validating Verdict configuration hierarchy for user #{user_id}")

    with {:ok, system_config} <- validate_system_configuration(),
         {:ok, user_config} <- validate_user_configuration(user_id),
         {:ok, project_config} <- validate_project_configuration(project_id),
         {:ok, resolved_config} <- validate_resolved_configuration(user_id, project_id),
         :ok <-
           validate_cross_tier_consistency(
             system_config,
             user_config,
             project_config,
             resolved_config
           ) do
      Logger.debug("Verdict configuration hierarchy validation successful")

      {:ok,
       %{
         validation_status: :valid,
         validated_at: DateTime.utc_now(),
         validation_levels: [:system, :user, :project, :resolved, :cross_tier],
         configuration_summary: summarize_configuration(resolved_config)
       }}
    else
      {:error, reason} = error ->
        Logger.warning("Verdict configuration validation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Validate system-level Verdict configuration.
  """
  def validate_system_configuration(config \\ nil) do
    config = config || load_system_configuration()

    case config do
      {:ok, system_config} ->
        validation_results = [
          validate_required_system_fields(system_config),
          validate_system_budget_constraints(system_config),
          validate_system_provider_settings(system_config),
          validate_system_quality_thresholds(system_config),
          validate_system_security_settings(system_config)
        ]

        case find_validation_error(validation_results) do
          nil -> {:ok, system_config}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Validate user-level Verdict preferences.
  """
  def validate_user_configuration(user_id, preferences \\ nil) do
    preferences = preferences || load_user_preferences(user_id)

    case preferences do
      {:ok, user_prefs} ->
        validation_results = [
          validate_user_budget_settings(user_prefs),
          validate_user_threshold_settings(user_prefs),
          validate_user_provider_preferences(user_prefs),
          validate_user_criteria_weights(user_prefs),
          validate_user_notification_settings(user_prefs)
        ]

        case find_validation_error(validation_results) do
          nil -> {:ok, user_prefs}
          error -> error
        end

      {:error, :not_found} ->
        {:ok, :not_configured}

      error ->
        error
    end
  end

  @doc """
  Validate project-level Verdict settings.
  """
  def validate_project_configuration(project_id, settings \\ nil)

  def validate_project_configuration(project_id, settings) when not is_nil(project_id) do
    settings = settings || load_project_settings(project_id)

    case settings do
      {:ok, project_settings} ->
        validation_results = [
          validate_project_team_settings(project_settings),
          validate_project_budget_settings(project_settings),
          validate_project_quality_standards(project_settings),
          validate_project_provider_restrictions(project_settings),
          validate_project_security_requirements(project_settings),
          validate_project_workflow_settings(project_settings)
        ]

        case find_validation_error(validation_results) do
          nil -> {:ok, project_settings}
          error -> error
        end

      {:error, :not_found} ->
        {:ok, :not_configured}

      error ->
        error
    end
  end

  def validate_project_configuration(nil, _settings), do: {:ok, :not_configured}

  @doc """
  Validate resolved configuration after three-tier merge.
  """
  def validate_resolved_configuration(user_id, project_id \\ nil) do
    alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver

    case VerdictConfigurationResolver.resolve_configuration(user_id, project_id) do
      {:ok, resolved_config} ->
        validation_results = [
          validate_resolved_budget_consistency(resolved_config),
          validate_resolved_provider_model_compatibility(resolved_config),
          validate_resolved_threshold_relationships(resolved_config),
          validate_resolved_criteria_completeness(resolved_config),
          validate_resolved_security_compliance(resolved_config)
        ]

        case find_validation_error(validation_results) do
          nil -> {:ok, resolved_config}
          error -> error
        end

      error ->
        error
    end
  end

  # System configuration validation

  defp validate_required_system_fields(config) do
    required_fields = [
      :enabled,
      :default_screening_model,
      :default_detailed_model,
      :global_daily_budget
    ]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        value = Map.get(config, field)
        is_nil(value) or (is_binary(value) and String.trim(value) == "")
      end)

    case missing_fields do
      [] -> :ok
      fields -> {:error, "Missing required system configuration fields: #{inspect(fields)}"}
    end
  end

  defp validate_system_budget_constraints(config) do
    global_budget = Map.get(config, :global_daily_budget, 0)
    max_tokens = Map.get(config, :max_tokens_per_evaluation, 1500)

    budget_value =
      case global_budget do
        %Decimal{} = d -> Decimal.to_float(d)
        b when is_number(b) -> b
        _ -> 0
      end

    cond do
      budget_value <= 0 ->
        {:error, "System global daily budget must be positive"}

      max_tokens < 100 or max_tokens > 10_000 ->
        {:error, "Max tokens per evaluation must be between 100 and 10,000"}

      true ->
        :ok
    end
  end

  defp validate_system_provider_settings(config) do
    providers = Map.get(config, :preferred_providers, [])
    screening_model = Map.get(config, :default_screening_model)
    detailed_model = Map.get(config, :default_detailed_model)

    with :ok <- validate_provider_list(providers),
         :ok <- validate_model_provider_compatibility(screening_model, providers),
         :ok <- validate_model_provider_compatibility(detailed_model, providers) do
      :ok
    else
      error -> error
    end
  end

  defp validate_system_quality_thresholds(config) do
    quality_threshold = get_decimal_value(config, :default_quality_threshold, 0.8)
    escalation_threshold = get_decimal_value(config, :escalation_threshold, 0.6)

    cond do
      quality_threshold < 0 or quality_threshold > 1 ->
        {:error, "Quality threshold must be between 0 and 1"}

      escalation_threshold < 0 or escalation_threshold > 1 ->
        {:error, "Escalation threshold must be between 0 and 1"}

      escalation_threshold >= quality_threshold ->
        {:error, "Escalation threshold must be lower than quality threshold"}

      true ->
        :ok
    end
  end

  defp validate_system_security_settings(config) do
    audit_enabled = Map.get(config, :audit_all_evaluations, false)
    bias_mitigation = Map.get(config, :bias_mitigation_enabled, false)
    retention_days = Map.get(config, :data_retention_days, 90)

    cond do
      not is_boolean(audit_enabled) ->
        {:error, "Audit setting must be boolean"}

      not is_boolean(bias_mitigation) ->
        {:error, "Bias mitigation setting must be boolean"}

      not is_integer(retention_days) or retention_days < 1 ->
        {:error, "Data retention days must be positive integer"}

      true ->
        :ok
    end
  end

  # User configuration validation

  defp validate_user_budget_settings(user_prefs) do
    personal_budget = get_decimal_value(user_prefs, :personal_daily_budget, 25.0)
    cost_alert_threshold = get_decimal_value(user_prefs, :cost_alert_threshold, 0.8)

    cond do
      personal_budget <= 0 ->
        {:error, "Personal daily budget must be positive"}

      cost_alert_threshold <= 0 or cost_alert_threshold > 1 ->
        {:error, "Cost alert threshold must be between 0 and 1"}

      true ->
        :ok
    end
  end

  defp validate_user_threshold_settings(user_prefs) do
    auto_accept = get_decimal_value(user_prefs, :auto_accept_threshold, 0.9)
    manual_review = get_decimal_value(user_prefs, :manual_review_threshold, 0.6)

    cond do
      auto_accept < 0 or auto_accept > 1 ->
        {:error, "Auto accept threshold must be between 0 and 1"}

      manual_review < 0 or manual_review > 1 ->
        {:error, "Manual review threshold must be between 0 and 1"}

      manual_review >= auto_accept ->
        {:error, "Manual review threshold must be lower than auto accept threshold"}

      true ->
        :ok
    end
  end

  defp validate_user_provider_preferences(user_prefs) do
    preferred = Map.get(user_prefs, :preferred_providers, [])
    avoided = Map.get(user_prefs, :avoid_providers, [])

    cond do
      not is_list(preferred) ->
        {:error, "Preferred providers must be a list"}

      not is_list(avoided) ->
        {:error, "Avoided providers must be a list"}

      not Enum.all?(preferred, &(&1 in @valid_providers)) ->
        {:error, "Invalid provider in preferred list"}

      not Enum.all?(avoided, &(&1 in @valid_providers)) ->
        {:error, "Invalid provider in avoided list"}

      length(preferred ++ avoided) != length(Enum.uniq(preferred ++ avoided)) ->
        {:error, "Cannot prefer and avoid the same provider"}

      true ->
        :ok
    end
  end

  defp validate_user_criteria_weights(user_prefs) do
    case Map.get(user_prefs, :custom_criteria_weights) do
      weights when is_map(weights) and map_size(weights) > 0 ->
        validate_criteria_weight_sum(weights)

      # No custom weights is valid
      _ ->
        :ok
    end
  end

  defp validate_user_notification_settings(user_prefs) do
    feedback_freq = Map.get(user_prefs, :feedback_frequency, :weekly)

    if feedback_freq in [:never, :monthly, :weekly, :daily] do
      :ok
    else
      {:error, "Invalid feedback frequency setting"}
    end
  end

  # Project configuration validation

  defp validate_project_team_settings(project_settings) do
    team_size = Map.get(project_settings, :team_size, 1)
    consensus_required = Map.get(project_settings, :consensus_required, false)
    minimum_judges = Map.get(project_settings, :minimum_judges, 1)

    cond do
      team_size < 1 ->
        {:error, "Team size must be at least 1"}

      consensus_required and minimum_judges < 2 ->
        {:error, "Consensus evaluations require at least 2 judges"}

      minimum_judges > 5 ->
        {:error, "Maximum 5 judges supported per evaluation"}

      true ->
        :ok
    end
  end

  defp validate_project_budget_settings(project_settings) do
    project_budget = get_decimal_value(project_settings, :project_daily_budget, 50.0)
    team_size = Map.get(project_settings, :team_size, 1)
    budget_strategy = Map.get(project_settings, :budget_allocation_strategy, :equal_distribution)

    budget_per_member = project_budget / max(team_size, 1)

    cond do
      project_budget <= 0 ->
        {:error, "Project daily budget must be positive"}

      budget_per_member < 1.0 ->
        {:error, "Budget allocation results in less than $1 per team member"}

      budget_per_member > 200.0 ->
        {:error, "Budget allocation exceeds $200 per team member"}

      budget_strategy not in [:equal_distribution, :usage_based, :role_based, :manual] ->
        {:error, "Invalid budget allocation strategy"}

      true ->
        :ok
    end
  end

  defp validate_project_quality_standards(project_settings) do
    quality_threshold = get_decimal_value(project_settings, :team_quality_threshold, 0.85)
    criteria_weights = Map.get(project_settings, :evaluation_criteria_weights)

    with :ok <- validate_quality_threshold_range(quality_threshold, "team quality threshold"),
         :ok <- validate_project_criteria_weights(criteria_weights) do
      :ok
    else
      error -> error
    end
  end

  defp validate_project_provider_restrictions(project_settings) do
    allowed = Map.get(project_settings, :allowed_providers, [])
    restricted = Map.get(project_settings, :restricted_providers, [])

    cond do
      not is_list(allowed) ->
        {:error, "Allowed providers must be a list"}

      not is_list(restricted) ->
        {:error, "Restricted providers must be a list"}

      not Enum.all?(allowed, &(&1 in @valid_providers)) ->
        {:error, "Invalid provider in allowed list"}

      not Enum.all?(restricted, &(&1 in @valid_providers)) ->
        {:error, "Invalid provider in restricted list"}

      not Enum.empty?(allowed) and Enum.filter(allowed, &(&1 not in restricted)) == [] ->
        {:error, "Cannot restrict all allowed providers"}

      true ->
        :ok
    end
  end

  defp validate_project_security_requirements(project_settings) do
    security_level = Map.get(project_settings, :security_requirements_level, :standard)
    compliance_standards = Map.get(project_settings, :compliance_standards, [])
    audit_retention = Map.get(project_settings, :audit_retention_override)

    cond do
      security_level not in [:basic, :standard, :high, :critical] ->
        {:error, "Invalid security requirements level"}

      security_level in [:high, :critical] and Enum.empty?(compliance_standards) ->
        {:error, "High security levels require compliance standards"}

      audit_retention && (not is_integer(audit_retention) or audit_retention < 1) ->
        {:error, "Audit retention override must be positive integer"}

      true ->
        :ok
    end
  end

  defp validate_project_workflow_settings(project_settings) do
    workflow = Map.get(project_settings, :evaluation_workflow, :standard)

    if workflow in [:minimal, :standard, :comprehensive, :custom] do
      :ok
    else
      {:error, "Invalid evaluation workflow setting"}
    end
  end

  # Resolved configuration validation

  defp validate_resolved_budget_consistency(resolved_config) do
    budget = get_decimal_value(resolved_config, :global_daily_budget, 100.0)
    max_tokens = Map.get(resolved_config, :max_tokens_per_evaluation, 1500)
    concurrent_limit = Map.get(resolved_config, :concurrent_evaluations_limit, 10)

    # Calculate if concurrent evaluations could exceed budget
    estimated_cost_per_eval = calculate_estimated_cost(max_tokens, resolved_config)
    max_concurrent_cost = estimated_cost_per_eval * concurrent_limit

    if max_concurrent_cost > budget do
      {:error, "Concurrent evaluation limit could exceed daily budget"}
    else
      :ok
    end
  end

  defp validate_resolved_provider_model_compatibility(resolved_config) do
    providers = Map.get(resolved_config, :preferred_providers, [])
    screening_model = Map.get(resolved_config, :default_screening_model)
    detailed_model = Map.get(resolved_config, :default_detailed_model)

    with :ok <- validate_model_available_in_providers(screening_model, providers),
         :ok <- validate_model_available_in_providers(detailed_model, providers) do
      :ok
    else
      error -> error
    end
  end

  defp validate_resolved_threshold_relationships(resolved_config) do
    quality = get_decimal_value(resolved_config, :default_quality_threshold, 0.8)
    escalation = get_decimal_value(resolved_config, :escalation_threshold, 0.6)
    auto_accept = get_decimal_value(resolved_config, :auto_accept_threshold, 0.9)
    manual_review = get_decimal_value(resolved_config, :manual_review_threshold, 0.6)

    cond do
      escalation >= quality ->
        {:error, "Escalation threshold must be lower than quality threshold"}

      manual_review >= auto_accept ->
        {:error, "Manual review threshold must be lower than auto accept threshold"}

      true ->
        :ok
    end
  end

  defp validate_resolved_criteria_completeness(resolved_config) do
    criteria_weights = Map.get(resolved_config, :evaluation_criteria_weights, %{})

    cond do
      not is_map(criteria_weights) ->
        {:error, "Evaluation criteria weights must be a map"}

      map_size(criteria_weights) == 0 ->
        {:error, "At least one evaluation criterion must be defined"}

      not Enum.all?(@required_criteria, &Map.has_key?(criteria_weights, &1)) ->
        missing = Enum.filter(@required_criteria, &(!Map.has_key?(criteria_weights, &1)))
        {:error, "Missing required criteria: #{inspect(missing)}"}

      true ->
        validate_criteria_weight_sum(criteria_weights)
    end
  end

  defp validate_resolved_security_compliance(resolved_config) do
    audit_enabled = Map.get(resolved_config, :audit_all_evaluations, false)
    bias_mitigation = Map.get(resolved_config, :bias_mitigation_enabled, false)
    data_retention = Map.get(resolved_config, :data_retention_days, 90)

    # Basic security compliance validation
    cond do
      not is_boolean(audit_enabled) ->
        {:error, "Audit setting must be boolean"}

      not is_boolean(bias_mitigation) ->
        {:error, "Bias mitigation setting must be boolean"}

      data_retention < 1 ->
        {:error, "Data retention must be at least 1 day"}

      true ->
        :ok
    end
  end

  # Cross-tier validation

  defp validate_cross_tier_consistency(
         _system_config,
         user_config,
         project_config,
         resolved_config
       ) do
    validation_results = [
      validate_budget_hierarchy_consistency(user_config, project_config, resolved_config),
      validate_threshold_hierarchy_consistency(user_config, project_config, resolved_config),
      validate_provider_hierarchy_consistency(user_config, project_config, resolved_config)
    ]

    case find_validation_error(validation_results) do
      nil -> :ok
      error -> error
    end
  end

  defp validate_budget_hierarchy_consistency(user_config, project_config, _resolved_config) do
    # Validate that project budget doesn't exceed reasonable multiples of user budget
    case {user_config, project_config} do
      {:not_configured, _} ->
        :ok

      {_, :not_configured} ->
        :ok

      {user_prefs, project_settings} ->
        user_budget = get_decimal_value(user_prefs, :personal_daily_budget, 25.0)
        project_budget = get_decimal_value(project_settings, :project_daily_budget, 50.0)
        team_size = Map.get(project_settings, :team_size, 1)

        expected_project_budget = user_budget * team_size

        if project_budget > expected_project_budget * 2 do
          {:error, "Project budget significantly exceeds user budget expectations"}
        else
          :ok
        end
    end
  end

  defp validate_threshold_hierarchy_consistency(user_config, project_config, _resolved_config) do
    # Validate that project thresholds are reasonable given user preferences
    case {user_config, project_config} do
      {:not_configured, _} ->
        :ok

      {_, :not_configured} ->
        :ok

      {user_prefs, project_settings} ->
        user_quality_pref = get_decimal_value(user_prefs, :quality_vs_cost_preference, 0.7)
        project_threshold = get_decimal_value(project_settings, :team_quality_threshold, 0.85)

        # If user prefers cost savings but project requires high quality, flag inconsistency
        if user_quality_pref < 0.5 and project_threshold > 0.9 do
          {:error, "Project quality requirements conflict with user cost preference"}
        else
          :ok
        end
    end
  end

  defp validate_provider_hierarchy_consistency(user_config, project_config, _resolved_config) do
    # Validate that project provider restrictions don't conflict with user preferences
    case {user_config, project_config} do
      {:not_configured, _} ->
        :ok

      {_, :not_configured} ->
        :ok

      {user_prefs, project_settings} ->
        validate_provider_conflicts(user_prefs, project_settings)
    end
  end

  defp validate_provider_conflicts(user_prefs, project_settings) do
    user_preferred = Map.get(user_prefs, :preferred_providers, [])
    user_avoided = Map.get(user_prefs, :avoid_providers, [])
    project_allowed = Map.get(project_settings, :allowed_providers, [])
    project_restricted = Map.get(project_settings, :restricted_providers, [])

    cond do
      not Enum.empty?(user_preferred) and not Enum.empty?(project_allowed) ->
        validate_preferred_allowed_overlap(user_preferred, project_allowed)

      not Enum.empty?(user_avoided) and not Enum.empty?(project_restricted) ->
        validate_combined_restrictions(user_avoided, project_restricted)

      true ->
        :ok
    end
  end

  defp validate_preferred_allowed_overlap(user_preferred, project_allowed) do
    overlap = MapSet.intersection(MapSet.new(user_preferred), MapSet.new(project_allowed))

    if MapSet.size(overlap) == 0 do
      {:error, "Project allowed providers conflict with user preferences"}
    else
      :ok
    end
  end

  defp validate_combined_restrictions(user_avoided, project_restricted) do
    user_available = @valid_providers -- user_avoided
    project_available = @valid_providers -- project_restricted

    combined_available =
      MapSet.intersection(MapSet.new(user_available), MapSet.new(project_available))

    if MapSet.size(combined_available) == 0 do
      {:error, "Combined provider restrictions leave no available providers"}
    else
      :ok
    end
  end

  # Helper functions

  defp validate_provider_list(providers) when is_list(providers) do
    invalid_providers = Enum.filter(providers, &(&1 not in @valid_providers))

    case invalid_providers do
      [] -> :ok
      invalid -> {:error, "Invalid providers: #{inspect(invalid)}"}
    end
  end

  defp validate_provider_list(_), do: {:error, "Providers must be a list"}

  defp validate_model_provider_compatibility(model, providers) do
    case get_model_provider(model) do
      {:ok, required_provider} ->
        if required_provider in providers do
          :ok
        else
          {:error, "Model #{model} requires provider #{required_provider}"}
        end

      {:error, _} ->
        {:error, "Unknown model: #{model}"}
    end
  end

  defp validate_model_available_in_providers(model, providers) do
    case get_model_provider(model) do
      {:ok, required_provider} ->
        if required_provider in providers or Enum.empty?(providers) do
          :ok
        else
          {:error, "Model #{model} not available in preferred providers"}
        end

      {:error, _} ->
        {:error, "Unknown model: #{model}"}
    end
  end

  defp get_model_provider(model) do
    provider =
      Enum.find(@valid_models, fn {_provider, models} ->
        model in models
      end)

    case provider do
      {provider_name, _models} -> {:ok, provider_name}
      nil -> {:error, :unknown_model}
    end
  end

  defp validate_criteria_weight_sum(weights) when is_map(weights) do
    total = weights |> Map.values() |> Enum.sum()

    if abs(total - 1.0) < 0.001 do
      :ok
    else
      {:error, "Criteria weights must sum to 1.0, current sum: #{Float.round(total, 3)}"}
    end
  end

  defp validate_project_criteria_weights(nil), do: :ok
  defp validate_project_criteria_weights(weights) when map_size(weights) == 0, do: :ok

  defp validate_project_criteria_weights(weights) when is_map(weights) do
    validate_criteria_weight_sum(weights)
  end

  defp validate_project_criteria_weights(_),
    do: {:error, "Project criteria weights must be a map"}

  defp validate_quality_threshold_range(threshold, field_name) do
    if threshold >= 0 and threshold <= 1 do
      :ok
    else
      {:error, "#{field_name} must be between 0 and 1"}
    end
  end

  defp get_decimal_value(config, key, default) do
    case Map.get(config, key, default) do
      %Decimal{} = d -> Decimal.to_float(d)
      value when is_number(value) -> value
      _ -> default
    end
  end

  defp calculate_estimated_cost(max_tokens, config) do
    # Simple cost estimation based on model and token count
    model = Map.get(config, :default_screening_model, "gpt-4o-mini")

    cost_per_1k_tokens =
      case model do
        "gpt-4o" -> 0.03
        "gpt-4o-mini" -> 0.01
        "claude-3-sonnet" -> 0.02
        "claude-3-haiku" -> 0.01
        _ -> 0.015
      end

    max_tokens / 1000 * cost_per_1k_tokens
  end

  defp find_validation_error(results) do
    Enum.find(results, fn result -> result != :ok end)
  end

  defp load_system_configuration do
    VerdictSystemConfiguration.get_active_configuration()
  end

  defp load_user_preferences(user_id) do
    UserVerdictPreferences.by_user(user_id)
  end

  defp load_project_settings(project_id) do
    ProjectVerdictSettings.by_project(project_id)
  end

  defp summarize_configuration(config) do
    %{
      total_keys: map_size(config),
      has_custom_criteria: Map.has_key?(config, :evaluation_criteria_weights),
      budget_configured: Map.has_key?(config, :global_daily_budget),
      providers_configured: not Enum.empty?(Map.get(config, :preferred_providers, [])),
      progressive_evaluation: Map.get(config, :progressive_evaluation_enabled, false),
      bias_mitigation: Map.get(config, :bias_mitigation_enabled, false)
    }
  end

  # Public validation API for external use

  def validate_configuration_update(level, config_data) do
    case level do
      :system -> validate_system_configuration_data(config_data)
      :user -> validate_user_configuration_data(config_data)
      :project -> validate_project_configuration_data(config_data)
      _ -> {:error, "Invalid configuration level"}
    end
  end

  defp validate_system_configuration_data(config_data) do
    VerdictSystemConfiguration.validate_configuration(config_data)
  end

  defp validate_user_configuration_data(config_data) do
    validation_results = [
      validate_user_budget_settings(config_data),
      validate_user_threshold_settings(config_data),
      validate_user_provider_preferences(config_data),
      validate_user_criteria_weights(config_data),
      validate_user_notification_settings(config_data)
    ]

    case find_validation_error(validation_results) do
      nil -> :ok
      error -> error
    end
  end

  defp validate_project_configuration_data(config_data) do
    validation_results = [
      validate_project_team_settings(config_data),
      validate_project_budget_settings(config_data),
      validate_project_quality_standards(config_data),
      validate_project_provider_restrictions(config_data),
      validate_project_security_requirements(config_data),
      validate_project_workflow_settings(config_data)
    ]

    case find_validation_error(validation_results) do
      nil -> :ok
      error -> error
    end
  end
end
