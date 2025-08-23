defmodule RubberDuck.Preferences.Validators.CodeQualityPreferenceValidator do
  @moduledoc """
  Code quality specific preference validation rules.

  Implements validation logic specific to code quality and analysis preferences,
  including detector configurations, refactoring agent settings, anti-pattern
  detection controls, and Credo integration parameters.
  """

  @severity_levels ["info", "warning", "error", "critical"]
  @performance_modes ["fast", "balanced", "thorough"]
  @analysis_depths ["shallow", "medium", "deep"]
  @aggressiveness_levels ["conservative", "moderate", "aggressive"]
  @risk_levels ["low", "medium", "high"]
  @enforcement_levels ["lenient", "moderate", "strict"]

  @doc """
  Validate severity level preference.
  """
  @spec validate_severity_level(value :: any()) :: :ok | {:error, String.t()}
  def validate_severity_level(value) when is_binary(value) do
    if value in @severity_levels do
      :ok
    else
      {:error, "Invalid severity level: #{value}. Supported: #{inspect(@severity_levels)}"}
    end
  end

  def validate_severity_level(_value) do
    {:error, "Severity level must be a string"}
  end

  @doc """
  Validate performance mode preference.
  """
  @spec validate_performance_mode(value :: any()) :: :ok | {:error, String.t()}
  def validate_performance_mode(value) when is_binary(value) do
    if value in @performance_modes do
      :ok
    else
      {:error, "Invalid performance mode: #{value}. Supported: #{inspect(@performance_modes)}"}
    end
  end

  def validate_performance_mode(_value) do
    {:error, "Performance mode must be a string"}
  end

  @doc """
  Validate analysis depth preference.
  """
  @spec validate_analysis_depth(value :: any()) :: :ok | {:error, String.t()}
  def validate_analysis_depth(value) when is_binary(value) do
    if value in @analysis_depths do
      :ok
    else
      {:error, "Invalid analysis depth: #{value}. Supported: #{inspect(@analysis_depths)}"}
    end
  end

  def validate_analysis_depth(_value) do
    {:error, "Analysis depth must be a string"}
  end

  @doc """
  Validate confidence threshold preference.
  """
  @spec validate_confidence_threshold(value :: any()) :: :ok | {:error, String.t()}
  def validate_confidence_threshold(value) when is_float(value) or is_integer(value) do
    numeric_value = if is_integer(value), do: value / 1.0, else: value

    cond do
      numeric_value < 0.0 ->
        {:error, "Confidence threshold must be non-negative"}

      numeric_value > 1.0 ->
        {:error, "Confidence threshold must be <= 1.0"}

      true ->
        :ok
    end
  end

  def validate_confidence_threshold(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> validate_confidence_threshold(float_value)
      _ -> {:error, "Confidence threshold must be a valid number"}
    end
  end

  def validate_confidence_threshold(_value) do
    {:error, "Confidence threshold must be a number or numeric string"}
  end

  @doc """
  Validate test coverage requirement preference.
  """
  @spec validate_test_coverage(value :: any()) :: :ok | {:error, String.t()}
  def validate_test_coverage(value) when is_float(value) or is_integer(value) do
    numeric_value = if is_integer(value), do: value / 1.0, else: value

    cond do
      numeric_value < 0.0 ->
        {:error, "Test coverage must be non-negative"}

      numeric_value > 1.0 ->
        {:error, "Test coverage must be <= 1.0 (100%)"}

      true ->
        :ok
    end
  end

  def validate_test_coverage(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> validate_test_coverage(float_value)
      _ -> {:error, "Test coverage must be a valid number"}
    end
  end

  def validate_test_coverage(_value) do
    {:error, "Test coverage must be a number or numeric string"}
  end

  @doc """
  Validate aggressiveness level preference.
  """
  @spec validate_aggressiveness_level(value :: any()) :: :ok | {:error, String.t()}
  def validate_aggressiveness_level(value) when is_binary(value) do
    if value in @aggressiveness_levels do
      :ok
    else
      {:error,
       "Invalid aggressiveness level: #{value}. Supported: #{inspect(@aggressiveness_levels)}"}
    end
  end

  def validate_aggressiveness_level(_value) do
    {:error, "Aggressiveness level must be a string"}
  end

  @doc """
  Validate risk level preference.
  """
  @spec validate_risk_level(value :: any()) :: :ok | {:error, String.t()}
  def validate_risk_level(value) when is_binary(value) do
    if value in @risk_levels do
      :ok
    else
      {:error, "Invalid risk level: #{value}. Supported: #{inspect(@risk_levels)}"}
    end
  end

  def validate_risk_level(_value) do
    {:error, "Risk level must be a string"}
  end

  @doc """
  Validate enforcement level preference.
  """
  @spec validate_enforcement_level(value :: any()) :: :ok | {:error, String.t()}
  def validate_enforcement_level(value) when is_binary(value) do
    if value in @enforcement_levels do
      :ok
    else
      {:error, "Invalid enforcement level: #{value}. Supported: #{inspect(@enforcement_levels)}"}
    end
  end

  def validate_enforcement_level(_value) do
    {:error, "Enforcement level must be a string"}
  end

  @doc """
  Validate code quality configuration consistency across related preferences.
  """
  @spec validate_code_quality_consistency(preferences :: map()) :: :ok | {:error, String.t()}
  def validate_code_quality_consistency(preferences) do
    with :ok <- validate_global_consistency(preferences),
         :ok <- validate_smell_detection_consistency(preferences),
         :ok <- validate_refactoring_consistency(preferences),
         :ok <- validate_credo_consistency(preferences) do
      :ok
    end
  end

  # Private helper functions

  defp validate_global_consistency(preferences) do
    global_enabled = Map.get(preferences, "code_quality.global.enabled", "true")
    auto_analysis = Map.get(preferences, "code_quality.global.auto_analysis_enabled", "true")

    if global_enabled == "false" and auto_analysis == "true" do
      {:error, "Auto analysis cannot be enabled when global code quality is disabled"}
    else
      :ok
    end
  end

  defp validate_smell_detection_consistency(preferences) do
    smells_enabled = Map.get(preferences, "code_quality.smells.enabled", "true")
    auto_fix = Map.get(preferences, "code_quality.smells.auto_fix_enabled", "false")

    if smells_enabled == "false" and auto_fix == "true" do
      {:error, "Auto-fix cannot be enabled when smell detection is disabled"}
    else
      :ok
    end
  end

  defp validate_refactoring_consistency(preferences) do
    refactoring_enabled = Map.get(preferences, "code_quality.refactoring.enabled", "true")
    auto_apply = Map.get(preferences, "code_quality.refactoring.auto_apply_enabled", "false")

    test_coverage =
      preferences
      |> Map.get("code_quality.refactoring.test_coverage_required", "0.8")
      |> parse_float()

    cond do
      refactoring_enabled == "false" and auto_apply == "true" ->
        {:error, "Auto-apply refactoring cannot be enabled when refactoring is disabled"}

      (auto_apply == "true" and test_coverage) && test_coverage < 0.5 ->
        {:error, "Auto-apply refactoring requires test coverage >= 50%"}

      true ->
        :ok
    end
  end

  defp validate_credo_consistency(preferences) do
    credo_enabled = Map.get(preferences, "code_quality.credo.enabled", "true")
    auto_fix = Map.get(preferences, "code_quality.credo.auto_fix_enabled", "false")
    strict_mode = Map.get(preferences, "code_quality.credo.strict_mode", "false")

    cond do
      credo_enabled == "false" and auto_fix == "true" ->
        {:error, "Credo auto-fix cannot be enabled when Credo is disabled"}

      credo_enabled == "false" and strict_mode == "true" ->
        {:error, "Credo strict mode cannot be enabled when Credo is disabled"}

      true ->
        :ok
    end
  end

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> float_value
      _ -> nil
    end
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1.0
  defp parse_float(_), do: nil
end
