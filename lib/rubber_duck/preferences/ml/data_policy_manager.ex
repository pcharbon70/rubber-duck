defmodule RubberDuck.Preferences.Ml.DataPolicyManager do
  @moduledoc """
  ML data policy manager for privacy and compliance management.

  Manages data retention policies, user consent, privacy settings,
  anonymization controls, and compliance with data protection
  regulations (GDPR, CCPA). Integrates with user preferences
  for data sharing and training policies.
  """

  require Logger

  alias RubberDuck.Preferences.Ml.ConfigurationManager

  @privacy_levels %{
    "strict" => %{
      retention_days: 30,
      anonymization_required: true,
      sharing_allowed: false,
      consent_required: true,
      opt_out_allowed: true
    },
    "moderate" => %{
      retention_days: 180,
      anonymization_required: true,
      sharing_allowed: false,
      consent_required: true,
      opt_out_allowed: true
    },
    "permissive" => %{
      retention_days: 365,
      anonymization_required: false,
      sharing_allowed: true,
      consent_required: false,
      opt_out_allowed: true
    }
  }

  @doc """
  Get data policies for a user and project.
  """
  @spec get_data_policies(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_data_policies(user_id, project_id \\ nil) do
    with {:ok, config} <- ConfigurationManager.get_data_policies(user_id, project_id),
         {:ok, processed_policies} <- process_data_policies(config) do
      {:ok, processed_policies}
    else
      error ->
        Logger.warning("Failed to get data policies for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to load data policies"}
    end
  end

  @doc """
  Check if data retention is compliant with user preferences and regulations.
  """
  @spec retention_compliant?(
          user_id :: binary(),
          data_age_days :: integer(),
          project_id :: binary() | nil
        ) :: boolean()
  def retention_compliant?(user_id, data_age_days, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} ->
        data_age_days <= policies.retention_days

      {:error, _} ->
        # Default to strict compliance if policies can't be loaded
        data_age_days <= 30
    end
  end

  @doc """
  Check if user has opted out of ML training data usage.
  """
  @spec user_opted_out?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def user_opted_out?(user_id, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} ->
        if policies.opt_out_enabled do
          check_user_opt_out_status(user_id, project_id)
        else
          false
        end

      {:error, _} ->
        # Default to opted out if policies can't be loaded
        true
    end
  end

  @doc """
  Check if data anonymization is required.
  """
  @spec anonymization_required?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def anonymization_required?(user_id, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} -> policies.anonymization_required
      {:error, _} -> true
    end
  end

  @doc """
  Check if data sharing with external systems is allowed.
  """
  @spec sharing_allowed?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def sharing_allowed?(user_id, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} -> policies.sharing_allowed
      {:error, _} -> false
    end
  end

  @doc """
  Get data cleanup schedule based on retention policies.
  """
  @spec get_cleanup_schedule(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_cleanup_schedule(user_id, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} ->
        cleanup_date = Date.add(Date.utc_today(), -policies.retention_days)

        schedule = %{
          enabled: policies.auto_cleanup_enabled,
          retention_days: policies.retention_days,
          next_cleanup_date: cleanup_date,
          cleanup_frequency: determine_cleanup_frequency(policies.retention_days)
        }

        {:ok, schedule}

      error ->
        error
    end
  end

  @doc """
  Validate data usage request against policies.
  """
  @spec validate_data_usage(
          user_id :: binary(),
          usage_type :: atom(),
          data_attributes :: map(),
          project_id :: binary() | nil
        ) :: :ok | {:error, String.t()}
  def validate_data_usage(user_id, usage_type, data_attributes, project_id \\ nil) do
    with {:ok, policies} <- get_data_policies(user_id, project_id),
         :ok <- validate_consent_requirements(user_id, usage_type, policies, project_id),
         :ok <- validate_privacy_requirements(data_attributes, policies),
         :ok <- validate_retention_requirements(data_attributes, policies),
         :ok <- validate_sharing_requirements(usage_type, policies) do
      :ok
    end
  end

  @doc """
  Get anonymization requirements for data processing.
  """
  @spec get_anonymization_requirements(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_anonymization_requirements(user_id, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} ->
        requirements = %{
          anonymization_enabled: policies.anonymization_required,
          privacy_level: policies.privacy_mode,
          fields_to_anonymize: get_anonymizable_fields(policies.privacy_mode),
          anonymization_method: get_anonymization_method(policies.privacy_mode)
        }

        {:ok, requirements}

      error ->
        error
    end
  end

  # Private helper functions

  defp process_data_policies(config) do
    privacy_level = Map.get(@privacy_levels, config.privacy_mode, @privacy_levels["strict"])

    processed = %{
      retention_days: min(config.retention_days, privacy_level.retention_days),
      auto_cleanup_enabled: config.auto_cleanup_enabled,
      privacy_mode: config.privacy_mode,
      anonymization_required:
        config.anonymization_enabled or privacy_level.anonymization_required,
      user_consent_required: config.user_consent_required or privacy_level.consent_required,
      opt_out_enabled: config.opt_out_enabled,
      sharing_allowed: config.sharing_allowed and privacy_level.sharing_allowed
    }

    {:ok, processed}
  end

  defp check_user_opt_out_status(_user_id, _project_id) do
    # Placeholder for actual user opt-out status checking
    # This would integrate with user consent management system
    false
  end

  defp determine_cleanup_frequency(retention_days) do
    cond do
      retention_days <= 90 -> :daily
      retention_days <= 365 -> :weekly
      true -> :monthly
    end
  end

  defp validate_consent_requirements(user_id, usage_type, policies, project_id) do
    if policies.user_consent_required do
      if check_user_consent(user_id, usage_type, project_id) do
        :ok
      else
        {:error, "User consent required for #{usage_type} data usage"}
      end
    else
      :ok
    end
  end

  defp validate_privacy_requirements(data_attributes, policies) do
    contains_pii = Map.get(data_attributes, :contains_pii, false)

    if contains_pii and not policies.anonymization_required do
      {:error, "PII data requires anonymization based on privacy settings"}
    else
      :ok
    end
  end

  defp validate_retention_requirements(data_attributes, policies) do
    data_age = Map.get(data_attributes, :age_days, 0)

    if data_age > policies.retention_days do
      {:error, "Data exceeds retention period (#{data_age} > #{policies.retention_days} days)"}
    else
      :ok
    end
  end

  defp validate_sharing_requirements(usage_type, policies) do
    if usage_type == :external_sharing and not policies.sharing_allowed do
      {:error, "External data sharing not allowed by privacy settings"}
    else
      :ok
    end
  end

  defp check_user_consent(_user_id, _usage_type, _project_id) do
    # Placeholder for user consent checking
    # This would integrate with actual consent management system
    true
  end

  defp get_anonymizable_fields(privacy_mode) do
    case privacy_mode do
      "strict" -> [:email, :ip_address, :user_id, :session_id, :location]
      "moderate" -> [:email, :ip_address, :user_id]
      "permissive" -> [:email]
    end
  end

  defp get_anonymization_method(privacy_mode) do
    case privacy_mode do
      "strict" -> :hash_with_salt
      "moderate" -> :hash
      "permissive" -> :pseudonymize
    end
  end
end
