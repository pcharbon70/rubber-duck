defmodule RubberDuckWeb.Preferences.CategoryEditorLive do
  @moduledoc """
  Category-based preference editor providing detailed preference configuration.

  Features:
  - Detailed preference editing with validation
  - Category-specific organization
  - Real-time validation and error display
  - Inheritance visualization
  - Bulk operations within category
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Preferences.{
    PreferenceResolver,
    PreferenceWatcher,
    ValidationInterfaceManager
  }

  alias RubberDuck.Preferences.Resources.{
    PreferenceValidation,
    SystemDefault,
    UserPreference
  }

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  @impl true
  def mount(%{"key" => preference_key}, _session, socket) do
    if connected?(socket) do
      # Subscribe to preference changes for real-time updates
      PreferenceWatcher.subscribe_user_changes(socket.assigns.current_user.id)
    end

    {:ok,
     socket
     |> assign_initial_state(preference_key)
     |> load_preference_details()
     |> load_validation_rules()
     |> prepare_form()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, assign_context(socket, params)}
  end

  @impl true
  def handle_event("validate", %{"preference" => preference_params}, socket) do
    changeset = validate_preference_changes(preference_params, socket.assigns.validation_rules)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"preference" => preference_params}, socket) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project_id
    preference_key = socket.assigns.preference_key

    case save_preference(user_id, project_id, preference_key, preference_params) do
      {:ok, _preference} ->
        {:noreply,
         socket
         |> put_flash(:info, "Preference saved successfully")
         |> push_navigate(to: ~p"/preferences")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Please fix the errors below")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{reason}")}
    end
  end

  @impl true
  def handle_event("reset_to_default", _params, socket) do
    user_id = socket.assigns.current_user.id
    preference_key = socket.assigns.preference_key

    case reset_preference_to_default(user_id, preference_key) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Preference reset to default")
         |> load_preference_details()
         |> prepare_form()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset: #{reason}")}
    end
  end

  @impl true
  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, :show_advanced, !socket.assigns.show_advanced)}
  end

  @impl true
  def handle_info({:preference_changed, change_event}, socket) do
    if change_event.user_id == socket.assigns.current_user.id and
         change_event.preference_key == socket.assigns.preference_key do
      {:noreply,
       socket
       |> load_preference_details()
       |> prepare_form()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="preference-editor max-w-4xl mx-auto">
      <!-- Header with breadcrumbs -->
      <div class="mb-6">
        <nav class="flex" aria-label="Breadcrumb">
          <ol class="flex items-center space-x-4">
            <li>
              <div>
                <.link navigate={~p"/preferences"} class="text-gray-400 hover:text-gray-500">
                  <svg class="flex-shrink-0 h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M10.707 2.293a1 1 0 00-1.414 0l-7 7a1 1 0 001.414 1.414L4 10.414V17a1 1 0 001 1h2a1 1 0 001-1v-2a1 1 0 011-1h2a1 1 0 011 1v2a1 1 0 001 1h2a1 1 0 001-1v-6.586l.293.293a1 1 0 001.414-1.414l-7-7z" />
                  </svg>
                  <span class="sr-only">Preferences</span>
                </.link>
              </div>
            </li>
            <li>
              <div class="flex items-center">
                <svg class="flex-shrink-0 h-5 w-5 text-gray-300" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 111.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                </svg>
                <.link
                  navigate={~p"/preferences?category=#{@preference_details.category}"}
                  class="ml-4 text-sm font-medium text-gray-500 hover:text-gray-700"
                >
                  <%= String.capitalize(@preference_details.category) %>
                </.link>
              </div>
            </li>
            <li>
              <div class="flex items-center">
                <svg class="flex-shrink-0 h-5 w-5 text-gray-300" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 111.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                </svg>
                <span class="ml-4 text-sm font-medium text-gray-500">
                  <%= @preference_key %>
                </span>
              </div>
            </li>
          </ol>
        </nav>
        
        <div class="mt-4">
          <h1 class="text-2xl font-bold text-gray-900">
            <%= @preference_key %>
          </h1>
          <p class="mt-1 text-sm text-gray-600">
            <%= @preference_details.description %>
          </p>
        </div>
      </div>
      
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Main Form -->
        <div class="lg:col-span-2">
          <div class="bg-white shadow rounded-lg">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-medium text-gray-900">Configuration</h3>
            </div>
            
            <.form
              for={@form}
              phx-change="validate"
              phx-submit="save"
              class="p-6"
            >
              <!-- Value Input -->
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Value
                </label>
                <%= case @preference_details.data_type do %>
                  <% "boolean" -> %>
                    <div class="flex items-center">
                      <.input
                        field={@form[:value]}
                        type="checkbox"
                        class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                      />
                      <label class="ml-2 text-sm text-gray-600">
                        Enable this preference
                      </label>
                    </div>
                  
                  <% "number" -> %>
                    <.input
                      field={@form[:value]}
                      type="number"
                      class="block w-full"
                      placeholder="Enter a number"
                    />
                  
                  <% "float" -> %>
                    <.input
                      field={@form[:value]}
                      type="number"
                      step="0.01"
                      class="block w-full"
                      placeholder="Enter a decimal number"
                    />
                  
                  <% "json" -> %>
                    <.input
                      field={@form[:value]}
                      type="textarea"
                      rows="10"
                      class="block w-full font-mono text-sm"
                      placeholder="Enter valid JSON"
                    />
                  
                  <% "enum" -> %>
                    <.input
                      field={@form[:value]}
                      type="select"
                      options={@preference_details.allowed_values}
                      class="block w-full"
                    />
                  
                  <% _ -> %>
                    <.input
                      field={@form[:value]}
                      type="text"
                      class="block w-full"
                      placeholder="Enter value"
                    />
                <% end %>
                
                <%= if @preference_details.constraints do %>
                  <div class="mt-2 text-sm text-gray-500">
                    <%= render_constraints_help(@preference_details.constraints) %>
                  </div>
                <% end %>
              </div>
              
              <!-- Reason for Change (if project context) -->
              <%= if @project_id do %>
                <div class="mb-6">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Reason for Change
                    <span class="text-red-500">*</span>
                  </label>
                  <.input
                    field={@form[:reason]}
                    type="textarea"
                    rows="3"
                    class="block w-full"
                    placeholder="Explain why this project override is needed..."
                    required
                  />
                </div>
              <% end %>
              
              <!-- Advanced Options -->
              <%= if @show_advanced do %>
                <div class="border-t border-gray-200 pt-6 mb-6">
                  <h4 class="text-sm font-medium text-gray-900 mb-4">Advanced Options</h4>
                  
                  <!-- Inheritance Override -->
                  <%= if @project_id do %>
                    <div class="mb-4">
                      <div class="flex items-center">
                        <.input
                          field={@form[:override_inheritance]}
                          type="checkbox"
                          class="h-4 w-4 text-blue-600"
                        />
                        <label class="ml-2 text-sm text-gray-700">
                          Override inheritance (don't inherit from user preferences)
                        </label>
                      </div>
                    </div>
                  <% end %>
                  
                  <!-- Category Selection -->
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 mb-2">
                      Category
                    </label>
                    <.input
                      field={@form[:category]}
                      type="select"
                      options={category_options()}
                      class="block w-full"
                    />
                  </div>
                </div>
              <% end %>
              
              <!-- Actions -->
              <div class="flex justify-between items-center">
                <div class="flex space-x-3">
                  <button
                    type="submit"
                    class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    Save Changes
                  </button>
                  
                  <button
                    type="button"
                    phx-click="reset_to_default"
                    data-confirm="Are you sure you want to reset this preference to its default value?"
                    class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    Reset to Default
                  </button>
                </div>
                
                <button
                  type="button"
                  phx-click="toggle_advanced"
                  class="text-sm text-blue-600 hover:text-blue-500"
                >
                  <%= if @show_advanced, do: "Hide", else: "Show" %> Advanced Options
                </button>
              </div>
            </.form>
          </div>
        </div>
        
        <!-- Sidebar -->
        <div class="lg:col-span-1 space-y-6">
          <!-- Preference Information -->
          <div class="bg-white shadow rounded-lg">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-medium text-gray-900">Information</h3>
            </div>
            <div class="p-6 space-y-4">
              <div>
                <dt class="text-sm font-medium text-gray-500">Data Type</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    <%= @preference_details.data_type %>
                  </span>
                </dd>
              </div>
              
              <div>
                <dt class="text-sm font-medium text-gray-500">Category</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <%= String.capitalize(@preference_details.category) %>
                </dd>
              </div>
              
              <div>
                <dt class="text-sm font-medium text-gray-500">Current Source</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    case @preference_details.source do
                      "system" -> "bg-gray-100 text-gray-800"
                      "user" -> "bg-blue-100 text-blue-800"
                      "project" -> "bg-green-100 text-green-800"
                      _ -> "bg-red-100 text-red-800"
                    end
                  ]}>
                    <%= String.capitalize(@preference_details.source) %>
                  </span>
                </dd>
              </div>
              
              <div>
                <dt class="text-sm font-medium text-gray-500">Default Value</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <code class="bg-gray-100 px-2 py-1 rounded text-xs">
                    <%= @preference_details.default_value %>
                  </code>
                </dd>
              </div>
            </div>
          </div>
          
          <!-- Inheritance Hierarchy -->
          <div class="bg-white shadow rounded-lg">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-medium text-gray-900">Inheritance</h3>
            </div>
            <div class="p-6">
              <div class="space-y-3">
                <!-- System Default -->
                <div class="flex items-center justify-between p-3 bg-gray-50 rounded">
                  <div>
                    <div class="text-sm font-medium text-gray-900">System Default</div>
                    <div class="text-xs text-gray-500">Base configuration</div>
                  </div>
                  <code class="text-xs bg-white px-2 py-1 rounded">
                    <%= @preference_details.default_value %>
                  </code>
                </div>
                
                <!-- User Override -->
                <%= if @preference_details.user_value do %>
                  <div class="flex items-center justify-between p-3 bg-blue-50 rounded border-l-4 border-blue-400">
                    <div>
                      <div class="text-sm font-medium text-gray-900">User Override</div>
                      <div class="text-xs text-gray-500">Your personal setting</div>
                    </div>
                    <code class="text-xs bg-white px-2 py-1 rounded">
                      <%= @preference_details.user_value %>
                    </code>
                  </div>
                <% end %>
                
                <!-- Project Override -->
                <%= if @preference_details.project_value do %>
                  <div class="flex items-center justify-between p-3 bg-green-50 rounded border-l-4 border-green-400">
                    <div>
                      <div class="text-sm font-medium text-gray-900">Project Override</div>
                      <div class="text-xs text-gray-500">Project-specific setting</div>
                    </div>
                    <code class="text-xs bg-white px-2 py-1 rounded">
                      <%= @preference_details.project_value %>
                    </code>
                  </div>
                <% end %>
                
                <!-- Final Value -->
                <div class="flex items-center justify-between p-3 bg-yellow-50 rounded border-l-4 border-yellow-400">
                  <div>
                    <div class="text-sm font-medium text-gray-900">Final Value</div>
                    <div class="text-xs text-gray-500">Currently active</div>
                  </div>
                  <code class="text-xs bg-white px-2 py-1 rounded font-bold">
                    <%= @preference_details.current_value %>
                  </code>
                </div>
              </div>
            </div>
          </div>
          
          <!-- Related Preferences -->
          <%= if @preference_details.related_preferences do %>
            <div class="bg-white shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200">
                <h3 class="text-lg font-medium text-gray-900">Related Preferences</h3>
              </div>
              <div class="p-6">
                <div class="space-y-2">
                  <%= for related <- @preference_details.related_preferences do %>
                    <.link
                      navigate={~p"/preferences/edit/#{related.key}"}
                      class="block p-2 rounded hover:bg-gray-50"
                    >
                      <div class="text-sm font-medium text-gray-900">
                        <%= related.key %>
                      </div>
                      <div class="text-xs text-gray-500 truncate">
                        <%= related.description %>
                      </div>
                    </.link>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp assign_initial_state(socket, preference_key) do
    socket
    |> assign(:preference_key, preference_key)
    |> assign(:project_id, nil)
    |> assign(:show_advanced, false)
    |> assign(:preference_details, %{})
    |> assign(:validation_rules, %{})
    |> assign(:changeset, nil)
    |> assign(:form, nil)
  end

  defp assign_context(socket, params) do
    assign(socket, :project_id, params["project_id"])
  end

  defp load_preference_details(socket) do
    user_id = socket.assigns.current_user.id
    preference_key = socket.assigns.preference_key
    project_id = socket.assigns.project_id

    case get_preference_details(user_id, preference_key, project_id) do
      {:ok, details} ->
        assign(socket, :preference_details, details)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Preference not found")
        |> push_navigate(to: ~p"/preferences")
    end
  end

  defp load_validation_rules(socket) do
    preference_key = socket.assigns.preference_key

    case PreferenceValidation.by_preference_key(preference_key) do
      {:ok, [validation]} ->
        assign(socket, :validation_rules, validation)

      {:ok, []} ->
        assign(socket, :validation_rules, %{})

      {:error, _} ->
        assign(socket, :validation_rules, %{})
    end
  end

  defp prepare_form(socket) do
    preference_details = socket.assigns.preference_details

    initial_params = %{
      "value" => preference_details.current_value,
      "category" => preference_details.category,
      "reason" => "",
      "override_inheritance" => false
    }

    changeset = create_preference_changeset(initial_params, socket.assigns.validation_rules)

    socket
    |> assign(:changeset, changeset)
    |> assign(:form, to_form(changeset))
  end

  defp get_preference_details(user_id, preference_key, project_id) do
    case SystemDefault.by_preference_key(preference_key) do
      {:ok, [default]} ->
        current_value =
          case PreferenceResolver.resolve(user_id, preference_key, project_id) do
            {:ok, value} -> value
            {:error, _} -> default.default_value
          end

        user_value =
          case UserPreference.by_user_and_key(user_id, preference_key) do
            {:ok, [user_pref]} -> user_pref.value
            _ -> nil
          end

        details = %{
          key: preference_key,
          description: default.description,
          category: default.category,
          data_type: default.data_type,
          constraints: default.constraints,
          default_value: default.default_value,
          current_value: current_value,
          user_value: user_value,
          # TODO: Implement project value lookup
          project_value: nil,
          source: determine_preference_source(user_id, preference_key, project_id),
          allowed_values: get_allowed_values(default.constraints),
          related_preferences: get_related_preferences(default.category, preference_key)
        }

        {:ok, details}

      {:ok, []} ->
        {:error, "Preference not found"}

      error ->
        error
    end
  end

  defp determine_preference_source(user_id, preference_key, project_id) do
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [_user_pref]} -> resolve_user_or_project_source(project_id, preference_key)
      {:ok, []} -> "system"
      _ -> "unknown"
    end
  end

  defp resolve_user_or_project_source(nil, _preference_key), do: "user"

  defp resolve_user_or_project_source(project_id, preference_key) do
    case check_project_override(project_id, preference_key) do
      true -> "project"
      false -> "user"
    end
  end

  defp check_project_override(_project_id, _preference_key) do
    # TODO: Implement project override checking
    false
  end

  defp get_allowed_values(nil), do: []
  defp get_allowed_values(%{allowed_values: values}) when is_list(values), do: values
  defp get_allowed_values(_), do: []

  defp get_related_preferences(category, current_key) do
    case SystemDefault.by_category(category) do
      {:ok, defaults} ->
        defaults
        |> Enum.reject(&(&1.preference_key == current_key))
        |> Enum.take(5)
        |> Enum.map(&%{key: &1.preference_key, description: &1.description})

      _ ->
        []
    end
  end

  defp create_preference_changeset(params, _validation_rules) do
    types = %{
      value: :string,
      category: :string,
      reason: :string,
      override_inheritance: :boolean
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:value])
  end

  defp validate_preference_changes(params, validation_rules) do
    changes = %{(params["key"] || "unknown") => params["value"]}

    case ValidationInterfaceManager.validate_preference_changes(changes) do
      {:ok, validation_result} ->
        if validation_result.valid do
          create_preference_changeset(params, validation_rules)
        else
          create_preference_changeset(params, validation_rules)
          |> Ecto.Changeset.add_error(:value, "Validation failed")
        end

      {:error, _reason} ->
        create_preference_changeset(params, validation_rules)
        |> Ecto.Changeset.add_error(:value, "Validation error")
    end
  end

  defp save_preference(user_id, nil, preference_key, params) do
    # Save as user preference
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [existing]} ->
        UserPreference.update(existing, %{value: params["value"]})

      {:ok, []} ->
        attrs = %{
          user_id: user_id,
          preference_key: preference_key,
          value: params["value"],
          category: params["category"] || get_preference_category(preference_key),
          source: :editor
        }

        UserPreference.create(attrs)

      error ->
        error
    end
  end

  defp save_preference(_user_id, _project_id, _preference_key, _params) do
    # TODO: Implement project preference saving
    {:error, "Project preferences not yet implemented"}
  end

  defp reset_preference_to_default(user_id, preference_key) do
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [user_pref]} ->
        UserPreference.destroy(user_pref)

      {:ok, []} ->
        {:ok, :already_default}

      error ->
        error
    end
  end

  defp get_preference_category(key) do
    key |> String.split(".") |> hd()
  end

  defp render_constraints_help(%{min: min, max: max}) do
    "Must be between #{min} and #{max}"
  end

  defp render_constraints_help(%{allowed_values: values}) when is_list(values) do
    "Allowed values: #{Enum.join(values, ", ")}"
  end

  defp render_constraints_help(%{pattern: pattern}) do
    "Must match pattern: #{pattern}"
  end

  defp render_constraints_help(_), do: ""

  defp category_options do
    [
      {"LLM Configuration", "llm"},
      {"Machine Learning", "ml"},
      {"Code Quality", "code_quality"},
      {"Budgeting", "budgeting"},
      {"Security", "security"},
      {"Performance", "performance"},
      {"Other", "other"}
    ]
  end
end
