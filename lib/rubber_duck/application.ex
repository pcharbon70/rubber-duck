defmodule RubberDuck.Application do
  @moduledoc """
  The RubberDuck OTP Application.
  
  Configures the supervision tree for the application including:
  - Database repository
  - Authentication supervisor
  - Telemetry and monitoring
  - Health checks
  - Error reporting
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Tower starts automatically when configured
    
    children = [
      # Database connection pool
      RubberDuck.Repo,
      
      # Authentication system
      {AshAuthentication.Supervisor, [otp_app: :rubber_duck]},
      
      # Telemetry and monitoring
      RubberDuck.Telemetry,
      
      # Health check monitoring
      RubberDuck.HealthCheck
      
      # Future children:
      # - Phoenix endpoint (when added)
      # - Job processing (Oban or similar)
      # - Cache (when needed)
    ]

    # Using rest_for_one: if a child process terminates, 
    # all processes started after it are also terminated and restarted
    opts = [strategy: :rest_for_one, name: RubberDuck.Supervisor]
    
    Logger.info("Starting RubberDuck application supervision tree...")
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("RubberDuck application started successfully")
        {:ok, pid}
      {:error, reason} = error ->
        Logger.error("Failed to start RubberDuck application: #{inspect(reason)}")
        error
    end
  end
end
