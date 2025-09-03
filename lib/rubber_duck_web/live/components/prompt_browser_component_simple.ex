defmodule RubberDuckWeb.Live.Components.PromptBrowserComponentSimple do
  @moduledoc """
  Simplified LiveView component for browsing saved prompts in LLM operations.
  
  TODO: This is a simplified version to resolve CSS compilation issues in original component.
  TODO: Add complete styling and advanced features when HEEx CSS framework issues are resolved.
  TODO: Implement full search functionality, filtering, and sophisticated UI interactions.
  
  Features:
  - Basic three-tier prompt browsing (System/Project/User)
  - Simple prompt selection for LLM operations
  - Essential prompt display with name, type, and description
  - Performance optimized using Section 6.1 infrastructure
  """

  use Phoenix.LiveComponent

  alias RubberDuck.Prompts.Services.LlmPromptSelector

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:prompts, %{})
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  @impl true
  def update(%{user_id: user_id, project_id: project_id} = assigns, socket) do
    socket = assign(socket, assigns)
    
    # Load initial prompts asynchronously
    send(self(), {:load_initial_prompts, user_id, project_id})
    
    {:ok, socket}
  end

  @impl true
  def handle_event("select_prompt", %{"prompt_id" => prompt_id}, socket) do
    %{prompts: prompts} = socket.assigns
    
    # Find selected prompt across all tiers
    selected_prompt = find_prompt_by_id(prompts, prompt_id)
    
    case selected_prompt do
      nil ->
        {:noreply, assign(socket, :error, "Prompt not found")}

      prompt ->
        # Send event to parent LiveView with selected prompt
        send(self(), {:prompt_browser_selection, prompt})
        {:noreply, socket}
    end
  end

  # Handle async messages

  @impl true
  def handle_info({:load_initial_prompts, user_id, project_id}, socket) do
    case LlmPromptSelector.get_available_prompts(user_id, project_id) do
      {:ok, organized_prompts} ->
        socket =
          socket
          |> assign(:prompts, organized_prompts)
          |> assign(:loading, false)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to load initial prompts: #{inspect(reason)}")
        
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to load prompts")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:prompt_browser_selection, prompt}, socket) do
    # Notify parent component about prompt selection
    send(socket.assigns.notify_target, {:prompt_browser_selection, prompt})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- TODO: Add sophisticated styling and advanced search functionality -->
    <!-- TODO: Implement tier filtering, search, and advanced UI interactions -->
    <div style="border: 1px solid #ddd; border-radius: 8px; background: white; max-height: 400px; overflow-y: auto;">
      
      <!-- Loading State -->
      <div :if={@loading} style="padding: 40px; text-align: center; color: #666;">
        Loading prompts...
      </div>

      <!-- Error State -->
      <div :if={@error} style="padding: 20px; background: #ffe6e6; color: #d00; margin: 10px; border-radius: 4px;">
        <%= @error %>
      </div>

      <!-- System Prompts -->
      <div :if={@prompts[:system_prompts] && length(@prompts[:system_prompts]) > 0} style="border-bottom: 1px solid #eee;">
        <h4 style="margin: 0; padding: 15px; background: #f8f9fa; color: #495057;">System Templates</h4>
        <div :for={prompt <- @prompts[:system_prompts]} 
             style="padding: 15px; border-bottom: 1px solid #f0f0f0; cursor: pointer; transition: background 0.2s;"
             phx-click="select_prompt"
             phx-value-prompt_id={prompt.id}
             phx-target={@myself}>
          <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px;">
            <span style="font-weight: 600; color: #212529;"><%= prompt.name %></span>
            <span style="padding: 2px 8px; background: #e3f2fd; color: #1565c0; border-radius: 12px; font-size: 12px;">System</span>
          </div>
          <div style="color: #6c757d; font-size: 14px; margin-bottom: 8px;">
            <%= prompt.description || "No description" %>
          </div>
          <div style="font-family: monospace; background: #f8f9fa; padding: 8px; border-radius: 4px; font-size: 12px; color: #6c757d;">
            <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
          </div>
        </div>
      </div>

      <!-- Project Prompts -->
      <div :if={@prompts[:project_prompts] && length(@prompts[:project_prompts]) > 0} style="border-bottom: 1px solid #eee;">
        <h4 style="margin: 0; padding: 15px; background: #f8f9fa; color: #495057;">Project Prompts</h4>
        <div :for={prompt <- @prompts[:project_prompts]} 
             style="padding: 15px; border-bottom: 1px solid #f0f0f0; cursor: pointer; transition: background 0.2s;"
             phx-click="select_prompt"
             phx-value-prompt_id={prompt.id}
             phx-target={@myself}>
          <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px;">
            <span style="font-weight: 600; color: #212529;"><%= prompt.name %></span>
            <span style="padding: 2px 8px; background: #e8f5e8; color: #2e7d32; border-radius: 12px; font-size: 12px;">Project</span>
          </div>
          <div style="color: #6c757d; font-size: 14px; margin-bottom: 8px;">
            <%= prompt.description || "No description" %>
          </div>
          <div style="font-family: monospace; background: #f8f9fa; padding: 8px; border-radius: 4px; font-size: 12px; color: #6c757d;">
            <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
          </div>
        </div>
      </div>

      <!-- User Prompts -->
      <div :if={@prompts[:user_prompts] && length(@prompts[:user_prompts]) > 0}>
        <h4 style="margin: 0; padding: 15px; background: #f8f9fa; color: #495057;">My Prompts</h4>
        <div :for={prompt <- @prompts[:user_prompts]} 
             style="padding: 15px; border-bottom: 1px solid #f0f0f0; cursor: pointer; transition: background 0.2s;"
             phx-click="select_prompt"
             phx-value-prompt_id={prompt.id}
             phx-target={@myself}>
          <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px;">
            <span style="font-weight: 600; color: #212529;"><%= prompt.name %></span>
            <span style="padding: 2px 8px; background: #fff3cd; color: #856404; border-radius: 12px; font-size: 12px;">Personal</span>
          </div>
          <div style="color: #6c757d; font-size: 14px; margin-bottom: 8px;">
            <%= prompt.description || "No description" %>
          </div>
          <div style="font-family: monospace; background: #f8f9fa; padding: 8px; border-radius: 4px; font-size: 12px; color: #6c757d;">
            <%= String.slice(prompt.content, 0, 100) %><%= if String.length(prompt.content) > 100, do: "..." %>
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div :if={is_empty_state?(@prompts)} style="padding: 40px; text-align: center; color: #6c757d;">
        <p>No prompts found. Create your first prompt in the Prompt Library.</p>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp find_prompt_by_id(prompts, prompt_id) do
    all_prompts = (prompts[:system_prompts] || []) ++ 
                  (prompts[:project_prompts] || []) ++ 
                  (prompts[:user_prompts] || [])
    
    Enum.find(all_prompts, fn prompt -> prompt.id == prompt_id end)
  end

  defp is_empty_state?(prompts) do
    prompt_counts = [
      length(prompts[:system_prompts] || []),
      length(prompts[:project_prompts] || []),
      length(prompts[:user_prompts] || [])
    ]
    
    Enum.sum(prompt_counts) == 0
  end

  defp extract_template_variables(content) do
    # Extract template variables from prompt content
    variables = Regex.scan(~r/\{\{(\w+)(?:\|([^}]+))?\}\}/, content, capture: :all_but_first)
    |> Enum.map(fn
      [variable_name] -> 
        {variable_name, %{default: nil}}
      
      [variable_name, default_value] -> 
        {variable_name, %{default: default_value}}
    end)
    |> Map.new()

    variables
  end

  defp initialize_variable_values(variables) do
    # Initialize variable values map
    Map.new(variables, fn {var, meta} -> {var, meta.default || ""} end)
  end

  defp has_variables?(content) do
    # Check if prompt content contains template variables
    String.contains?(content, "{{") && String.contains?(content, "}}")
  end
end