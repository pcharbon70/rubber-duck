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

    children = [
      # Error Aggregator
      {RubberDuck.ErrorReporting.Aggregator, []}

      # Other error reporting components will be added as they're implemented
    ]

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
