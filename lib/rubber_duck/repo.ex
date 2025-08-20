defmodule RubberDuck.Repo do
  use Ecto.Repo,
    otp_app: :rubber_duck,
    adapter: Ecto.Adapters.Postgres
end
