defmodule RubberDuckWeb.Preferences.TemplateBrowserLive do
  @moduledoc """
  Template browser providing template discovery and application interface.

  Features:
  - Template library browsing with search and filtering
  - Template preview and detailed view
  - Template application with impact preview
  - Template creation from current preferences
  - Rating and review system
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Preferences.{PreferenceResolver, TemplateManager}

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_initial_state()
     |> load_templates()
     |> load_categories()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign_filters(params)
     |> apply_filters()}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> apply_filters()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    {:noreply,
     socket
     |> assign_filter_params(filter_params)
     |> apply_filters()}
  end

  @impl true
  def handle_event("preview_template", %{"template_id" => template_id}, socket) do
    case get_template_preview(template_id, socket.assigns.current_user.id) do
      {:ok, preview} ->
        {:noreply,
         socket
         |> assign(:selected_template, preview)
         |> assign(:show_preview, true)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to preview template: #{reason}")}
    end
  end

  @impl true
  def handle_event("apply_template", %{"template_id" => template_id}, socket) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project_id
    selective_keys = socket.assigns.selected_preferences || []

    result =
      if project_id do
        TemplateManager.apply_template_to_project(template_id, project_id, user_id,
          selective_keys: selective_keys,
          overwrite_existing: true
        )
      else
        TemplateManager.apply_template_to_user(template_id, user_id,
          selective_keys: selective_keys,
          overwrite_existing: true
        )
      end

    case result do
      {:ok, application_result} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Applied template successfully (#{application_result.applied_count} preferences)"
         )
         |> assign(:show_preview, false)
         |> assign(:selected_template, nil)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to apply template: #{reason}")}
    end
  end

  @impl true
  def handle_event("toggle_preference", %{"key" => key}, socket) do
    selected = socket.assigns.selected_preferences || []

    new_selected =
      if key in selected do
        List.delete(selected, key)
      else
        [key | selected]
      end

    {:noreply, assign(socket, :selected_preferences, new_selected)}
  end

  @impl true
  def handle_event("close_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_preview, false)
     |> assign(:selected_template, nil)
     |> assign(:selected_preferences, [])}
  end

  @impl true
  def handle_event("create_template", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/preferences/templates/create")}
  end

  @impl true
  def handle_event("rate_template", %{"template_id" => template_id, "rating" => rating}, socket) do
    user_id = socket.assigns.current_user.id

    case rate_template(template_id, user_id, String.to_integer(rating)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rating submitted successfully")
         |> load_templates()
         |> apply_filters()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to rate template: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="template-browser">
      <!-- Header -->
      <div class="mb-6">
        <div class="flex justify-between items-center">
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Template Library</h1>
            <p class="mt-1 text-sm text-gray-600">
              Discover and apply preference templates to quickly configure your settings
            </p>
          </div>
          <div class="flex space-x-3">
            <.link
              navigate={~p"/preferences"}
              class="btn btn-outline"
            >
              Back to Preferences
            </.link>
            <button
              phx-click="create_template"
              class="btn btn-primary"
            >
              Create Template
            </button>
          </div>
        </div>
      </div>

      <!-- Search and Filters -->
      <div class="bg-white rounded-lg shadow mb-6">
        <div class="p-6">
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <!-- Search -->
            <div class="md:col-span-2">
              <.form
                for={%{}}
                as={:search}
                phx-change="search"
                class="flex"
              >
                <.input
                  type="search"
                  name="query"
                  value={@search_query}
                  placeholder="Search templates..."
                  class="flex-1"
                />
              </.form>
            </div>

            <!-- Category Filter -->
            <div>
              <.form
                for={%{}}
                as={:filter}
                phx-change="filter"
              >
                <.input
                  type="select"
                  name="category"
                  value={@filter_category}
                  options={[{"All Categories", ""} | category_options()]}
                  class="block w-full"
                />
              </.form>
            </div>

            <!-- Type Filter -->
            <div>
              <.form
                for={%{}}
                as={:filter}
                phx-change="filter"
              >
                <.input
                  type="select"
                  name="type"
                  value={@filter_type}
                  options={[
                    {"All Types", ""},
                    {"Private", "private"},
                    {"Team", "team"},
                    {"Public", "public"}
                  ]}
                  class="block w-full"
                />
              </.form>
            </div>
          </div>
        </div>
      </div>

      <!-- Template Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for template <- @filtered_templates do %>
          <div class="bg-white rounded-lg shadow hover:shadow-lg transition-shadow duration-200">
            <!-- Template Header -->
            <div class="p-6">
              <div class="flex items-start justify-between mb-4">
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-medium text-gray-900 truncate">
                    <%= template.name %>
                  </h3>
                  <p class="text-sm text-gray-500 mt-1">
                    by <%= template.created_by || "System" %>
                  </p>
                </div>
                <div class="ml-4 flex-shrink-0">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    case template.template_type do
                      :private -> "bg-gray-100 text-gray-800"
                      :team -> "bg-blue-100 text-blue-800"
                      :public -> "bg-green-100 text-green-800"
                      _ -> "bg-gray-100 text-gray-800"
                    end
                  ]}>
                    <%= String.capitalize(to_string(template.template_type)) %>
                  </span>
                </div>
              </div>

              <!-- Description -->
              <p class="text-sm text-gray-600 mb-4 line-clamp-3">
                <%= template.description %>
              </p>

              <!-- Stats -->
              <div class="flex items-center justify-between text-sm text-gray-500 mb-4">
                <div class="flex items-center space-x-4">
                  <div class="flex items-center">
                    <svg class="h-4 w-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
                    </svg>
                    <%= map_size(template.preferences) %> preferences
                  </div>
                  <div class="flex items-center">
                    <svg class="h-4 w-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
                    </svg>
                    <%= template.usage_count || 0 %> uses
                  </div>
                </div>

                <!-- Rating -->
                <%= if template.rating do %>
                  <div class="flex items-center">
                    <%= for i <- 1..5 do %>
                      <svg class={[
                        "h-4 w-4",
                        if(template.rating && i <= trunc(template.rating), do: "text-yellow-400", else: "text-gray-300")
                      ]} fill="currentColor" viewBox="0 0 20 20">
                        <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                      </svg>
                    <% end %>
                    <span class="ml-1 text-xs">
                      <%= Float.round(template.rating, 1) %>
                    </span>
                  </div>
                <% end %>
              </div>

              <!-- Categories -->
              <div class="flex flex-wrap gap-1 mb-4">
                <%= for category <- template.categories do %>
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                    <%= String.capitalize(category) %>
                  </span>
                <% end %>
              </div>

              <!-- Actions -->
              <div class="flex space-x-2">
                <button
                  phx-click="preview_template"
                  phx-value-template_id={template.template_id}
                  class="flex-1 btn btn-outline btn-sm"
                >
                  Preview
                </button>
                <button
                  phx-click="apply_template"
                  phx-value-template_id={template.template_id}
                  data-confirm="Apply this template to your preferences?"
                  class="flex-1 btn btn-primary btn-sm"
                >
                  Apply
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Empty State -->
      <%= if length(@filtered_templates) == 0 do %>
        <div class="text-center py-12">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No templates found</h3>
          <p class="mt-1 text-sm text-gray-500">
            <%= if @search_query != "" do %>
              No templates match your search criteria.
            <% else %>
              Get started by creating your first template.
            <% end %>
          </p>
          <div class="mt-6">
            <button
              phx-click="create_template"
              class="btn btn-primary"
            >
              Create Template
            </button>
          </div>
        </div>
      <% end %>
    </div>

    <!-- Template Preview Modal -->
    <%= if @show_preview and @selected_template do %>
      <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50" id="template-preview-modal">
        <div class="relative top-20 mx-auto p-5 border w-11/12 md:w-3/4 lg:w-1/2 shadow-lg rounded-md bg-white">
          <!-- Modal Header -->
          <div class="flex items-start justify-between mb-6">
            <div>
              <h3 class="text-lg font-medium text-gray-900">
                <%= @selected_template.name %>
              </h3>
              <p class="text-sm text-gray-500">
                Template Preview
              </p>
            </div>
            <button
              phx-click="close_preview"
              class="text-gray-400 hover:text-gray-600"
            >
              <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Template Description -->
          <div class="mb-6">
            <h4 class="text-sm font-medium text-gray-900 mb-2">Description</h4>
            <p class="text-sm text-gray-600">
              <%= @selected_template.description %>
            </p>
          </div>

          <!-- Preference Changes -->
          <div class="mb-6">
            <div class="flex items-center justify-between mb-4">
              <h4 class="text-sm font-medium text-gray-900">
                Preference Changes (<%= length(@selected_template.changes) %>)
              </h4>
              <button
                type="button"
                onclick="toggleSelectAll()"
                class="text-sm text-blue-600 hover:text-blue-500"
              >
                Select All
              </button>
            </div>

            <div class="max-h-96 overflow-y-auto border border-gray-200 rounded-md">
              <%= for change <- @selected_template.changes do %>
                <div class={[
                  "flex items-center p-3 border-b border-gray-100",
                  if(change.type == "conflict", do: "bg-red-50", else: "bg-white")
                ]}>
                  <input
                    type="checkbox"
                    phx-click="toggle_preference"
                    phx-value-key={change.key}
                    checked={change.key in (@selected_preferences || [])}
                    class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded mr-3"
                  />
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center justify-between">
                      <h5 class="text-sm font-medium text-gray-900 truncate">
                        <%= change.key %>
                      </h5>
                      <%= if change.type == "conflict" do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                          Conflict
                        </span>
                      <% end %>
                    </div>
                    <div class="mt-1 flex items-center space-x-4 text-sm">
                      <%= if change.current_value do %>
                        <div>
                          <span class="text-gray-500">Current:</span>
                          <code class="bg-gray-100 px-1 py-0.5 rounded text-xs">
                            <%= change.current_value %>
                          </code>
                        </div>
                      <% end %>
                      <div>
                        <span class="text-gray-500">New:</span>
                        <code class="bg-green-100 px-1 py-0.5 rounded text-xs">
                          <%= change.new_value %>
                        </code>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Impact Summary -->
          <div class="mb-6 p-4 bg-blue-50 rounded-md">
            <h4 class="text-sm font-medium text-gray-900 mb-2">Impact Summary</h4>
            <div class="grid grid-cols-3 gap-4 text-sm">
              <div>
                <span class="font-medium text-green-600">
                  <%= @selected_template.summary.new_preferences %>
                </span>
                <span class="text-gray-600">new preferences</span>
              </div>
              <div>
                <span class="font-medium text-blue-600">
                  <%= @selected_template.summary.updated_preferences %>
                </span>
                <span class="text-gray-600">updates</span>
              </div>
              <div>
                <span class="font-medium text-red-600">
                  <%= @selected_template.summary.conflicts %>
                </span>
                <span class="text-gray-600">conflicts</span>
              </div>
            </div>
          </div>

          <!-- Rating -->
          <div class="mb-6">
            <h4 class="text-sm font-medium text-gray-900 mb-2">Rate this template</h4>
            <div class="flex items-center space-x-1">
              <%= for i <- 1..5 do %>
                <button
                  phx-click="rate_template"
                  phx-value-template_id={@selected_template.template_id}
                  phx-value-rating={i}
                  class="text-gray-300 hover:text-yellow-400 transition-colors"
                >
                  <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                  </svg>
                </button>
              <% end %>
            </div>
          </div>

          <!-- Modal Actions -->
          <div class="flex justify-end space-x-3">
            <button
              phx-click="close_preview"
              class="btn btn-outline"
            >
              Cancel
            </button>
            <button
              phx-click="apply_template"
              phx-value-template_id={@selected_template.template_id}
              class="btn btn-primary"
              data-confirm="Apply selected preferences from this template?"
            >
              Apply Selected (<%= length(@selected_preferences || []) %>)
            </button>
          </div>
        </div>
      </div>
    <% end %>

    <script>
      function toggleSelectAll() {
        const checkboxes = document.querySelectorAll('#template-preview-modal input[type="checkbox"]');
        const allChecked = Array.from(checkboxes).every(cb => cb.checked);
        checkboxes.forEach(cb => {
          if (allChecked) {
            cb.checked = false;
            cb.dispatchEvent(new Event('click', { bubbles: true }));
          } else if (!cb.checked) {
            cb.checked = true;
            cb.dispatchEvent(new Event('click', { bubbles: true }));
          }
        });
      }
    </script>
    """
  end

  # Private helper functions

  defp assign_initial_state(socket) do
    socket
    |> assign(:search_query, "")
    |> assign(:filter_category, "")
    |> assign(:filter_type, "")
    |> assign(:project_id, nil)
    |> assign(:all_templates, [])
    |> assign(:filtered_templates, [])
    |> assign(:categories, [])
    |> assign(:show_preview, false)
    |> assign(:selected_template, nil)
    |> assign(:selected_preferences, [])
  end

  defp assign_filters(socket, params) do
    socket
    |> assign(:search_query, params["search"] || "")
    |> assign(:filter_category, params["category"] || "")
    |> assign(:filter_type, params["type"] || "")
    |> assign(:project_id, params["project_id"])
  end

  defp assign_filter_params(socket, params) do
    socket
    |> assign(:filter_category, params["category"] || "")
    |> assign(:filter_type, params["type"] || "")
  end

  defp load_templates(socket) do
    case get_all_templates() do
      {:ok, templates} ->
        assign(socket, :all_templates, templates)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to load templates")
        |> assign(:all_templates, [])
    end
  end

  defp load_categories(socket) do
    categories = ["llm", "ml", "code_quality", "budgeting", "security", "performance", "other"]
    assign(socket, :categories, categories)
  end

  defp apply_filters(socket) do
    templates =
      socket.assigns.all_templates
      |> filter_by_search(socket.assigns.search_query)
      |> filter_by_category(socket.assigns.filter_category)
      |> filter_by_type(socket.assigns.filter_type)

    assign(socket, :filtered_templates, templates)
  end

  defp filter_by_search(templates, ""), do: templates

  defp filter_by_search(templates, query) do
    query = String.downcase(query)

    Enum.filter(templates, fn template ->
      String.contains?(String.downcase(template.name), query) or
        String.contains?(String.downcase(template.description), query)
    end)
  end

  defp filter_by_category(templates, ""), do: templates

  defp filter_by_category(templates, category) do
    Enum.filter(templates, fn template ->
      category in (template.categories || [])
    end)
  end

  defp filter_by_type(templates, ""), do: templates

  defp filter_by_type(templates, type) do
    Enum.filter(templates, &(to_string(&1.template_type) == type))
  end

  defp get_all_templates do
    # Mock template data for now
    templates = [
      %{
        template_id: "template_1",
        name: "Development Setup",
        description:
          "Optimized settings for software development with enhanced code quality checks and ML assistance.",
        template_type: :public,
        categories: ["code_quality", "ml"],
        created_by: "System",
        preferences: %{
          "code_quality.global.enabled" => true,
          "ml.training.enabled" => true,
          "llm.providers.primary" => "anthropic"
        },
        rating: 4.5,
        usage_count: 127
      },
      %{
        template_id: "template_2",
        name: "Performance Optimized",
        description:
          "High-performance configuration with optimized LLM selection and reduced overhead.",
        template_type: :public,
        categories: ["performance", "llm"],
        created_by: "System",
        preferences: %{
          "llm.providers.primary" => "openai",
          "performance.cache.enabled" => true,
          "budgeting.enabled" => false
        },
        rating: 4.2,
        usage_count: 89
      },
      %{
        template_id: "template_3",
        name: "Budget Conscious",
        description:
          "Cost-effective settings with strict budgeting controls and efficient resource usage.",
        template_type: :public,
        categories: ["budgeting", "performance"],
        created_by: "Community",
        preferences: %{
          "budgeting.enabled" => true,
          "budgeting.monthly_limit" => 50.0,
          "llm.providers.primary" => "openai",
          "performance.batch_size" => 10
        },
        rating: 4.1,
        usage_count: 203
      }
    ]

    {:ok, templates}
  end

  defp get_template_preview(template_id, user_id) do
    case find_template_by_id(template_id) do
      nil -> {:error, "Template not found"}
      template -> build_template_preview(template, user_id)
    end
  end

  defp find_template_by_id(template_id) do
    {:ok, templates} = get_all_templates()
    Enum.find(templates, &(&1.template_id == template_id))
  end

  defp build_template_preview(template, user_id) do
    changes = build_preference_changes(template.preferences, user_id)
    summary = build_changes_summary(changes)

    preview = Map.merge(template, %{changes: changes, summary: summary})
    {:ok, preview}
  end

  defp build_preference_changes(preferences, user_id) do
    Enum.map(preferences, &build_preference_change(user_id, &1))
  end

  defp build_preference_change(user_id, {key, new_value}) do
    current_value = get_current_preference_value(user_id, key)
    change_type = determine_change_type(current_value, new_value)

    %{
      key: key,
      current_value: current_value,
      new_value: new_value,
      type: change_type
    }
  end

  defp get_current_preference_value(user_id, key) do
    case PreferenceResolver.resolve(user_id, key) do
      {:ok, value} -> value
      {:error, _} -> nil
    end
  end

  defp determine_change_type(current_value, new_value) do
    case {current_value, new_value} do
      {nil, _} -> "new"
      {current, new} when current != new -> "conflict"
      _ -> "new"
    end
  end

  defp build_changes_summary(changes) do
    %{
      new_preferences: Enum.count(changes, &(&1.type == "new")),
      updated_preferences: Enum.count(changes, &(&1.type == "conflict")),
      conflicts: Enum.count(changes, &(&1.type == "conflict"))
    }
  end

  defp rate_template(_template_id, _user_id, _rating) do
    # TODO: Implement actual template rating
    {:ok, :rated}
  end

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
