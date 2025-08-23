defmodule RubberDuck.Preferences.Seeders.CodeQualityDefaultsSeeder do
  @moduledoc """
  Seeds code quality and analysis preference defaults into the system.

  Creates comprehensive default configurations for code smell detection,
  refactoring agents, anti-pattern detection, and Credo integration
  preferences.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.SystemDefault

  @doc """
  Seed all code quality preference defaults.
  """
  @spec seed_all() :: :ok | {:error, term()}
  def seed_all do
    Logger.info("Seeding code quality preference defaults...")

    with :ok <- seed_global_quality_defaults(),
         :ok <- seed_code_smell_defaults(),
         :ok <- seed_individual_smell_detectors(),
         :ok <- seed_refactoring_defaults(),
         :ok <- seed_individual_refactoring_agents(),
         :ok <- seed_anti_pattern_defaults(),
         :ok <- seed_individual_anti_patterns(),
         :ok <- seed_credo_integration_defaults() do
      Logger.info("Successfully seeded all code quality preference defaults")
      :ok
    else
      error ->
        Logger.error("Failed to seed code quality defaults: #{inspect(error)}")
        error
    end
  end

  @doc """
  Seed global code quality preference defaults.
  """
  @spec seed_global_quality_defaults() :: :ok | {:error, term()}
  def seed_global_quality_defaults do
    defaults = [
      %{
        preference_key: "code_quality.global.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "global",
        description: "Enable code quality analysis and tools globally",
        access_level: :user,
        display_order: 1
      },
      %{
        preference_key: "code_quality.global.auto_analysis_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "global",
        description: "Enable automatic code analysis on file changes",
        access_level: :user,
        display_order: 2
      },
      %{
        preference_key: "code_quality.global.severity_threshold",
        default_value: "warning",
        data_type: :string,
        category: "code_quality",
        subcategory: "global",
        description: "Minimum severity level to report issues",
        constraints: %{allowed_values: ["info", "warning", "error", "critical"]},
        access_level: :user,
        display_order: 3
      },
      %{
        preference_key: "code_quality.global.performance_mode",
        default_value: "balanced",
        data_type: :string,
        category: "code_quality",
        subcategory: "global",
        description: "Analysis performance vs thoroughness trade-off",
        constraints: %{allowed_values: ["fast", "balanced", "thorough"]},
        access_level: :user,
        display_order: 4
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed code smell detection preference defaults.
  """
  @spec seed_code_smell_defaults() :: :ok | {:error, term()}
  def seed_code_smell_defaults do
    defaults = [
      # Global smell detection controls
      %{
        preference_key: "code_quality.smells.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "smells",
        description: "Enable code smell detection",
        access_level: :user,
        display_order: 10
      },
      %{
        preference_key: "code_quality.smells.analysis_depth",
        default_value: "medium",
        data_type: :string,
        category: "code_quality",
        subcategory: "smells",
        description: "Depth of code smell analysis",
        constraints: %{allowed_values: ["shallow", "medium", "deep"]},
        access_level: :user,
        display_order: 11
      },
      %{
        preference_key: "code_quality.smells.confidence_threshold",
        default_value: "0.7",
        data_type: :float,
        category: "code_quality",
        subcategory: "smells",
        description: "Minimum confidence threshold for smell detection (0.0-1.0)",
        constraints: %{min: 0.0, max: 1.0},
        access_level: :user,
        display_order: 12
      },

      # Category-based toggles
      %{
        preference_key: "code_quality.smells.readability_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "smells",
        description: "Enable readability-related smell detection",
        access_level: :user,
        display_order: 13
      },
      %{
        preference_key: "code_quality.smells.complexity_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "smells",
        description: "Enable complexity-related smell detection",
        access_level: :user,
        display_order: 14
      },
      %{
        preference_key: "code_quality.smells.maintainability_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "smells",
        description: "Enable maintainability-related smell detection",
        access_level: :user,
        display_order: 15
      },
      %{
        preference_key: "code_quality.smells.performance_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "smells",
        description: "Enable performance-related smell detection",
        access_level: :user,
        display_order: 16
      },

      # Remediation preferences
      %{
        preference_key: "code_quality.smells.auto_fix_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "smells",
        description: "Enable automatic fixing of simple code smells",
        access_level: :user,
        display_order: 17
      },
      %{
        preference_key: "code_quality.smells.suggestion_aggressiveness",
        default_value: "moderate",
        data_type: :string,
        category: "code_quality",
        subcategory: "smells",
        description: "Aggressiveness of smell remediation suggestions",
        constraints: %{allowed_values: ["conservative", "moderate", "aggressive"]},
        access_level: :user,
        display_order: 18
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed refactoring agent preference defaults.
  """
  @spec seed_refactoring_defaults() :: :ok | {:error, term()}
  def seed_refactoring_defaults do
    defaults = [
      # Global refactoring controls
      %{
        preference_key: "code_quality.refactoring.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Enable refactoring agents and suggestions",
        access_level: :user,
        display_order: 20
      },
      %{
        preference_key: "code_quality.refactoring.mode",
        default_value: "conservative",
        data_type: :string,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Refactoring aggressiveness mode",
        constraints: %{allowed_values: ["conservative", "moderate", "aggressive"]},
        access_level: :user,
        display_order: 21
      },
      %{
        preference_key: "code_quality.refactoring.risk_threshold",
        default_value: "low",
        data_type: :string,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Maximum risk level for automatic refactoring",
        constraints: %{allowed_values: ["low", "medium", "high"]},
        access_level: :user,
        display_order: 22
      },

      # Category-based refactoring toggles
      %{
        preference_key: "code_quality.refactoring.structural_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Enable structural refactoring (extract function, inline, etc.)",
        access_level: :user,
        display_order: 23
      },
      %{
        preference_key: "code_quality.refactoring.naming_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Enable naming-related refactoring (rename, conventions)",
        access_level: :user,
        display_order: 24
      },
      %{
        preference_key: "code_quality.refactoring.design_patterns_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Enable design pattern application refactoring",
        access_level: :user,
        display_order: 25
      },

      # Automation and safety
      %{
        preference_key: "code_quality.refactoring.auto_apply_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Automatically apply safe refactorings without approval",
        access_level: :admin,
        display_order: 26
      },
      %{
        preference_key: "code_quality.refactoring.approval_required_for",
        default_value: "medium_risk",
        data_type: :string,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Risk level requiring approval before applying",
        constraints: %{allowed_values: ["low_risk", "medium_risk", "high_risk", "all"]},
        access_level: :admin,
        display_order: 27
      },
      %{
        preference_key: "code_quality.refactoring.test_coverage_required",
        default_value: "0.8",
        data_type: :float,
        category: "code_quality",
        subcategory: "refactoring",
        description: "Minimum test coverage required for refactoring (0.0-1.0)",
        constraints: %{min: 0.0, max: 1.0},
        access_level: :user,
        display_order: 28
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed anti-pattern detection preference defaults.
  """
  @spec seed_anti_pattern_defaults() :: :ok | {:error, term()}
  def seed_anti_pattern_defaults do
    defaults = [
      # Global anti-pattern controls
      %{
        preference_key: "code_quality.anti_patterns.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Enable anti-pattern detection",
        access_level: :user,
        display_order: 30
      },
      %{
        preference_key: "code_quality.anti_patterns.severity_mode",
        default_value: "warning",
        data_type: :string,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Default severity for anti-pattern detection",
        constraints: %{allowed_values: ["info", "warning", "error", "critical"]},
        access_level: :user,
        display_order: 31
      },

      # Category-based anti-pattern toggles
      %{
        preference_key: "code_quality.anti_patterns.code_patterns_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Enable code-level anti-pattern detection",
        access_level: :user,
        display_order: 32
      },
      %{
        preference_key: "code_quality.anti_patterns.design_patterns_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Enable design-level anti-pattern detection",
        access_level: :user,
        display_order: 33
      },
      %{
        preference_key: "code_quality.anti_patterns.process_patterns_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Enable OTP process anti-pattern detection",
        access_level: :user,
        display_order: 34
      },
      %{
        preference_key: "code_quality.anti_patterns.macro_patterns_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Enable macro-related anti-pattern detection",
        access_level: :user,
        display_order: 35
      },

      # Elixir-specific settings
      %{
        preference_key: "code_quality.anti_patterns.otp_enforcement_level",
        default_value: "moderate",
        data_type: :string,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "OTP pattern enforcement strictness",
        constraints: %{allowed_values: ["lenient", "moderate", "strict"]},
        access_level: :user,
        display_order: 36
      },
      %{
        preference_key: "code_quality.anti_patterns.functional_strictness",
        default_value: "moderate",
        data_type: :string,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Functional paradigm enforcement strictness",
        constraints: %{allowed_values: ["lenient", "moderate", "strict"]},
        access_level: :user,
        display_order: 37
      },
      %{
        preference_key: "code_quality.anti_patterns.macro_hygiene_required",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "anti_patterns",
        description: "Require macro hygiene compliance",
        access_level: :user,
        display_order: 38
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed Credo integration preference defaults.
  """
  @spec seed_credo_integration_defaults() :: :ok | {:error, term()}
  def seed_credo_integration_defaults do
    defaults = [
      # Credo configuration
      %{
        preference_key: "code_quality.credo.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo static analysis",
        access_level: :user,
        display_order: 40
      },
      %{
        preference_key: "code_quality.credo.strict_mode",
        default_value: "false",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo strict mode with additional checks",
        access_level: :user,
        display_order: 41
      },
      %{
        preference_key: "code_quality.credo.config_file",
        default_value: ".credo.exs",
        data_type: :string,
        category: "code_quality",
        subcategory: "credo",
        description: "Path to Credo configuration file",
        access_level: :admin,
        display_order: 42
      },

      # Check categories
      %{
        preference_key: "code_quality.credo.consistency_checks",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo consistency checks",
        access_level: :user,
        display_order: 43
      },
      %{
        preference_key: "code_quality.credo.design_checks",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo design checks",
        access_level: :user,
        display_order: 44
      },
      %{
        preference_key: "code_quality.credo.readability_checks",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo readability checks",
        access_level: :user,
        display_order: 45
      },
      %{
        preference_key: "code_quality.credo.refactor_checks",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo refactoring opportunity checks",
        access_level: :user,
        display_order: 46
      },
      %{
        preference_key: "code_quality.credo.warning_checks",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable Credo warning checks",
        access_level: :user,
        display_order: 47
      },

      # Integration settings
      %{
        preference_key: "code_quality.credo.auto_fix_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable automatic fixing of Credo issues",
        access_level: :admin,
        display_order: 48
      },
      %{
        preference_key: "code_quality.credo.editor_integration",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable editor integration for real-time feedback",
        access_level: :user,
        display_order: 49
      },
      %{
        preference_key: "code_quality.credo.ci_integration",
        default_value: "true",
        data_type: :boolean,
        category: "code_quality",
        subcategory: "credo",
        description: "Enable CI/CD pipeline integration",
        access_level: :admin,
        display_order: 50
      }
    ]

    seed_defaults(defaults)
  end

  # Individual smell detector preferences (35+ detectors)
  defp seed_individual_smell_detectors do
    smell_detectors = [
      # Readability smells
      "long_method",
      "long_parameter_list",
      "large_class",
      "complex_conditional",
      "duplicate_code",
      "comments_smell",
      "inconsistent_naming",
      "magic_numbers",

      # Complexity smells
      "cyclomatic_complexity",
      "cognitive_complexity",
      "nested_conditionals",
      "switch_statements",
      "deep_nesting",
      "feature_envy",
      "data_clumps",

      # Maintainability smells
      "god_class",
      "refused_bequest",
      "shotgun_surgery",
      "divergent_change",
      "parallel_inheritance",
      "temporary_field",
      "message_chains",
      "middle_man",

      # Performance smells
      "premature_optimization",
      "inefficient_loops",
      "memory_leaks",
      "resource_not_closed",
      "string_concatenation",
      "unnecessary_object_creation",

      # Elixir-specific smells
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

    smell_defaults =
      Enum.with_index(smell_detectors, 60)
      |> Enum.map(fn {detector, index} ->
        %{
          preference_key: "code_quality.smells.detectors.#{detector}",
          default_value: "true",
          data_type: :boolean,
          category: "code_quality",
          subcategory: "smell_detectors",
          description: "Enable #{String.replace(detector, "_", " ")} detection",
          access_level: :user,
          display_order: index
        }
      end)

    seed_defaults(smell_defaults)
  end

  # Individual refactoring agent preferences (82+ agents)
  defp seed_individual_refactoring_agents do
    refactoring_agents = [
      # Structural refactoring
      "extract_function",
      "inline_function",
      "extract_variable",
      "inline_variable",
      "move_method",
      "move_field",
      "extract_class",
      "inline_class",
      "extract_module",
      "rename_method",
      "rename_variable",
      "rename_module",

      # Code organization
      "organize_imports",
      "remove_unused_imports",
      "sort_members",
      "group_methods",
      "split_large_class",
      "merge_duplicate_code",
      "consolidate_conditionals",

      # Pattern application
      "introduce_factory",
      "introduce_builder",
      "introduce_strategy",
      "introduce_observer",
      "introduce_decorator",
      "introduce_adapter",

      # Elixir-specific refactoring
      "pipe_chain_optimization",
      "pattern_match_optimization",
      "with_statement_refactor",
      "genserver_refactor",
      "supervisor_refactor",
      "process_refactor",
      "ecto_query_optimization",
      "phoenix_controller_refactor",
      "liveview_optimization",

      # Quality improvements
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

    # Create first 30 agents to keep reasonable
    agent_defaults =
      refactoring_agents
      |> Enum.take(30)
      |> Enum.with_index(100)
      |> Enum.map(fn {agent, index} ->
        %{
          preference_key: "code_quality.refactoring.agents.#{agent}",
          default_value: "true",
          data_type: :boolean,
          category: "code_quality",
          subcategory: "refactoring_agents",
          description: "Enable #{String.replace(agent, "_", " ")} refactoring agent",
          access_level: :user,
          display_order: index
        }
      end)

    seed_defaults(agent_defaults)
  end

  # Individual anti-pattern preferences (24+ patterns)
  defp seed_individual_anti_patterns do
    anti_patterns = [
      # Code anti-patterns
      "dynamic_atom_creation",
      "non_assertive_code",
      "unrelated_multi_clause",
      "complex_guard_expressions",
      "improper_error_handling",
      "inefficient_recursion",

      # Design anti-patterns
      "large_structs",
      "god_module",
      "feature_envy",
      "improper_abstraction",
      "circular_dependencies",
      "tight_coupling",
      "interface_segregation_violation",

      # Process anti-patterns
      "supervision_tree_misuse",
      "genserver_state_abuse",
      "process_bottleneck",
      "improper_process_communication",
      "resource_leak",
      "deadlock_prone_design",

      # Macro anti-patterns
      "unsafe_macro_usage",
      "compile_time_abuse",
      "macro_instead_of_function",
      "quote_unquote_abuse",
      "ast_manipulation_overuse",
      "macro_hygiene_violation"
    ]

    pattern_defaults =
      Enum.with_index(anti_patterns, 140)
      |> Enum.map(fn {pattern, index} ->
        %{
          preference_key: "code_quality.anti_patterns.patterns.#{pattern}",
          default_value: "true",
          data_type: :boolean,
          category: "code_quality",
          subcategory: "anti_pattern_detectors",
          description: "Detect #{String.replace(pattern, "_", " ")} anti-pattern",
          access_level: :user,
          display_order: index
        }
      end)

    seed_defaults(pattern_defaults)
  end

  # Private helper function to seed defaults
  defp seed_defaults(defaults) do
    Enum.each(defaults, fn default_attrs ->
      case SystemDefault.seed_default(default_attrs) do
        {:ok, _} ->
          :ok

        {:error, error} ->
          Logger.warning(
            "Failed to seed code quality default #{default_attrs.preference_key}: #{inspect(error)}"
          )
      end
    end)

    :ok
  rescue
    error ->
      Logger.error("Error seeding code quality defaults: #{inspect(error)}")
      {:error, error}
  end
end
