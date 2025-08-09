defmodule RubberDuck.MixProject do
  use Mix.Project

  def project do
    [
      app: :rubber_duck,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {RubberDuck.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:ash_authentication, "~> 4.0"},
      {:sourceror, "~> 1.8"},
      {:ash_postgres, "~> 2.0"},
      {:ash, "~> 3.0"},
      # Jido SDK
      {:jido, "~> 1.2"},
      {:jason, "~> 1.4"},
      # Ash framework
      {:picosat_elixir, "~> 0.2"},
      {:igniter, "~> 0.6"},
      # HTTP client
      {:req, "~> 0.5"},
      # Circuit breaker library
      {:fuse, "~> 2.5"},
      {:ex_rated, "~> 2.1"},
      # OpenAI tokenization
      {:tiktoken, "~> 0.4"},
      # HuggingFace tokenizers for Anthropic
      {:tokenizers, "~> 0.5"},
      # Vector support for semantic search
      {:pgvector, "~> 0.3"},
      # RAG (Retrieval-Augmented Generation) library
      {:rag, "~> 0.1"},
      # Template engine dependencies
      {:solid, "~> 1.0.1"},
      {:earmark, "~> 1.4.48"},
      {:file_system, "~> 1.1.0"},

      # JSON Schema validation
      {:ex_json_schema, "~> 0.10"},

      # Telemetry and monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Error reporting
      {:tower, "~> 0.6"},

      # HTTP client for Swoosh
      {:hackney, "~> 1.9"},

      # PubSub for signal system
      {:phoenix_pubsub, "~> 2.1"},
      
      # Phoenix framework and LiveView
      {:phoenix, "~> 1.7.18"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:floki, ">= 0.30.0", only: :test},
      
      # Authentication UI
      {:ash_authentication_phoenix, "~> 2.0"},
      
      # Asset building
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      
      # HTTP server
      {:bandit, "~> 1.5"},
      {:plug_cowboy, "~> 2.7"},
      {:gettext, "~> 0.20"},
      {:heroicons, "~> 0.5"},
      
      # Monaco editor
      {:live_monaco_editor, "~> 0.1"},
      
      # Development tools
      {:swoosh, "~> 1.5"},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases() do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind rubberduck", "esbuild rubberduck"],
      "assets.deploy": [
        "tailwind rubberduck --minify",
        "esbuild rubberduck --minify",
        "phx.digest"
      ],
      test: ["ash.setup --quiet", "test"]
    ]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
