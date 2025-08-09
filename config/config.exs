import Config

# General application configuration
config :rubber_duck,
  ecto_repos: [RubberDuck.Repo]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure Phoenix
config :rubber_duck, RubberDuckWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RubberDuckWeb.ErrorHTML, json: RubberDuckWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RubberDuck.PubSub,
  live_view: [signing_salt: "nR3qgxhM"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  rubberduck: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  rubberduck: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ash Framework
config :rubber_duck,
  ash_domains: [
    RubberDuck.Accounts,
    RubberDuck.Projects,
    RubberDuck.AI,
    RubberDuck.Agents
  ]

# Configure EventStore for event sourcing
config :rubber_duck, 
  event_stores: [RubberDuck.EventStore]

config :rubber_duck, RubberDuck.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "rubberduck_eventstore",
  hostname: "localhost",
  pool_size: 10

# Configure Tower error reporting
config :tower,
  reporters: [Tower.LoggerReporter],
  log_level: :error,
  ignored_exceptions: [
    # Add any exceptions you want to ignore
  ],
  metadata_keys: [:user_id, :request_id, :resource, :action]

# Configure Telemetry for ML/AI monitoring
config :rubber_duck, :telemetry,
  prometheus_enabled: true,
  prometheus_port: 9568,
  ml_metrics_enabled: true,
  action_tracking_enabled: true,
  learning_metrics_enabled: true,
  impact_scoring_enabled: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
