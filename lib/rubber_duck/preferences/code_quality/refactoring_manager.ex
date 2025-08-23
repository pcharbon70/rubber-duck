defmodule RubberDuck.Preferences.CodeQuality.RefactoringManager do
  @moduledoc """
  Refactoring agent manager for controlling automated refactoring.

  Manages refactoring agent preferences including agent enablement,
  aggressiveness settings, safety requirements, and approval workflows.
  Integrates with test coverage and quality gates for safe refactoring.
  """

  require Logger

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Validators.CodeQualityPreferenceValidator

  @refactoring_categories [
    :structural,
    :naming,
    :organization,
    :patterns,
    :elixir_specific,
    :quality
  ]

  @refactoring_agents %{
    structural: [
      "extract_function",
      "inline_function",
      "extract_variable",
      "inline_variable",
      "move_method",
      "move_field",
      "extract_class",
      "inline_class",
      "extract_module"
    ],
    naming: [
      "rename_method",
      "rename_variable",
      "rename_module",
      "improve_naming_consistency",
      "apply_naming_conventions",
      "standardize_terminology"
    ],
    organization: [
      "organize_imports",
      "remove_unused_imports",
      "sort_members",
      "group_methods",
      "split_large_class",
      "consolidate_conditionals",
      "merge_duplicate_code"
    ],
    patterns: [
      "introduce_factory",
      "introduce_builder",
      "introduce_strategy",
      "introduce_observer",
      "introduce_decorator",
      "introduce_adapter"
    ],
    elixir_specific: [
      "pipe_chain_optimization",
      "pattern_match_optimization",
      "with_statement_refactor",
      "genserver_refactor",
      "supervisor_refactor",
      "process_refactor",
      "ecto_query_optimization",
      "phoenix_controller_refactor",
      "liveview_optimization"
    ],
    quality: [
      "improve_readability",
      "reduce_complexity",
      "enhance_performance",
      "add_documentation",
      "improve_error_handling",
      "add_type_specs",
      "optimize_memory_usage",
      "reduce_coupling",
      "increase_cohesion"
    ]
  }

  @risk_levels %{
    "extract_function" => :low,
    "inline_variable" => :low,
    "rename_variable" => :low,
    "organize_imports" => :low,
    "remove_unused_imports" => :low,
    "add_documentation" => :low,
    "improve_naming_consistency" => :medium,
    "split_large_class" => :medium,
    "extract_module" => :medium,
    "introduce_strategy" => :high,
    "genserver_refactor" => :high,
    "ecto_query_optimization" => :high
  }

  @doc """
  Get refactoring configuration for a user and optional project.
  """
  @spec get_refactoring_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_refactoring_config(user_id, project_id \\ nil) do
    with {:ok, raw_config} <- resolve_refactoring_preferences(user_id, project_id),
         {:ok, validated_config} <- validate_refactoring_configuration(raw_config),
         {:ok, processed_config} <- process_refactoring_configuration(validated_config) do
      {:ok, processed_config}
    else
      error ->
        Logger.warning("Failed to get refactoring config for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to load refactoring configuration"}
    end
  end

  @doc """
  Check if refactoring is enabled for a user/project.
  """
  @spec refactoring_enabled?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def refactoring_enabled?(user_id, project_id \\ nil) do
    case get_refactoring_config(user_id, project_id) do
      {:ok, config} -> config.global.enabled and config.refactoring.enabled
      {:error, _} -> false
    end
  end

  @doc """
  Check if specific refactoring agent is enabled.
  """
  @spec agent_enabled?(
          user_id :: binary(),
          agent :: String.t(),
          project_id :: binary() | nil
        ) :: boolean()
  def agent_enabled?(user_id, agent, project_id \\ nil) do
    case get_refactoring_config(user_id, project_id) do
      {:ok, config} ->
        category_enabled = agent_category_enabled?(agent, config)
        individual_enabled = Map.get(config.agents, agent, true)
        risk_allowed = risk_level_allowed?(agent, config)

        category_enabled and individual_enabled and risk_allowed

      {:error, _} ->
        false
    end
  end

  @doc """
  Check if refactoring can be auto-applied based on risk and coverage.
  """
  @spec can_auto_apply?(
          user_id :: binary(),
          agent :: String.t(),
          test_coverage :: float(),
          project_id :: binary() | nil
        ) :: boolean()
  def can_auto_apply?(user_id, agent, test_coverage, project_id \\ nil) do
    case get_refactoring_config(user_id, project_id) do
      {:ok, config} ->
        config.refactoring.auto_apply_enabled and
          agent_enabled?(user_id, agent, project_id) and
          test_coverage >= config.refactoring.test_coverage_required and
          meets_auto_apply_criteria?(agent, config)

      {:error, _} ->
        false
    end
  end

  @doc """
  Get enabled refactoring agents for a category.
  """
  @spec get_enabled_agents(
          user_id :: binary(),
          category :: atom(),
          project_id :: binary() | nil
        ) :: {:ok, list(String.t())} | {:error, String.t()}
  def get_enabled_agents(user_id, category, project_id \\ nil)
      when category in @refactoring_categories do
    case get_refactoring_config(user_id, project_id) do
      {:ok, config} ->
        if category_enabled?(category, config) do
          agents = Map.get(@refactoring_agents, category, [])
          enabled_agents = Enum.filter(agents, &agent_enabled?(user_id, &1, project_id))
          {:ok, enabled_agents}
        else
          {:ok, []}
        end

      error ->
        error
    end
  end

  @doc """
  Get safety requirements for refactoring operations.
  """
  @spec get_safety_requirements(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_safety_requirements(user_id, project_id \\ nil) do
    case get_refactoring_config(user_id, project_id) do
      {:ok, config} ->
        {:ok,
         %{
           test_coverage_required: config.refactoring.test_coverage_required,
           approval_required_for: config.refactoring.approval_required_for,
           risk_threshold: config.refactoring.risk_threshold,
           mode: config.refactoring.mode
         }}

      error ->
        error
    end
  end

  # Private functions

  defp resolve_refactoring_preferences(user_id, project_id) do
    base_preferences = [
      "code_quality.global.enabled",
      "code_quality.refactoring.enabled",
      "code_quality.refactoring.mode",
      "code_quality.refactoring.risk_threshold",
      "code_quality.refactoring.structural_enabled",
      "code_quality.refactoring.naming_enabled",
      "code_quality.refactoring.design_patterns_enabled",
      "code_quality.refactoring.auto_apply_enabled",
      "code_quality.refactoring.approval_required_for",
      "code_quality.refactoring.test_coverage_required"
    ]

    # Add individual agent preferences (first 30 agents)
    agent_preferences =
      @refactoring_agents
      |> Enum.flat_map(fn {_category, agents} -> agents end)
      |> Enum.take(30)
      |> Enum.map(&"code_quality.refactoring.agents.#{&1}")

    all_preferences = base_preferences ++ agent_preferences

    case PreferenceResolver.resolve_batch(user_id, all_preferences, project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp validate_refactoring_configuration(raw_config) do
    case CodeQualityPreferenceValidator.validate_code_quality_consistency(raw_config) do
      :ok -> {:ok, raw_config}
      error -> error
    end
  end

  defp process_refactoring_configuration(raw_config) do
    # Extract agent configurations
    agent_configs =
      raw_config
      |> Enum.filter(fn {key, _value} -> String.contains?(key, "agents.") end)
      |> Enum.into(%{}, fn {key, value} ->
        agent_name = key |> String.split(".") |> List.last()
        {agent_name, parse_boolean(value)}
      end)

    processed = %{
      global: %{
        enabled: parse_boolean(raw_config["code_quality.global.enabled"])
      },
      refactoring: %{
        enabled: parse_boolean(raw_config["code_quality.refactoring.enabled"]),
        mode: raw_config["code_quality.refactoring.mode"],
        risk_threshold: raw_config["code_quality.refactoring.risk_threshold"],
        structural_enabled:
          parse_boolean(raw_config["code_quality.refactoring.structural_enabled"]),
        naming_enabled: parse_boolean(raw_config["code_quality.refactoring.naming_enabled"]),
        design_patterns_enabled:
          parse_boolean(raw_config["code_quality.refactoring.design_patterns_enabled"]),
        auto_apply_enabled:
          parse_boolean(raw_config["code_quality.refactoring.auto_apply_enabled"]),
        approval_required_for: raw_config["code_quality.refactoring.approval_required_for"],
        test_coverage_required:
          parse_float(raw_config["code_quality.refactoring.test_coverage_required"])
      },
      agents: agent_configs
    }

    {:ok, processed}
  end

  defp agent_category_enabled?(agent, config) do
    category = find_agent_category(agent)

    case category do
      :structural -> config.refactoring.structural_enabled
      :naming -> config.refactoring.naming_enabled
      :organization -> true
      :patterns -> config.refactoring.design_patterns_enabled
      :elixir_specific -> true
      :quality -> true
      _ -> true
    end
  end

  defp category_enabled?(category, config) do
    case category do
      :structural -> config.refactoring.structural_enabled
      :naming -> config.refactoring.naming_enabled
      :organization -> true
      :patterns -> config.refactoring.design_patterns_enabled
      :elixir_specific -> true
      :quality -> true
    end
  end

  defp find_agent_category(agent) do
    Enum.find_value(@refactoring_agents, fn {category, agents} ->
      if agent in agents, do: category
    end) || :unknown
  end

  defp risk_level_allowed?(agent, config) do
    agent_risk = Map.get(@risk_levels, agent, :medium)
    threshold_risk = string_to_risk_atom(config.refactoring.risk_threshold)

    risk_level_numeric(agent_risk) <= risk_level_numeric(threshold_risk)
  end

  defp meets_auto_apply_criteria?(agent, config) do
    agent_risk = Map.get(@risk_levels, agent, :medium)
    approval_threshold = string_to_risk_atom(config.refactoring.approval_required_for)

    risk_level_numeric(agent_risk) < risk_level_numeric(approval_threshold)
  end

  defp string_to_risk_atom("low"), do: :low
  defp string_to_risk_atom("medium"), do: :medium
  defp string_to_risk_atom("high"), do: :high
  defp string_to_risk_atom("low_risk"), do: :low
  defp string_to_risk_atom("medium_risk"), do: :medium
  defp string_to_risk_atom("high_risk"), do: :high
  defp string_to_risk_atom("all"), do: :none
  defp string_to_risk_atom(_), do: :medium

  defp risk_level_numeric(:low), do: 1
  defp risk_level_numeric(:medium), do: 2
  defp risk_level_numeric(:high), do: 3
  defp risk_level_numeric(:none), do: 0

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
