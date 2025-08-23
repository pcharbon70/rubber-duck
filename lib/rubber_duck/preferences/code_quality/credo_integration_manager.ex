defmodule RubberDuck.Preferences.CodeQuality.CredoIntegrationManager do
  @moduledoc """
  Credo integration manager for configuring Credo static analysis.

  Manages Credo integration preferences including check enablement,
  custom configuration, severity overrides, and CI/CD integration.
  Provides seamless integration with Credo's configuration system
  while respecting user and project preferences.
  """

  require Logger

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Validators.CodeQualityPreferenceValidator

  @credo_check_categories [:consistency, :design, :readability, :refactor, :warning]

  @credo_checks %{
    consistency: [
      "Credo.Check.Consistency.ExceptionNames",
      "Credo.Check.Consistency.LineEndings",
      "Credo.Check.Consistency.ParameterPatternMatching",
      "Credo.Check.Consistency.SpaceAroundOperators",
      "Credo.Check.Consistency.SpaceInParentheses",
      "Credo.Check.Consistency.TabsOrSpaces"
    ],
    design: [
      "Credo.Check.Design.AliasUsage",
      "Credo.Check.Design.DuplicatedCode",
      "Credo.Check.Design.TagFIXME",
      "Credo.Check.Design.TagTODO"
    ],
    readability: [
      "Credo.Check.Readability.AliasOrder",
      "Credo.Check.Readability.FunctionNames",
      "Credo.Check.Readability.LargeNumbers",
      "Credo.Check.Readability.MaxLineLength",
      "Credo.Check.Readability.ModuleAttributeNames",
      "Credo.Check.Readability.ModuleDoc",
      "Credo.Check.Readability.ModuleNames",
      "Credo.Check.Readability.ParenthesesInCondition",
      "Credo.Check.Readability.ParenthesesOnZeroArityDefs",
      "Credo.Check.Readability.PredicateFunctionNames",
      "Credo.Check.Readability.PreferImplicitTry",
      "Credo.Check.Readability.RedundantBlankLines",
      "Credo.Check.Readability.Semicolons",
      "Credo.Check.Readability.SpaceAfterCommas",
      "Credo.Check.Readability.StringSigils",
      "Credo.Check.Readability.TrailingBlankLine",
      "Credo.Check.Readability.TrailingWhiteSpace",
      "Credo.Check.Readability.UnnecessaryAliasExpansion",
      "Credo.Check.Readability.VariableNames"
    ],
    refactor: [
      "Credo.Check.Refactor.ABCSize",
      "Credo.Check.Refactor.AppendSingleItem",
      "Credo.Check.Refactor.DoubleBooleanNegation",
      "Credo.Check.Refactor.MatchInCondition",
      "Credo.Check.Refactor.NegatedConditionsInUnless",
      "Credo.Check.Refactor.NegatedConditionsWithElse",
      "Credo.Check.Refactor.Nesting",
      "Credo.Check.Refactor.UnlessWithElse",
      "Credo.Check.Refactor.WithClauses"
    ],
    warning: [
      "Credo.Check.Warning.ApplicationConfigInModuleAttribute",
      "Credo.Check.Warning.BoolOperationOnSameValues",
      "Credo.Check.Warning.ExpensiveEmptyEnumCheck",
      "Credo.Check.Warning.IExPry",
      "Credo.Check.Warning.IoInspect",
      "Credo.Check.Warning.OperationOnSameValues",
      "Credo.Check.Warning.OperationWithConstantResult",
      "Credo.Check.Warning.RaiseInsideRescue",
      "Credo.Check.Warning.SpecWithStruct",
      "Credo.Check.Warning.WrongTestFileExtension"
    ]
  }

  @doc """
  Get Credo integration configuration for a user and optional project.
  """
  @spec get_credo_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_credo_config(user_id, project_id \\ nil) do
    with {:ok, raw_config} <- resolve_credo_preferences(user_id, project_id),
         {:ok, validated_config} <- validate_credo_configuration(raw_config),
         {:ok, processed_config} <- process_credo_configuration(validated_config) do
      {:ok, processed_config}
    else
      error ->
        Logger.warning("Failed to get Credo config for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to load Credo configuration"}
    end
  end

  @doc """
  Check if Credo analysis is enabled for a user/project.
  """
  @spec credo_enabled?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def credo_enabled?(user_id, project_id \\ nil) do
    case get_credo_config(user_id, project_id) do
      {:ok, config} -> config.global.enabled and config.credo.enabled
      {:error, _} -> false
    end
  end

  @doc """
  Generate Credo configuration file based on preferences.
  """
  @spec generate_credo_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def generate_credo_config(user_id, project_id \\ nil) do
    case get_credo_config(user_id, project_id) do
      {:ok, config} ->
        credo_config = %{
          configs: [
            %{
              name: "default",
              files: %{
                included: ["lib/", "src/", "test/", "web/", "apps/*/lib/", "apps/*/test/"],
                excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
              },
              plugins: [],
              requires: [],
              strict: config.credo.strict_mode,
              parse_timeout: 5000,
              color: true,
              checks: generate_checks_config(config)
            }
          ]
        }

        {:ok, credo_config}

      error ->
        error
    end
  end

  @doc """
  Get enabled Credo checks for a category.
  """
  @spec get_enabled_checks(
          user_id :: binary(),
          category :: atom(),
          project_id :: binary() | nil
        ) :: {:ok, list(String.t())} | {:error, String.t()}
  def get_enabled_checks(user_id, category, project_id \\ nil)
      when category in @credo_check_categories do
    case get_credo_config(user_id, project_id) do
      {:ok, config} ->
        if category_enabled?(category, config) do
          checks = Map.get(@credo_checks, category, [])
          {:ok, checks}
        else
          {:ok, []}
        end

      error ->
        error
    end
  end

  @doc """
  Check if auto-fix is enabled for Credo issues.
  """
  @spec auto_fix_enabled?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def auto_fix_enabled?(user_id, project_id \\ nil) do
    case get_credo_config(user_id, project_id) do
      {:ok, config} -> config.credo.auto_fix_enabled
      {:error, _} -> false
    end
  end

  @doc """
  Get CI/CD integration settings for Credo.
  """
  @spec get_ci_integration_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_ci_integration_config(user_id, project_id \\ nil) do
    case get_credo_config(user_id, project_id) do
      {:ok, config} ->
        {:ok,
         %{
           ci_integration: config.credo.ci_integration,
           strict_mode: config.credo.strict_mode,
           fail_on_issues: config.credo.fail_on_issues,
           format: "flycheck"
         }}

      error ->
        error
    end
  end

  # Private functions

  defp resolve_credo_preferences(user_id, project_id) do
    credo_preferences = [
      "code_quality.global.enabled",
      "code_quality.credo.enabled",
      "code_quality.credo.strict_mode",
      "code_quality.credo.config_file",
      "code_quality.credo.consistency_checks",
      "code_quality.credo.design_checks",
      "code_quality.credo.readability_checks",
      "code_quality.credo.refactor_checks",
      "code_quality.credo.warning_checks",
      "code_quality.credo.auto_fix_enabled",
      "code_quality.credo.editor_integration",
      "code_quality.credo.ci_integration"
    ]

    case PreferenceResolver.resolve_batch(user_id, credo_preferences, project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp validate_credo_configuration(raw_config) do
    case CodeQualityPreferenceValidator.validate_code_quality_consistency(raw_config) do
      :ok -> {:ok, raw_config}
      error -> error
    end
  end

  defp process_credo_configuration(raw_config) do
    processed = %{
      global: %{
        enabled: parse_boolean(raw_config["code_quality.global.enabled"])
      },
      credo: %{
        enabled: parse_boolean(raw_config["code_quality.credo.enabled"]),
        strict_mode: parse_boolean(raw_config["code_quality.credo.strict_mode"]),
        config_file: raw_config["code_quality.credo.config_file"],
        consistency_checks: parse_boolean(raw_config["code_quality.credo.consistency_checks"]),
        design_checks: parse_boolean(raw_config["code_quality.credo.design_checks"]),
        readability_checks: parse_boolean(raw_config["code_quality.credo.readability_checks"]),
        refactor_checks: parse_boolean(raw_config["code_quality.credo.refactor_checks"]),
        warning_checks: parse_boolean(raw_config["code_quality.credo.warning_checks"]),
        auto_fix_enabled: parse_boolean(raw_config["code_quality.credo.auto_fix_enabled"]),
        editor_integration: parse_boolean(raw_config["code_quality.credo.editor_integration"]),
        ci_integration: parse_boolean(raw_config["code_quality.credo.ci_integration"]),
        fail_on_issues: false
      }
    }

    {:ok, processed}
  end

  defp generate_checks_config(config) do
    enabled_checks = []

    enabled_checks =
      if config.credo.consistency_checks do
        enabled_checks ++ generate_category_checks(:consistency)
      else
        enabled_checks
      end

    enabled_checks =
      if config.credo.design_checks do
        enabled_checks ++ generate_category_checks(:design)
      else
        enabled_checks
      end

    enabled_checks =
      if config.credo.readability_checks do
        enabled_checks ++ generate_category_checks(:readability)
      else
        enabled_checks
      end

    enabled_checks =
      if config.credo.refactor_checks do
        enabled_checks ++ generate_category_checks(:refactor)
      else
        enabled_checks
      end

    enabled_checks =
      if config.credo.warning_checks do
        enabled_checks ++ generate_category_checks(:warning)
      else
        enabled_checks
      end

    enabled_checks
  end

  defp generate_category_checks(category) do
    checks = Map.get(@credo_checks, category, [])

    Enum.map(checks, fn check ->
      {check, []}
    end)
  end

  defp category_enabled?(category, config) do
    case category do
      :consistency -> config.credo.consistency_checks
      :design -> config.credo.design_checks
      :readability -> config.credo.readability_checks
      :refactor -> config.credo.refactor_checks
      :warning -> config.credo.warning_checks
    end
  end

  # Helper functions for type conversion
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: false
end
