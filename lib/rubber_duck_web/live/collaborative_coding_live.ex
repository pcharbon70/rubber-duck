defmodule RubberDuckWeb.CollaborativeCodingLive do
  @moduledoc """
  Main LiveView for the collaborative coding platform integrated with backend agents.
  """

  use RubberDuckWeb, :live_view

  alias RubberDuckWeb.CollaborativeCodingLive.{
    ChatComponent,
    EditorComponent
  }

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    case authenticate_user(session) do
      {:ok, user} ->
        session_id = generate_session_id()

        socket =
          socket
          |> assign(:user, user)
          |> assign(:session_id, session_id)
          |> assign(:connection_state, :connecting)
          |> assign(:page_title, "Collaborative Coding - RubberDuck")
          |> assign(:layout_config, default_layout_config())
          |> assign(:agents, connect_to_agents())
          |> assign(:active_users, %{})

        # Subscribe to Phoenix PubSub topics
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, "session:#{session_id}:broadcast")
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, "session:#{session_id}:agent")

        {:ok, socket}

      {:error, reason} ->
        {:ok, redirect(socket, to: ~p"/?error=#{reason}")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("update_layout", %{"width" => width}, socket) do
    editor_width = String.to_integer(width)
    chat_width = 100 - editor_width

    layout_config = %{
      socket.assigns.layout_config
      | editor_width_percent: editor_width,
        chat_width_percent: chat_width
    }

    {:noreply, assign(socket, :layout_config, layout_config)}
  end

  @impl Phoenix.LiveView
  def handle_info({:agent_message, message}, socket) do
    send_update(ChatComponent, id: "chat-component", agent_message: message)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:agent_suggestion, suggestion}, socket) do
    send_update(EditorComponent, id: "editor-component", agent_suggestion: suggestion)
    {:noreply, socket}
  end

  defp authenticate_user(session) do
    cond do
      demo_user = session["demo_user"] ->
        {:ok, demo_user}

      user = session["current_user"] ->
        {:ok, user}

      true ->
        {:error, "not_authenticated"}
    end
  end

  defp generate_session_id do
    bytes = :crypto.strong_rand_bytes(16)
    Base.encode16(bytes, case: :lower)
  end

  defp connect_to_agents do
    # Connect to backend agents
    %{
      orchestrator: "llm_orchestrator",
      monitor: "llm_monitoring",
      status: :connected
    }
  end

  defp default_layout_config do
    %{
      editor_width_percent: 70,
      chat_width_percent: 30,
      mobile_layout: :stacked,
      theme: :dark
    }
  end
end
