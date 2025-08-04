defmodule RubberDuck.LLM.Supervisor do
  @moduledoc """
  Supervisor for the LLM subsystem.

  Manages all LLM-related processes including the service,
  provider registry, and health monitor.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Provider registry must start first
      RubberDuck.LLM.ProviderRegistry,

      # Health monitor
      RubberDuck.LLM.HealthMonitor,

      # Main service
      RubberDuck.LLM.Service,

      # Dynamic supervisor for provider connections
      {DynamicSupervisor, name: RubberDuck.LLM.ConnectionSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
