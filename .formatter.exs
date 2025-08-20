# Used by "mix format"
[
  inputs: [".claude.exs", "{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [:ash_authentication, :ash_postgres, :ash, :reactor]
]
