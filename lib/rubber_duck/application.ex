defmodule RubberDuck.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RubberDuck.Repo,
      {AshAuthentication.Supervisor, [otp_app: :rubber_duck]}
      # Starts a worker by calling: RubberDuck.Worker.start_link(arg)
      # {RubberDuck.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
