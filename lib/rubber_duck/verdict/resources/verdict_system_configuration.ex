defmodule RubberDuck.Verdict.VerdictSystemConfiguration do
  @moduledoc """
  System-level Verdict configuration resource that defines global defaults
  and policies for the LLM judge evaluation system.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer

  require Logger

  postgres do
    table "verdict_system_configurations"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create
    define :update
    define :destroy
    define :read
    define :get_active_configuration
  end

  actions do
    defaults [:read]

    create :create do
      description "Create new system-level Verdict configuration"
      primary? true

      accept [
        :enabled,
        :default_screening_model,
        :default_detailed_model,
        :global_daily_budget,
        :default_quality_threshold,
        :escalation_threshold,
        :preferred_providers,
        :evaluation_criteria_weights
      ]

      validate present([:enabled, :default_screening_model, :default_detailed_model])
    end

    update :update do
      description "Update system-level Verdict configuration"
      primary? true

      accept [
        :enabled,
        :default_screening_model,
        :default_detailed_model,
        :global_daily_budget,
        :default_quality_threshold,
        :escalation_threshold,
        :preferred_providers,
        :evaluation_criteria_weights
      ]
    end

    destroy :destroy do
      description "Delete system-level Verdict configuration"
      primary? true
    end

    read :get_active_configuration do
      description "Get the currently active system configuration"

      filter expr(enabled == true)
      prepare build(sort: [created_at: :desc])
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :enabled, :boolean do
      description "Global enablement of Verdict evaluation system"
      default true
      allow_nil? false
    end

    attribute :default_screening_model, :string do
      description "Default model for lightweight screening evaluations"
      constraints min_length: 1, max_length: 100
      default "gpt-4o-mini"
    end

    attribute :default_detailed_model, :string do
      description "Default model for detailed analysis evaluations"
      constraints min_length: 1, max_length: 100
      default "gpt-4o"
    end

    attribute :global_daily_budget, :decimal do
      description "System-wide daily budget limit for evaluations"
      constraints greater_than: 0
      default Decimal.new("100.00")
    end

    attribute :default_quality_threshold, :decimal do
      description "Default minimum quality threshold for evaluations"
      constraints min: 0, max: 1
      default Decimal.new("0.8")
    end

    attribute :escalation_threshold, :decimal do
      description "Confidence threshold below which evaluations are escalated"
      constraints min: 0, max: 1
      default Decimal.new("0.6")
    end

    attribute :preferred_providers, {:array, :string} do
      description "Ordered list of preferred LLM providers"
      default ["openai", "anthropic"]
    end

    attribute :evaluation_criteria_weights, :map do
      description "Default weights for evaluation criteria categories"

      default %{
        "correctness" => 0.3,
        "security" => 0.25,
        "maintainability" => 0.2,
        "performance" => 0.15,
        "style" => 0.1
      }
    end

    timestamps()
  end

  def get_default_configuration do
    %{
      enabled: true,
      default_screening_model: "gpt-4o-mini",
      default_detailed_model: "gpt-4o",
      global_daily_budget: Decimal.new("100.00"),
      default_quality_threshold: Decimal.new("0.8"),
      escalation_threshold: Decimal.new("0.6"),
      preferred_providers: ["openai", "anthropic"],
      evaluation_criteria_weights: %{
        "correctness" => 0.3,
        "security" => 0.25,
        "maintainability" => 0.2,
        "performance" => 0.15,
        "style" => 0.1
      }
    }
  end

  def validate_configuration(config) when is_map(config) do
    with :ok <- validate_required_fields(config),
         :ok <- validate_budget_values(config),
         :ok <- validate_thresholds(config),
         :ok <- validate_providers(config),
         :ok <- validate_criteria_weights(config) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(config) do
    required = [:enabled, :default_screening_model, :default_detailed_model]
    missing = Enum.filter(required, &(!Map.has_key?(config, &1)))

    case missing do
      [] -> :ok
      fields -> {:error, "Missing required fields: #{inspect(fields)}"}
    end
  end

  defp validate_budget_values(config) do
    case Map.get(config, :global_daily_budget) do
      budget when is_number(budget) and budget > 0 ->
        :ok

      %Decimal{} = budget ->
        if Decimal.positive?(budget), do: :ok, else: {:error, "Budget must be positive"}

      _ ->
        {:error, "Invalid budget value"}
    end
  end

  defp validate_thresholds(config) do
    quality = Map.get(config, :default_quality_threshold, 0.8)
    escalation = Map.get(config, :escalation_threshold, 0.6)

    cond do
      escalation >= quality ->
        {:error, "Escalation threshold must be less than quality threshold"}

      quality < 0 or quality > 1 ->
        {:error, "Quality threshold must be between 0 and 1"}

      escalation < 0 or escalation > 1 ->
        {:error, "Escalation threshold must be between 0 and 1"}

      true ->
        :ok
    end
  end

  defp validate_providers(config) do
    case Map.get(config, :preferred_providers, []) do
      providers when is_list(providers) and length(providers) > 0 ->
        valid_providers = ["openai", "anthropic", "ollama", "azure", "vertex"]

        if Enum.all?(providers, &(&1 in valid_providers)) do
          :ok
        else
          {:error, "Invalid provider in list"}
        end

      _ ->
        {:error, "Preferred providers must be a non-empty list"}
    end
  end

  defp validate_criteria_weights(config) do
    case Map.get(config, :evaluation_criteria_weights, %{}) do
      weights when is_map(weights) ->
        total = weights |> Map.values() |> Enum.sum()

        if abs(total - 1.0) < 0.001 do
          :ok
        else
          {:error, "Evaluation criteria weights must sum to 1.0"}
        end

      _ ->
        {:error, "Evaluation criteria weights must be a map"}
    end
  end
end
