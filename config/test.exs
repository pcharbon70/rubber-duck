import Config

config :rubber_duck, token_signing_secret: "WRxU1Oi6CEOiOdIm6UIh+bHjk2FfgsqD"
config :bcrypt_elixir, log_rounds: 1
config :logger, level: :warning

config :rubber_duck, RubberDuck.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rubberduck_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true
