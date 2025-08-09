defmodule RubberDuckWeb.CollaborativeCodingLive.ChatComponent do
  @moduledoc """
  Chat component for agent interaction.
  """
  use RubberDuckWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:message_input, "")}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> handle_new_message(assigns)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      new_message = %{
        id: System.unique_integer([:positive]),
        content: message,
        sender: :user,
        timestamp: DateTime.utc_now()
      }

      # Send to agents
      send(self(), {:forward_to_agent, new_message})

      socket =
        socket
        |> update(:messages, &(&1 ++ [new_message]))
        |> assign(:message_input, "")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp handle_new_message(socket, %{agent_message: message}) do
    agent_message = %{
      id: System.unique_integer([:positive]),
      content: message.content,
      sender: :agent,
      timestamp: DateTime.utc_now()
    }

    update(socket, :messages, &(&1 ++ [agent_message]))
  end

  defp handle_new_message(socket, _), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <!-- Messages Area -->
      <div class="flex-1 overflow-y-auto p-4 space-y-4">
        <%= for message <- @messages do %>
          <div class={[
            "chat",
            message.sender == :user && "chat-end",
            message.sender == :agent && "chat-start"
          ]}>
            <div class="chat-image avatar">
              <div class="w-10 rounded-full">
                <%= if message.sender == :agent do %>
                  <.rubber_duck size="sm" class="p-1" />
                <% else %>
                  <div class="bg-primary text-primary-content flex items-center justify-center h-full">
                    <%= String.first(@user[:username] || @user[:email] || "U") |> String.upcase() %>
                  </div>
                <% end %>
              </div>
            </div>
            <div class="chat-header">
              <%= if message.sender == :agent do %>
                Duck Assistant
              <% else %>
                You
              <% end %>
              <time class="text-xs opacity-50">
                <%= Calendar.strftime(message.timestamp, "%H:%M") %>
              </time>
            </div>
            <div class="chat-bubble">
              <%= message.content %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Input Area -->
      <form phx-submit="send_message" phx-target={@myself} class="p-4 border-t border-base-300">
        <div class="flex gap-2">
          <input
            type="text"
            name="message"
            value={@message_input}
            placeholder="Ask Duck anything..."
            class="input input-bordered flex-1"
            phx-keyup="update_input"
            phx-target={@myself}
          />
          <button type="submit" class="btn btn-primary">
            Send
          </button>
        </div>
      </form>
    </div>
    """
  end
end
