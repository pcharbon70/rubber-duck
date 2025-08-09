defmodule RubberDuckWeb.CollaborativeChannel do
  @moduledoc """
  Channel for real-time collaborative features and agent communication.
  """
  use RubberDuckWeb, :channel

  require Logger

  @impl true
  def join("session:" <> session_id, _payload, socket) do
    send(self(), :after_join)
    {:ok, assign(socket, :session_id, session_id)}
  end

  @impl true
  def handle_info(:after_join, socket) do
    push(socket, "presence_state", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_in("chat_message", payload, socket) do
    # Forward to agents if needed
    forward_to_agents(socket.assigns.session_id, payload)

    # Broadcast to other users
    broadcast_from(socket, "new_message", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("editor_change", payload, socket) do
    broadcast_from(socket, "editor_change", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("cursor_position", payload, socket) do
    broadcast_from(socket, "cursor_update", payload)
    {:noreply, socket}
  end

  defp forward_to_agents(session_id, _message) do
    # TODO: Integration with backend agents
    Logger.info("Forwarding message to agents for session: #{session_id}")
  end
end
