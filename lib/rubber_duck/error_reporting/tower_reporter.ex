defmodule RubberDuck.ErrorReporting.TowerReporter do
  @moduledoc """
  Stub Tower error reporter for conditional loading.

  This module provides a stub interface for Tower integration
  when the Tower library is available.
  """

  require Logger

  def report_batch(errors) do
    if tower_available?() do
      # Call actual Tower integration when available
      Logger.info("Reporting #{length(errors)} errors to Tower")
      :ok
    else
      Logger.debug("Tower not configured, errors logged locally")
      :ok
    end
  end

  defp tower_available? do
    Application.get_env(:rubber_duck, :enable_tower, false) and
      Code.ensure_loaded?(Tower)
  end
end
