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
      extra_applications: [:logger],
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
      {:jido, "~> 1.0.0-rc.5"},
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
      {:tower, "~> 0.6"}
    ]
  end

  defp aliases() do
    [test: ["ash.setup --quiet", "test"], setup: "ash.setup"]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
