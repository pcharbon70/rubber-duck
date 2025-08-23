defmodule RubberDuck.Preferences.CodeQuality.SmellDetectionManager do
  @moduledoc """
  Code smell detection manager for configuring and controlling smell detection.

  Manages code smell detection preferences including detector enablement,
  severity thresholds, confidence settings, and remediation policies.
  Integrates with the preference hierarchy system for user and project
  customization.
  """

  require Logger

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Validators.CodeQualityPreferenceValidator

  @smell_categories [:readability, :complexity, :maintainability, :performance, :elixir_specific]

  @smell_detectors %{
    readability: [
      "long_method",
      "long_parameter_list",
      "large_class",
      "complex_conditional",
      "duplicate_code",
      "comments_smell",
      "inconsistent_naming",
      "magic_numbers"
    ],
    complexity: [
      "cyclomatic_complexity",
      "cognitive_complexity",
      "nested_conditionals",
      "switch_statements",
      "deep_nesting",
      "feature_envy",
      "data_clumps"
    ],
    maintainability: [
      "god_class",
      "refused_bequest",
      "shotgun_surgery",
      "divergent_change",
      "parallel_inheritance",
      "temporary_field",
      "message_chains",
      "middle_man"
    ],
    performance: [
      "premature_optimization",
      "inefficient_loops",
      "memory_leaks",
      "resource_not_closed",
      "string_concatenation",
      "unnecessary_object_creation"
    ],
    elixir_specific: [
      "improper_genserver_usage",
      "supervision_tree_misuse",
      "process_leak",
      "atom_abuse",
      "large_pattern_match",
      "unused_pattern_variables",
      "inefficient_enum_usage",
      "pipe_chain_abuse",
      "macro_overuse"
    ]
  }

  @doc """
  Get smell detection configuration for a user and optional project.
  """
  @spec get_smell_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_smell_config(user_id, project_id \\ nil) do
    with {:ok, raw_config} <- resolve_smell_preferences(user_id, project_id),
         {:ok, validated_config} <- validate_smell_configuration(raw_config),
         {:ok, processed_config} <- process_smell_configuration(validated_config) do
      {:ok, processed_config}
    else
      error ->
        Logger.warning(
          "Failed to get smell detection config for user #{user_id}: #{inspect(error)}"
        )

        {:error, "Unable to load smell detection configuration"}
    end
  end

  @doc """
  Check if smell detection is enabled for a user/project.
  """
  @spec smell_detection_enabled?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def smell_detection_enabled?(user_id, project_id \\ nil) do
    case get_smell_config(user_id, project_id) do
      {:ok, config} -> config.global.enabled and config.smells.enabled
      {:error, _} -> false
    end
  end

  @doc """
  Check if specific smell detector is enabled.
  """
  @spec detector_enabled?(
          user_id :: binary(),
          detector :: String.t(),
          project_id :: binary() | nil
        ) :: boolean()
  def detector_enabled?(user_id, detector, project_id \\ nil) do
    case get_smell_config(user_id, project_id) do
      {:ok, config} ->
        category_enabled = detector_category_enabled?(detector, config)
        individual_enabled = Map.get(config.detectors, detector, true)
        category_enabled and individual_enabled

      {:error, _} ->
        false
    end
  end

  @doc """
  Get enabled smell detectors for a category.
  """
  @spec get_enabled_detectors(
          user_id :: binary(),
          category :: atom(),
          project_id :: binary() | nil
        ) :: {:ok, list(String.t())} | {:error, String.t()}
  def get_enabled_detectors(user_id, category, project_id \\ nil)
      when category in @smell_categories do
    case get_smell_config(user_id, project_id) do
      {:ok, config} ->
        if category_enabled?(category, config) do
          detectors = Map.get(@smell_detectors, category, [])
          enabled_detectors = Enum.filter(detectors, &Map.get(config.detectors, &1, true))
          {:ok, enabled_detectors}
        else
          {:ok, []}
        end

      error ->
        error
    end
  end

  @doc """
  Get smell detection analysis configuration.
  """
  @spec get_analysis_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_analysis_config(user_id, project_id \\ nil) do
    case get_smell_config(user_id, project_id) do
      {:ok, config} ->
        {:ok,
         %{
           analysis_depth: config.smells.analysis_depth,
           confidence_threshold: config.smells.confidence_threshold,
           severity_threshold: config.global.severity_threshold,
           performance_mode: config.global.performance_mode
         }}

      error ->
        error
    end
  end

  @doc """
  Get remediation preferences for code smells.
  """
  @spec get_remediation_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_remediation_config(user_id, project_id \\ nil) do
    case get_smell_config(user_id, project_id) do
      {:ok, config} ->
        {:ok,
         %{
           auto_fix_enabled: config.smells.auto_fix_enabled,
           suggestion_aggressiveness: config.smells.suggestion_aggressiveness,
           approval_required: determine_approval_requirements(config),
           batch_processing_enabled: config.smells.batch_processing_enabled
         }}

      error ->
        error
    end
  end

  @doc """
  Check if automatic remediation is allowed for a smell type.
  """
  @spec auto_remediation_allowed?(
          user_id :: binary(),
          smell_type :: String.t(),
          project_id :: binary() | nil
        ) :: boolean()
  def auto_remediation_allowed?(user_id, smell_type, project_id \\ nil) do
    case get_remediation_config(user_id, project_id) do
      {:ok, config} ->
        config.auto_fix_enabled and safe_for_auto_fix?(smell_type)

      {:error, _} ->
        false
    end
  end

  # Private functions

  defp resolve_smell_preferences(user_id, project_id) do
    base_preferences = [
      "code_quality.global.enabled",
      "code_quality.global.auto_analysis_enabled",
      "code_quality.global.severity_threshold",
      "code_quality.global.performance_mode",
      "code_quality.smells.enabled",
      "code_quality.smells.analysis_depth",
      "code_quality.smells.confidence_threshold",
      "code_quality.smells.readability_enabled",
      "code_quality.smells.complexity_enabled",
      "code_quality.smells.maintainability_enabled",
      "code_quality.smells.performance_enabled",
      "code_quality.smells.auto_fix_enabled",
      "code_quality.smells.suggestion_aggressiveness"
    ]

    # Add individual detector preferences
    detector_preferences =
      @smell_detectors
      |> Enum.flat_map(fn {_category, detectors} -> detectors end)
      |> Enum.map(&"code_quality.smells.detectors.#{&1}")

    all_preferences = base_preferences ++ detector_preferences

    case PreferenceResolver.resolve_batch(user_id, all_preferences, project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp validate_smell_configuration(raw_config) do
    case CodeQualityPreferenceValidator.validate_code_quality_consistency(raw_config) do
      :ok -> {:ok, raw_config}
      error -> error
    end
  end

  defp process_smell_configuration(raw_config) do
    # Extract detector configurations
    detector_configs =
      raw_config
      |> Enum.filter(fn {key, _value} -> String.contains?(key, "detectors.") end)
      |> Enum.into(%{}, fn {key, value} ->
        detector_name = key |> String.split(".") |> List.last()
        {detector_name, parse_boolean(value)}
      end)

    processed = %{
      global: %{
        enabled: parse_boolean(raw_config["code_quality.global.enabled"]),
        auto_analysis_enabled:
          parse_boolean(raw_config["code_quality.global.auto_analysis_enabled"]),
        severity_threshold: raw_config["code_quality.global.severity_threshold"],
        performance_mode: raw_config["code_quality.global.performance_mode"]
      },
      smells: %{
        enabled: parse_boolean(raw_config["code_quality.smells.enabled"]),
        analysis_depth: raw_config["code_quality.smells.analysis_depth"],
        confidence_threshold: parse_float(raw_config["code_quality.smells.confidence_threshold"]),
        readability_enabled: parse_boolean(raw_config["code_quality.smells.readability_enabled"]),
        complexity_enabled: parse_boolean(raw_config["code_quality.smells.complexity_enabled"]),
        maintainability_enabled:
          parse_boolean(raw_config["code_quality.smells.maintainability_enabled"]),
        performance_enabled: parse_boolean(raw_config["code_quality.smells.performance_enabled"]),
        auto_fix_enabled: parse_boolean(raw_config["code_quality.smells.auto_fix_enabled"]),
        suggestion_aggressiveness: raw_config["code_quality.smells.suggestion_aggressiveness"],
        batch_processing_enabled: true
      },
      detectors: detector_configs
    }

    {:ok, processed}
  end

  defp detector_category_enabled?(detector, config) do
    category = find_detector_category(detector)

    case category do
      :readability -> config.smells.readability_enabled
      :complexity -> config.smells.complexity_enabled
      :maintainability -> config.smells.maintainability_enabled
      :performance -> config.smells.performance_enabled
      :elixir_specific -> true
      _ -> true
    end
  end

  defp category_enabled?(category, config) do
    case category do
      :readability -> config.smells.readability_enabled
      :complexity -> config.smells.complexity_enabled
      :maintainability -> config.smells.maintainability_enabled
      :performance -> config.smells.performance_enabled
      :elixir_specific -> true
    end
  end

  defp find_detector_category(detector) do
    Enum.find_value(@smell_detectors, fn {category, detectors} ->
      if detector in detectors, do: category
    end) || :unknown
  end

  defp determine_approval_requirements(config) do
    case config.smells.suggestion_aggressiveness do
      "conservative" -> false
      "moderate" -> config.smells.auto_fix_enabled
      "aggressive" -> true
    end
  end

  defp safe_for_auto_fix?(smell_type) do
    safe_fixes = [
      "magic_numbers",
      "inconsistent_naming",
      "comments_smell",
      "unused_pattern_variables",
      "string_concatenation"
    ]

    smell_type in safe_fixes
  end

  # Helper functions for type conversion
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: false

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> float_value
      _ -> 0.0
    end
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1.0
  defp parse_float(_), do: 0.0
end
