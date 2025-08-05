defmodule RubberDuck.Actions.LLM.Complete do
  @moduledoc """
  Action for completing text using an LLM provider.
  
  This is a stateless action that executes a completion request
  against a specific provider.
  """

  use Jido.Action,
    name: "llm_complete",
    description: "Generate text completion using specified LLM provider",
    schema: [
      provider: [type: :map, required: true],
      request: [type: :map, required: true],
      timeout: [type: :pos_integer, default: 30_000]
    ]

  alias RubberDuck.LLM.HealthMonitor
  require Logger

  @impl true
  def run(params, _context) do
    provider = params.provider
    request = params.request
    timeout = params.timeout
    
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Add timeout to provider config
      config = Map.put(provider.config, :timeout, timeout)
      
      # Call the provider's complete function
      case apply(provider.module, :complete, [request, config]) do
        {:ok, response} ->
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Record success metrics
          HealthMonitor.record_success(provider.name, duration)
          
          {:ok, %{
            response: response,
            provider: provider.name,
            duration_ms: duration,
            success: true
          }}
        
        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Record failure metrics
          HealthMonitor.record_failure(provider.name, reason)
          
          Logger.warning("LLM completion failed for provider #{provider.name}: #{inspect(reason)}")
          
          {:error, %{
            reason: reason,
            provider: provider.name,
            duration_ms: duration,
            success: false
          }}
      end
    rescue
      exception ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Record failure metrics
        HealthMonitor.record_failure(provider.name, exception)
        
        Logger.error("LLM completion crashed for provider #{provider.name}: #{inspect(exception)}")
        
        {:error, %{
          reason: {:exception, exception},
          provider: provider.name,
          duration_ms: duration,
          success: false
        }}
    end
  end

  def describe do
    %{
      name: "LLM Complete",
      description: "Executes a text completion request against an LLM provider",
      category: "llm",
      inputs: %{
        provider: "The provider configuration map with module and config",
        request: "The completion request with model, messages, and parameters",
        timeout: "Maximum time to wait for completion in milliseconds"
      },
      outputs: %{
        success: %{
          response: "The completion response from the provider",
          provider: "Name of the provider used",
          duration_ms: "Time taken for the completion",
          success: "Always true for successful completions"
        },
        error: %{
          reason: "The error reason",
          provider: "Name of the provider that failed",
          duration_ms: "Time taken before failure",
          success: "Always false for failures"
        }
      }
    }
  end
end