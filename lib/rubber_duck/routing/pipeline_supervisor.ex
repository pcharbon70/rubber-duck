defmodule RubberDuck.Routing.PipelineSupervisor do
  @moduledoc """
  Supervisor for the GenStage message processing pipeline.
  
  Manages the lifecycle of:
  - Message Producer
  - Priority Consumer Pool  
  - Batching Telemetry
  
  Provides automatic restart capabilities and ensures proper
  initialization order for the pipeline components.
  """
  
  use Supervisor
  require Logger
  
  @doc """
  Starts the pipeline supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Enqueues a message into the pipeline.
  """
  def enqueue(message, context \\ %{}) do
    RubberDuck.Routing.MessageProducer.enqueue(message, context)
  end
  
  @doc """
  Enqueues a message synchronously.
  """
  def enqueue_sync(message, context \\ %{}, timeout \\ 5000) do
    RubberDuck.Routing.MessageProducer.enqueue_sync(message, context, timeout)
  end
  
  @impl true
  def init(opts) do
    # Pipeline configuration
    producer_config = Keyword.get(opts, :producer, [])
    consumer_config = Keyword.get(opts, :consumer, [])
    
    children = [
      # Start telemetry first
      {RubberDuck.Telemetry.BatchingTelemetry, []},
      
      # Start the producer
      {RubberDuck.Routing.MessageProducer, producer_config},
      
      # Start the consumer pool that subscribes to the producer
      {RubberDuck.Routing.PriorityConsumerPool, 
       Keyword.merge(consumer_config, [producer: RubberDuck.Routing.MessageProducer])}
    ]
    
    # Using rest_for_one strategy: if a process fails, all processes
    # started after it are terminated and restarted
    Supervisor.init(children, strategy: :rest_for_one)
  end
  
  @doc """
  Returns pipeline statistics.
  """
  def stats do
    %{
      producer: get_producer_stats(),
      consumer: get_consumer_stats(),
      telemetry: RubberDuck.Telemetry.BatchingTelemetry.get_metrics()
    }
  end
  
  defp get_producer_stats do
    try do
      GenStage.call(RubberDuck.Routing.MessageProducer, :get_stats, 1000)
    catch
      :exit, _ -> %{status: :unavailable}
    end
  end
  
  defp get_consumer_stats do
    try do
      GenStage.call(RubberDuck.Routing.PriorityConsumerPool, :get_stats, 1000)
    catch
      :exit, _ -> %{status: :unavailable}
    end
  end
end