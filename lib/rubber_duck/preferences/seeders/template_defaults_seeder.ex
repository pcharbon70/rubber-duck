defmodule RubberDuck.Preferences.Seeders.TemplateDefaultsSeeder do
  @moduledoc """
  Seeds predefined preference templates into the system.

  Creates comprehensive template library including Conservative, Balanced,
  and Aggressive configurations plus team-specific and specialized templates
  for common use cases.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.PreferenceTemplate

  @doc """
  Seed all predefined preference templates.
  """
  @spec seed_all() :: :ok | {:error, term()}
  def seed_all do
    Logger.info("Seeding predefined preference templates...")

    with :ok <- seed_system_templates(),
         :ok <- seed_team_templates(),
         :ok <- seed_specialized_templates() do
      Logger.info("Successfully seeded all predefined templates")
      :ok
    else
      error ->
        Logger.error("Failed to seed templates: #{inspect(error)}")
        error
    end
  end

  @doc """
  Seed system-provided templates.
  """
  @spec seed_system_templates() :: :ok | {:error, term()}
  def seed_system_templates do
    templates = [
      %{
        name: "Conservative",
        description: "Safe, minimal settings optimized for stability and reliability",
        category: "system",
        template_type: :system,
        featured: true,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.mode" => "conservative",
          "code_quality.refactoring.auto_apply_enabled" => "false",
          "code_quality.refactoring.test_coverage_required" => "0.9",
          "code_quality.anti_patterns.otp_enforcement_level" => "strict",
          "ml.global.enabled" => "false",
          "budgeting.enforcement.enabled" => "true",
          "budgeting.enforcement.mode" => "hard_stop",
          "llm.cost_optimization.optimization_enabled" => "true"
        },
        tags: ["safe", "stable", "minimal", "enterprise"]
      },
      %{
        name: "Balanced",
        description: "Balanced settings providing good functionality with reasonable safety",
        category: "system",
        template_type: :system,
        featured: true,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.mode" => "moderate",
          "code_quality.refactoring.auto_apply_enabled" => "false",
          "code_quality.refactoring.test_coverage_required" => "0.8",
          "code_quality.anti_patterns.otp_enforcement_level" => "moderate",
          "ml.global.enabled" => "true",
          "ml.features.advanced_enabled" => "false",
          "ml.features.experiment_tracking" => "true",
          "budgeting.enforcement.enabled" => "true",
          "budgeting.enforcement.mode" => "soft_warning",
          "llm.cost_optimization.optimization_enabled" => "true"
        },
        tags: ["balanced", "recommended", "productive", "standard"]
      },
      %{
        name: "Aggressive",
        description: "Advanced settings with full automation and cutting-edge features",
        category: "system",
        template_type: :system,
        featured: true,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.mode" => "aggressive",
          "code_quality.refactoring.auto_apply_enabled" => "true",
          "code_quality.refactoring.test_coverage_required" => "0.7",
          "code_quality.anti_patterns.otp_enforcement_level" => "lenient",
          "ml.global.enabled" => "true",
          "ml.features.advanced_enabled" => "true",
          "ml.features.auto_optimization" => "true",
          "ml.experiments.ab_testing_enabled" => "true",
          "budgeting.enforcement.enabled" => "false",
          "llm.cost_optimization.optimization_enabled" => "false"
        },
        tags: ["advanced", "automated", "experimental", "cutting-edge"]
      }
    ]

    seed_templates(templates)
  end

  @doc """
  Seed team-oriented templates.
  """
  @spec seed_team_templates() :: :ok | {:error, term()}
  def seed_team_templates do
    templates = [
      %{
        name: "Team Development",
        description: "Optimized for team development with collaboration features",
        category: "team",
        template_type: :team,
        featured: false,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.mode" => "moderate",
          "code_quality.refactoring.approval_required_for" => "medium_risk",
          "code_quality.credo.enabled" => "true",
          "code_quality.credo.strict_mode" => "true",
          "code_quality.credo.ci_integration" => "true",
          "budgeting.enforcement.enabled" => "true",
          "budgeting.alerts.enabled" => "true"
        },
        tags: ["team", "collaboration", "ci-cd", "standards"]
      },
      %{
        name: "Solo Developer",
        description: "Optimized for individual developers with minimal overhead",
        category: "individual",
        template_type: :public,
        featured: false,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.mode" => "moderate",
          "code_quality.refactoring.auto_apply_enabled" => "true",
          "code_quality.credo.enabled" => "true",
          "code_quality.credo.strict_mode" => "false",
          "ml.global.enabled" => "true",
          "ml.features.experiment_tracking" => "false",
          "budgeting.enforcement.enabled" => "false"
        },
        tags: ["solo", "individual", "minimal", "productivity"]
      },
      %{
        name: "Enterprise Security",
        description: "Maximum security and compliance for enterprise environments",
        category: "security",
        template_type: :team,
        featured: false,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.auto_apply_enabled" => "false",
          "code_quality.anti_patterns.otp_enforcement_level" => "strict",
          "code_quality.credo.strict_mode" => "true",
          "ml.data.privacy_mode" => "strict",
          "ml.data.user_consent_required" => "true",
          "ml.data.sharing_allowed" => "false",
          "budgeting.enforcement.enabled" => "true",
          "budgeting.enforcement.mode" => "hard_stop"
        },
        tags: ["security", "compliance", "enterprise", "strict"]
      }
    ]

    seed_templates(templates)
  end

  @doc """
  Seed specialized use-case templates.
  """
  @spec seed_specialized_templates() :: :ok | {:error, term()}
  def seed_specialized_templates do
    templates = [
      %{
        name: "Machine Learning Focus",
        description: "Optimized for ML-heavy projects with advanced features enabled",
        category: "specialized",
        template_type: :public,
        featured: false,
        preferences: %{
          "ml.global.enabled" => "true",
          "ml.features.advanced_enabled" => "true",
          "ml.features.experiment_tracking" => "true",
          "ml.features.auto_optimization" => "true",
          "ml.experiments.ab_testing_enabled" => "true",
          "ml.monitoring.drift_detection" => "true",
          "ml.feedback.auto_retrain_threshold" => "0.05",
          "budgeting.limits.cost.monthly" => "500.00",
          "code_quality.refactoring.mode" => "conservative"
        },
        tags: ["ml", "experimentation", "advanced", "data-science"]
      },
      %{
        name: "Code Quality Focus",
        description: "Maximum code quality with comprehensive analysis and refactoring",
        category: "specialized",
        template_type: :public,
        featured: false,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.global.performance_mode" => "thorough",
          "code_quality.smells.analysis_depth" => "deep",
          "code_quality.refactoring.mode" => "moderate",
          "code_quality.refactoring.auto_apply_enabled" => "true",
          "code_quality.credo.enabled" => "true",
          "code_quality.credo.strict_mode" => "true",
          "code_quality.anti_patterns.severity_mode" => "error",
          "ml.global.enabled" => "false"
        },
        tags: ["quality", "refactoring", "analysis", "clean-code"]
      },
      %{
        name: "Performance Optimized",
        description: "Settings optimized for maximum performance and minimal overhead",
        category: "specialized",
        template_type: :public,
        featured: false,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.global.performance_mode" => "fast",
          "code_quality.smells.analysis_depth" => "shallow",
          "code_quality.refactoring.mode" => "conservative",
          "ml.global.enabled" => "false",
          "budgeting.enforcement.enabled" => "false",
          "llm.cost_optimization.optimization_enabled" => "true"
        },
        tags: ["performance", "fast", "minimal", "optimized"]
      },
      %{
        name: "Experimental",
        description: "Cutting-edge features for early adopters and experimentation",
        category: "experimental",
        template_type: :public,
        featured: false,
        preferences: %{
          "code_quality.global.enabled" => "true",
          "code_quality.refactoring.mode" => "aggressive",
          "code_quality.refactoring.auto_apply_enabled" => "true",
          "ml.global.enabled" => "true",
          "ml.features.advanced_enabled" => "true",
          "ml.features.auto_optimization" => "true",
          "ml.experiments.ab_testing_enabled" => "true",
          "budgeting.enforcement.enabled" => "false"
        },
        tags: ["experimental", "cutting-edge", "beta", "advanced"]
      }
    ]

    seed_templates(templates)
  end

  # Private helper function to seed templates
  defp seed_templates(templates) do
    Enum.each(templates, fn template_attrs ->
      case create_template(template_attrs) do
        {:ok, template} ->
          Logger.info("Created template: #{template.name}")

        {:error, error} ->
          Logger.warning("Failed to create template #{template_attrs.name}: #{inspect(error)}")
      end
    end)

    :ok
  rescue
    error ->
      Logger.error("Error seeding templates: #{inspect(error)}")
      {:error, error}
  end

  defp create_template(template_attrs) do
    # Use upsert to make seeding idempotent
    # Placeholder for template lookup by name and type
    case {:ok, []} do
      {:ok, [existing]} ->
        # Update existing template
        update_attrs = Map.drop(template_attrs, [:name, :template_type])
        PreferenceTemplate.update(existing, update_attrs)

      {:ok, []} ->
        # Create new template
        PreferenceTemplate.create(template_attrs)

      error ->
        error
    end
  end
end
