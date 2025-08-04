import Config

config :rubber_duck, token_signing_secret: "tkYPiqXQUG82eRM3HFwrSLYXCnqSHvzC"

config :rubber_duck, RubberDuck.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rubber_duck_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true]
