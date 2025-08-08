import Config

config :rubber_duck, token_signing_secret: "tkYPiqXQUG82eRM3HFwrSLYXCnqSHvzC"

config :rubber_duck, RubberDuck.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rubberduck_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true]

# Configure Phoenix endpoint for development
config :rubber_duck, RubberDuckWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "KLdO3FxwZPq5qZJ3B1234567890abcdefghijklmnopqrstuvwxyz1234567890ab",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:rubberduck, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:rubberduck, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :rubber_duck, RubberDuckWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/rubber_duck_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :rubber_duck, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
