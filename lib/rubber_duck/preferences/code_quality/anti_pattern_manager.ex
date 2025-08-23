defmodule RubberDuck.Preferences.CodeQuality.AntiPatternManager do
  @moduledoc """
  Anti-pattern detection manager for Elixir/OTP specific patterns.

  Manages anti-pattern detection preferences including pattern enablement,
  Elixir-specific enforcement levels, remediation controls, and team-specific
  standards. Focuses on OTP patterns, functional paradigm compliance, and
  macro hygiene requirements.
  """

  require Logger

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Validators.CodeQualityPreferenceValidator

  @anti_pattern_categories [:code_patterns, :design_patterns, :process_patterns, :macro_patterns]

  @anti_patterns %{
    code_patterns: [
      "dynamic_atom_creation",
      "non_assertive_code",
      "unrelated_multi_clause",
      "complex_guard_expressions",
      "improper_error_handling",
      "inefficient_recursion"
    ],
    design_patterns: [
      "large_structs",
      "god_module",
      "feature_envy",
      "improper_abstraction",
      "circular_dependencies",
      "tight_coupling",
      "interface_segregation_violation"
    ],
    process_patterns: [
      "supervision_tree_misuse",
      "genserver_state_abuse",
      "process_bottleneck",
      "improper_process_communication",
      "resource_leak",
      "deadlock_prone_design"
    ],
    macro_patterns: [
      "unsafe_macro_usage",
      "compile_time_abuse",
      "macro_instead_of_function",
      "quote_unquote_abuse",
      "ast_manipulation_overuse",
      "macro_hygiene_violation"
    ]
  }

  @severity_mappings %{
    "dynamic_atom_creation" => :critical,
    "resource_leak" => :critical,
    "deadlock_prone_design" => :critical,
    "unsafe_macro_usage" => :error,
    "supervision_tree_misuse" => :error,
    "large_structs" => :warning,
    "complex_guard_expressions" => :warning,
    "god_module" => :info
  }

  @doc """
  Get anti-pattern detection configuration for a user and optional project.
  """
  @spec get_anti_pattern_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_anti_pattern_config(user_id, project_id \\ nil) do
    with {:ok, raw_config} <- resolve_anti_pattern_preferences(user_id, project_id),
         {:ok, validated_config} <- validate_anti_pattern_configuration(raw_config),
         {:ok, processed_config} <- process_anti_pattern_configuration(validated_config) do
      {:ok, processed_config}
    else
      error ->
        Logger.warning("Failed to get anti-pattern config for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to load anti-pattern configuration"}
    end
  end

  @doc """
  Check if anti-pattern detection is enabled for a user/project.
  """
  @spec anti_pattern_detection_enabled?(user_id :: binary(), project_id :: binary() | nil) ::
          boolean()
  def anti_pattern_detection_enabled?(user_id, project_id \\ nil) do
    case get_anti_pattern_config(user_id, project_id) do
      {:ok, config} -> config.global.enabled and config.anti_patterns.enabled
      {:error, _} -> false
    end
  end

  @doc """
  Check if specific anti-pattern detection is enabled.
  """
  @spec pattern_enabled?(
          user_id :: binary(),
          pattern :: String.t(),
          project_id :: binary() | nil
        ) :: boolean()
  def pattern_enabled?(user_id, pattern, project_id \\ nil) do
    case get_anti_pattern_config(user_id, project_id) do
      {:ok, config} ->
        category_enabled = pattern_category_enabled?(pattern, config)
        individual_enabled = Map.get(config.patterns, pattern, true)
        severity_allowed = severity_level_allowed?(pattern, config)

        category_enabled and individual_enabled and severity_allowed

      {:error, _} ->
        false
    end
  end

  @doc """
  Get Elixir-specific enforcement settings.
  """
  @spec get_elixir_enforcement(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_elixir_enforcement(user_id, project_id \\ nil) do
    case get_anti_pattern_config(user_id, project_id) do
      {:ok, config} ->
        {:ok,
         %{
           otp_enforcement_level: config.anti_patterns.otp_enforcement_level,
           functional_strictness: config.anti_patterns.functional_strictness,
           macro_hygiene_required: config.anti_patterns.macro_hygiene_required,
           concurrency_patterns_strict: determine_concurrency_strictness(config)
         }}

      error ->
        error
    end
  end

  @doc """
  Check if anti-pattern should block compilation/CI.
  """
  @spec should_block_build?(
          user_id :: binary(),
          pattern :: String.t(),
          project_id :: binary() | nil
        ) :: boolean()
  def should_block_build?(user_id, pattern, project_id \\ nil) do
    case get_anti_pattern_config(user_id, project_id) do
      {:ok, config} ->
        pattern_severity = Map.get(@severity_mappings, pattern, :warning)
        critical_pattern?(pattern_severity) and config.anti_patterns.block_on_critical

      {:error, _} ->
        false
    end
  end

  @doc """
  Get enabled anti-patterns for a category.
  """
  @spec get_enabled_patterns(
          user_id :: binary(),
          category :: atom(),
          project_id :: binary() | nil
        ) :: {:ok, list(String.t())} | {:error, String.t()}
  def get_enabled_patterns(user_id, category, project_id \\ nil)
      when category in @anti_pattern_categories do
    case get_anti_pattern_config(user_id, project_id) do
      {:ok, config} ->
        if category_enabled?(category, config) do
          patterns = Map.get(@anti_patterns, category, [])
          enabled_patterns = Enum.filter(patterns, &pattern_enabled?(user_id, &1, project_id))
          {:ok, enabled_patterns}
        else
          {:ok, []}
        end

      error ->
        error
    end
  end

  @doc """
  Get remediation configuration for anti-patterns.
  """
  @spec get_remediation_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_remediation_config(user_id, project_id \\ nil) do
    case get_anti_pattern_config(user_id, project_id) do
      {:ok, config} ->
        {:ok,
         %{
           auto_remediation_enabled: config.anti_patterns.auto_remediation_enabled,
           remediation_strategy: config.anti_patterns.remediation_strategy,
           approval_required: config.anti_patterns.approval_required,
           impact_analysis_required: config.anti_patterns.impact_analysis_required
         }}

      error ->
        error
    end
  end

  # Private functions

  defp resolve_anti_pattern_preferences(user_id, project_id) do
    base_preferences = [
      "code_quality.global.enabled",
      "code_quality.anti_patterns.enabled",
      "code_quality.anti_patterns.severity_mode",
      "code_quality.anti_patterns.code_patterns_enabled",
      "code_quality.anti_patterns.design_patterns_enabled",
      "code_quality.anti_patterns.process_patterns_enabled",
      "code_quality.anti_patterns.macro_patterns_enabled",
      "code_quality.anti_patterns.otp_enforcement_level",
      "code_quality.anti_patterns.functional_strictness",
      "code_quality.anti_patterns.macro_hygiene_required"
    ]

    # Add individual pattern preferences (24 patterns)
    pattern_preferences =
      @anti_patterns
      |> Enum.flat_map(fn {_category, patterns} -> patterns end)
      |> Enum.map(&"code_quality.anti_patterns.patterns.#{&1}")

    all_preferences = base_preferences ++ pattern_preferences

    case PreferenceResolver.resolve_batch(user_id, all_preferences, project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp validate_anti_pattern_configuration(raw_config) do
    case CodeQualityPreferenceValidator.validate_code_quality_consistency(raw_config) do
      :ok -> {:ok, raw_config}
      error -> error
    end
  end

  defp process_anti_pattern_configuration(raw_config) do
    # Extract pattern configurations
    pattern_configs =
      raw_config
      |> Enum.filter(fn {key, _value} -> String.contains?(key, "patterns.") end)
      |> Enum.into(%{}, fn {key, value} ->
        pattern_name = key |> String.split(".") |> List.last()
        {pattern_name, parse_boolean(value)}
      end)

    processed = %{
      global: %{
        enabled: parse_boolean(raw_config["code_quality.global.enabled"])
      },
      anti_patterns: %{
        enabled: parse_boolean(raw_config["code_quality.anti_patterns.enabled"]),
        severity_mode: raw_config["code_quality.anti_patterns.severity_mode"],
        code_patterns_enabled:
          parse_boolean(raw_config["code_quality.anti_patterns.code_patterns_enabled"]),
        design_patterns_enabled:
          parse_boolean(raw_config["code_quality.anti_patterns.design_patterns_enabled"]),
        process_patterns_enabled:
          parse_boolean(raw_config["code_quality.anti_patterns.process_patterns_enabled"]),
        macro_patterns_enabled:
          parse_boolean(raw_config["code_quality.anti_patterns.macro_patterns_enabled"]),
        otp_enforcement_level: raw_config["code_quality.anti_patterns.otp_enforcement_level"],
        functional_strictness: raw_config["code_quality.anti_patterns.functional_strictness"],
        macro_hygiene_required:
          parse_boolean(raw_config["code_quality.anti_patterns.macro_hygiene_required"]),
        auto_remediation_enabled: false,
        remediation_strategy: "manual",
        approval_required: true,
        impact_analysis_required: true,
        block_on_critical: true
      },
      patterns: pattern_configs
    }

    {:ok, processed}
  end

  defp pattern_category_enabled?(pattern, config) do
    category = find_pattern_category(pattern)

    case category do
      :code_patterns -> config.anti_patterns.code_patterns_enabled
      :design_patterns -> config.anti_patterns.design_patterns_enabled
      :process_patterns -> config.anti_patterns.process_patterns_enabled
      :macro_patterns -> config.anti_patterns.macro_patterns_enabled
      _ -> true
    end
  end

  defp category_enabled?(category, config) do
    case category do
      :code_patterns -> config.anti_patterns.code_patterns_enabled
      :design_patterns -> config.anti_patterns.design_patterns_enabled
      :process_patterns -> config.anti_patterns.process_patterns_enabled
      :macro_patterns -> config.anti_patterns.macro_patterns_enabled
    end
  end

  defp find_pattern_category(pattern) do
    Enum.find_value(@anti_patterns, fn {category, patterns} ->
      if pattern in patterns, do: category
    end) || :unknown
  end

  defp severity_level_allowed?(pattern, config) do
    pattern_severity = Map.get(@severity_mappings, pattern, :warning)
    threshold_severity = string_to_severity_atom(config.anti_patterns.severity_mode)

    severity_level_numeric(pattern_severity) >= severity_level_numeric(threshold_severity)
  end

  defp determine_concurrency_strictness(config) do
    case config.anti_patterns.otp_enforcement_level do
      "strict" -> true
      "moderate" -> config.anti_patterns.process_patterns_enabled
      "lenient" -> false
    end
  end

  defp critical_pattern?(severity) do
    severity in [:critical, :error]
  end

  defp string_to_severity_atom("info"), do: :info
  defp string_to_severity_atom("warning"), do: :warning
  defp string_to_severity_atom("error"), do: :error
  defp string_to_severity_atom("critical"), do: :critical
  defp string_to_severity_atom(_), do: :warning

  defp severity_level_numeric(:info), do: 1
  defp severity_level_numeric(:warning), do: 2
  defp severity_level_numeric(:error), do: 3
  defp severity_level_numeric(:critical), do: 4

  # Helper functions for type conversion
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: false
end
