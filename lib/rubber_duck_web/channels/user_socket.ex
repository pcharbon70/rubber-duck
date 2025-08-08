defmodule RubberDuckWeb.UserSocket do
  use Phoenix.Socket

  # Channels
  channel "session:*", RubberDuckWeb.CollaborativeChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # TODO: verify token
    {:ok, assign(socket, :user_id, "user_#{:rand.uniform(1000)}")}
  end

  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns[:user_id] || "anonymous"}"
end