defmodule RubberDuckWeb.CollaborativeCodingLive.EditorComponent do
  @moduledoc """
  Code editor component with Monaco integration.
  """
  use RubberDuckWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:code, default_code())
     |> assign(:language, "elixir")
     |> assign(:theme, "vs-dark")}
  end

  @impl true
  def update(assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> handle_agent_suggestion(assigns)

    {:ok, socket}
  end

  @impl true
  def handle_event("code_change", %{"value" => value}, socket) do
    # Forward to agents for analysis
    send(self(), {:analyze_code, value})
    
    {:noreply, assign(socket, :code, value)}
  end

  defp handle_agent_suggestion(socket, %{agent_suggestion: suggestion}) do
    # Apply agent suggestion to editor
    push_event(socket, "apply_suggestion", %{suggestion: suggestion})
  end

  defp handle_agent_suggestion(socket, _), do: socket

  defp default_code do
    """
    defmodule Example do
      @moduledoc \"\"\"
      Welcome to RubberDuck collaborative coding!
      Start typing to see agent suggestions.
      \"\"\"

      def hello do
        "Hello from RubberDuck!"
      end
    end
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full">
      <div
        id={"editor-#{@id}"}
        phx-hook="MonacoEditor"
        phx-target={@myself}
        data-language={@language}
        data-theme={@theme}
        data-value={@code}
        class="h-full w-full"
      >
        <!-- Monaco Editor will be mounted here -->
        <div class="flex items-center justify-center h-full">
          <div class="text-center">
            <div class="loading loading-spinner loading-lg"></div>
            <p class="mt-4">Loading editor...</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end