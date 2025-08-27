defmodule RubberDuck.ErrorReporting.Supervisor do
  @moduledoc """
  Error Reporting Supervisor with Tower integration.

  Manages error aggregation, context enrichment, filtering,
  and pattern detection for the entire application.
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting Error Reporting System...")

    children =
      [
        # Error Aggregator
        {RubberDuck.ErrorReporting.Aggregator, []},

        # Context Enricher
        {RubberDuck.ErrorReporting.ContextEnricher, []},

        # Error Pattern Detector
        {RubberDuck.ErrorReporting.PatternDetector, []},

        # Tower Reporter (if configured)
        tower_reporter_child()
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp tower_reporter_child do
    if Application.get_env(:rubber_duck, :enable_tower, false) do
      {RubberDuck.ErrorReporting.TowerReporter, []}
    else
      nil
    end
  end
end
