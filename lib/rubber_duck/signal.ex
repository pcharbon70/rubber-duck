defmodule RubberDuck.Signal do
  @moduledoc """
  Simple signal system for inter-agent communication.
  
  This module provides a pub/sub mechanism for agents to communicate
  through signals without direct coupling.
  """

  use GenServer
  require Logger

  @registry RubberDuck.SignalRegistry
  @pubsub RubberDuck.PubSub

  # Client API

  @doc """
  Start the signal system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to a signal type.
  """
  def subscribe(signal_type) when is_binary(signal_type) do
    Phoenix.PubSub.subscribe(@pubsub, signal_type)
  end

  @doc """
  Emit a signal.
  """
  def emit(signal_type, payload) when is_binary(signal_type) and is_map(payload) do
    message = {:signal, signal_type, payload}
    Phoenix.PubSub.broadcast(@pubsub, signal_type, message)
    :ok
  end

  @doc """
  List all active subscriptions for a signal type.
  """
  def list_subscribers(signal_type) when is_binary(signal_type) do
    Registry.lookup(@registry, signal_type)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Start the PubSub system if not already started
    unless Process.whereis(@pubsub) do
      {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: @pubsub, adapter: Phoenix.PubSub.PG2)
    end

    # Start the registry for tracking subscriptions
    unless Process.whereis(@registry) do
      {:ok, _} = Registry.start_link(keys: :duplicate, name: @registry)
    end

    {:ok, %{}}
  end
end