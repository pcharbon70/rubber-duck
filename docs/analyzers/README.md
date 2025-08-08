# Code Analyzers Documentation

This directory contains documentation for the individual code analyzers that power the RubberDuck code analysis system.

## Available Analyzers

1. [Security Analyzer](./security-analyzer.md) - Vulnerability detection and security assessment
2. [Performance Analyzer](./performance-analyzer.md) - Performance bottleneck and optimization analysis
3. [Quality Analyzer](./quality-analyzer.md) - Code quality and maintainability evaluation
4. [Impact Analyzer](./impact-analyzer.md) - Change impact and risk assessment

## Analyzer Interface

All analyzers implement the `RubberDuck.Analyzer` behaviour:

```elixir
@behaviour RubberDuck.Analyzer

@callback analyze(message :: struct(), context :: map()) :: 
  {:ok, result :: map()} | {:error, reason :: term()}

@callback supported_types() :: [module()]

@callback priority() :: :low | :normal | :high | :critical

@callback timeout() :: pos_integer()

@callback metadata() :: map()
```

## Creating Custom Analyzers

To create a custom analyzer:

1. Implement the `RubberDuck.Analyzer` behaviour
2. Define supported message types
3. Implement the analyze/2 function
4. Register with the Orchestrator (if needed)

Example:
```elixir
defmodule MyApp.Analyzers.CustomAnalyzer do
  @behaviour RubberDuck.Analyzer
  
  @impl true
  def analyze(%Analyze{analysis_type: :custom} = msg, context) do
    # Perform analysis
    {:ok, %{custom_metric: calculate_metric(msg.content)}}
  end
  
  @impl true
  def supported_types, do: [Analyze]
  
  @impl true
  def priority, do: :normal
  
  @impl true
  def timeout, do: 10_000
  
  @impl true
  def metadata do
    %{
      name: "Custom Analyzer",
      description: "Performs custom analysis",
      version: "1.0.0"
    }
  end
end
```