defmodule RubberDuckWeb.Preferences.ApprovalWorkflowLive do
  @moduledoc """
  Approval workflow interface for preference change requests.

  Features:
  - Pending approval queue management
  - Change request review interface
  - Approval/rejection workflows
  - Comprehensive audit trails
  - Bulk approval operations
  """

  use RubberDuckWeb, :live_view

  alias RubberDuck.Preferences.ApprovalManager

  # LiveView mount requires authentication
  on_mount({RubberDuckWeb.LiveUserAuth, :live_user_required})

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to approval changes for real-time updates
      subscribe_to_approval_events()
    end

    {:ok,
     socket
     |> assign_initial_state()
     |> load_pending_approvals()
     |> load_approval_history()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign_filters(params)
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
  def handle_event("approve_request", %{"approval_id" => approval_id}, socket) do
    user_id = socket.assigns.current_user.id

    case ApprovalManager.approve_request(approval_id, user_id) do
      {:ok, _approval} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request approved successfully")
         |> load_pending_approvals()
         |> load_approval_history()
         |> apply_filters()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve request: #{reason}")}
    end
  end

  @impl true
  def handle_event("reject_request", %{"approval_id" => approval_id, "reason" => reason}, socket) do
    user_id = socket.assigns.current_user.id

    case ApprovalManager.reject_request(approval_id, user_id, reason) do
      {:ok, _approval} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request rejected")
         |> load_pending_approvals()
         |> load_approval_history()
         |> apply_filters()}

      {:error, error_reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reject request: #{error_reason}")}
    end
  end

  @impl true
  def handle_event("bulk_approve", %{"approval_ids" => approval_ids}, socket)
      when is_list(approval_ids) do
    user_id = socket.assigns.current_user.id

    case ApprovalManager.bulk_approve_requests(approval_ids, user_id) do
      {:ok, results} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved #{results.approved_count} requests")
         |> load_pending_approvals()
         |> load_approval_history()
         |> apply_filters()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Bulk approval failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("toggle_selection", %{"approval_id" => approval_id}, socket) do
    selected = socket.assigns.selected_approvals || []

    new_selected =
      if approval_id in selected do
        List.delete(selected, approval_id)
      else
        [approval_id | selected]
      end

    {:noreply, assign(socket, :selected_approvals, new_selected)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids = Enum.map(socket.assigns.filtered_approvals, & &1.id)
    {:noreply, assign(socket, :selected_approvals, all_ids)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_approvals, [])}
  end

  @impl true
  def handle_event("show_details", %{"approval_id" => approval_id}, socket) do
    case get_approval_details(approval_id) do
      {:ok, details} ->
        {:noreply,
         socket
         |> assign(:selected_approval, details)
         |> assign(:show_details_modal, true)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load details: #{reason}")}
    end
  end

  @impl true
  def handle_event("close_details", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_details_modal, false)
     |> assign(:selected_approval, nil)}
  end

  @impl true
  def handle_info({:approval_created, _approval}, socket) do
    {:noreply,
     socket
     |> load_pending_approvals()
     |> apply_filters()
     |> put_flash(:info, "New approval request received")}
  end

  @impl true
  def handle_info({:approval_updated, _approval}, socket) do
    {:noreply,
     socket
     |> load_pending_approvals()
     |> load_approval_history()
     |> apply_filters()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="approval-workflow">
      <!-- Header -->
      <div class="mb-6">
        <div class="flex justify-between items-center">
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Approval Workflow</h1>
            <p class="mt-1 text-sm text-gray-600">
              Manage preference change requests and approval workflows
            </p>
          </div>
          <div class="flex space-x-3">
            <.link
              navigate={~p"/preferences"}
              class="btn btn-outline"
            >
              Back to Preferences
            </.link>
          </div>
        </div>
      </div>
      
      <!-- Summary Stats -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-6">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-yellow-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.414L11 9.586V6z" clip-rule="evenodd"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Pending Approvals
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= length(@all_pending_approvals) %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-green-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Approved Today
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @stats.approved_today %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-red-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Rejected Today
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @stats.rejected_today %>
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-blue-500 rounded-md flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">
                    Avg Response Time
                  </dt>
                  <dd class="text-lg font-medium text-gray-900">
                    <%= @stats.avg_response_time %>h
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Filters and Actions -->
      <div class="bg-white shadow rounded-lg mb-6">
        <div class="p-6">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <!-- Filters -->
            <div class="flex items-center space-x-4">
              <div>
                <label class="text-sm font-medium text-gray-700 mr-2">Status:</label>
                <select 
                  phx-change="filter"
                  name="status"
                  value={@filter_status}
                  class="form-select rounded-md border-gray-300"
                >
                  <option value="">All</option>
                  <option value="pending">Pending</option>
                  <option value="approved">Approved</option>
                  <option value="rejected">Rejected</option>
                </select>
              </div>
              
              <div>
                <label class="text-sm font-medium text-gray-700 mr-2">Priority:</label>
                <select 
                  phx-change="filter"
                  name="priority"
                  value={@filter_priority}
                  class="form-select rounded-md border-gray-300"
                >
                  <option value="">All</option>
                  <option value="high">High</option>
                  <option value="medium">Medium</option>
                  <option value="low">Low</option>
                </select>
              </div>
              
              <div>
                <label class="text-sm font-medium text-gray-700 mr-2">Requester:</label>
                <select 
                  phx-change="filter"
                  name="requester"
                  value={@filter_requester}
                  class="form-select rounded-md border-gray-300"
                >
                  <option value="">All Users</option>
                  <%= for user <- @requesters do %>
                    <option value={user.id}><%= user.name %></option>
                  <% end %>
                </select>
              </div>
            </div>
            
            <!-- Bulk Actions -->
            <%= if length(@selected_approvals || []) > 0 do %>
              <div class="flex items-center space-x-2">
                <span class="text-sm text-gray-600">
                  <%= length(@selected_approvals) %> selected
                </span>
                <button
                  phx-click="bulk_approve"
                  phx-value-approval_ids={Jason.encode!(@selected_approvals)}
                  data-confirm="Approve all selected requests?"
                  class="btn btn-sm btn-green"
                >
                  Bulk Approve
                </button>
                <button
                  phx-click="clear_selection"
                  class="btn btn-sm btn-outline"
                >
                  Clear Selection
                </button>
              </div>
            <% else %>
              <div class="flex items-center space-x-2">
                <button
                  phx-click="select_all"
                  class="btn btn-sm btn-outline"
                >
                  Select All
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
      <!-- Approvals List -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h3 class="text-lg font-medium text-gray-900">
            Approval Requests (<%= length(@filtered_approvals) %>)
          </h3>
        </div>
        
        <%= if length(@filtered_approvals) > 0 do %>
          <div class="divide-y divide-gray-200">
            <%= for approval <- @filtered_approvals do %>
              <div class="p-6 hover:bg-gray-50">
                <div class="flex items-start">
                  <!-- Selection Checkbox -->
                  <input
                    type="checkbox"
                    phx-click="toggle_selection"
                    phx-value-approval_id={approval.id}
                    checked={approval.id in (@selected_approvals || [])}
                    class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded mt-1 mr-4"
                  />
                  
                  <!-- Main Content -->
                  <div class="flex-1 min-w-0">
                    <div class="flex items-start justify-between">
                      <div class="flex-1">
                        <!-- Request Header -->
                        <div class="flex items-center space-x-2 mb-2">
                          <h4 class="text-sm font-medium text-gray-900">
                            <%= approval.preference_key %>
                          </h4>
                          <span class={[
                            "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                            priority_color(approval.priority)
                          ]}>
                            <%= String.capitalize(approval.priority) %>
                          </span>
                          <span class={[
                            "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                            status_color(approval.status)
                          ]}>
                            <%= String.capitalize(approval.status) %>
                          </span>
                        </div>
                        
                        <!-- Request Details -->
                        <div class="text-sm text-gray-600 mb-2">
                          <p><strong>Requested by:</strong> <%= approval.requested_by %></p>
                          <p><strong>Reason:</strong> <%= approval.reason %></p>
                        </div>
                        
                        <!-- Value Changes -->
                        <div class="flex items-center space-x-4 text-sm mb-3">
                          <%= if approval.old_value do %>
                            <div>
                              <span class="text-gray-500">Current:</span>
                              <code class="bg-gray-100 px-2 py-1 rounded text-xs ml-1">
                                <%= approval.old_value %>
                              </code>
                            </div>
                          <% end %>
                          <div>
                            <span class="text-gray-500">New:</span>
                            <code class="bg-green-100 px-2 py-1 rounded text-xs ml-1">
                              <%= approval.new_value %>
                            </code>
                          </div>
                        </div>
                        
                        <!-- Metadata -->
                        <div class="flex items-center text-xs text-gray-500 space-x-4">
                          <span>Requested <%= time_ago(approval.created_at) %></span>
                          <%= if approval.project_id do %>
                            <span>Project: <%= approval.project_name || approval.project_id %></span>
                          <% end %>
                          <span>Category: <%= approval.category %></span>
                        </div>
                      </div>
                      
                      <!-- Actions -->
                      <div class="ml-4 flex-shrink-0 flex items-center space-x-2">
                        <button
                          phx-click="show_details"
                          phx-value-approval_id={approval.id}
                          class="text-sm text-blue-600 hover:text-blue-500"
                        >
                          Details
                        </button>
                        
                        <%= if approval.status == "pending" do %>
                          <button
                            phx-click="approve_request"
                            phx-value-approval_id={approval.id}
                            class="btn btn-sm btn-green"
                          >
                            Approve
                          </button>
                          <button
                            onclick={"showRejectModal('#{approval.id}')"}
                            class="btn btn-sm btn-red"
                          >
                            Reject
                          </button>
                        <% else %>
                          <div class="flex items-center text-sm text-gray-500">
                            <%= if approval.reviewed_by do %>
                              <span>by <%= approval.reviewed_by %></span>
                            <% end %>
                            <span class="ml-2"><%= time_ago(approval.updated_at) %></span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="p-8 text-center">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No approval requests</h3>
            <p class="mt-1 text-sm text-gray-500">
              No requests match your current filters.
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Details Modal -->
    <%= if @show_details_modal and @selected_approval do %>
      <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
        <div class="relative top-20 mx-auto p-5 border w-11/12 md:w-3/4 lg:w-1/2 shadow-lg rounded-md bg-white">
          <!-- Modal Header -->
          <div class="flex items-start justify-between mb-6">
            <div>
              <h3 class="text-lg font-medium text-gray-900">
                Approval Request Details
              </h3>
              <p class="text-sm text-gray-500 mt-1">
                <%= @selected_approval.preference_key %>
              </p>
            </div>
            <button
              phx-click="close_details"
              class="text-gray-400 hover:text-gray-600"
            >
              <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          
          <!-- Request Information -->
          <div class="space-y-6">
            <div>
              <h4 class="text-sm font-medium text-gray-900 mb-3">Request Information</h4>
              <dl class="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <dt class="font-medium text-gray-500">Requested by</dt>
                  <dd class="text-gray-900"><%= @selected_approval.requested_by %></dd>
                </div>
                <div>
                  <dt class="font-medium text-gray-500">Priority</dt>
                  <dd class="text-gray-900">
                    <span class={[
                      "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                      priority_color(@selected_approval.priority)
                    ]}>
                      <%= String.capitalize(@selected_approval.priority) %>
                    </span>
                  </dd>
                </div>
                <div>
                  <dt class="font-medium text-gray-500">Status</dt>
                  <dd class="text-gray-900">
                    <span class={[
                      "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                      status_color(@selected_approval.status)
                    ]}>
                      <%= String.capitalize(@selected_approval.status) %>
                    </span>
                  </dd>
                </div>
                <div>
                  <dt class="font-medium text-gray-500">Created</dt>
                  <dd class="text-gray-900"><%= time_ago(@selected_approval.created_at) %></dd>
                </div>
              </dl>
            </div>
            
            <div>
              <h4 class="text-sm font-medium text-gray-900 mb-3">Change Details</h4>
              <div class="bg-gray-50 rounded-lg p-4">
                <div class="grid grid-cols-2 gap-4">
                  <%= if @selected_approval.old_value do %>
                    <div>
                      <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Current Value</dt>
                      <dd class="mt-1">
                        <code class="bg-white px-2 py-1 rounded text-sm border">
                          <%= @selected_approval.old_value %>
                        </code>
                      </dd>
                    </div>
                  <% end %>
                  <div>
                    <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Proposed Value</dt>
                    <dd class="mt-1">
                      <code class="bg-green-50 border-green-200 px-2 py-1 rounded text-sm border">
                        <%= @selected_approval.new_value %>
                      </code>
                    </dd>
                  </div>
                </div>
              </div>
            </div>
            
            <div>
              <h4 class="text-sm font-medium text-gray-900 mb-3">Justification</h4>
              <div class="bg-gray-50 rounded-lg p-4">
                <p class="text-sm text-gray-700">
                  <%= @selected_approval.reason %>
                </p>
              </div>
            </div>
            
            <%= if @selected_approval.impact_analysis do %>
              <div>
                <h4 class="text-sm font-medium text-gray-900 mb-3">Impact Analysis</h4>
                <div class="bg-blue-50 rounded-lg p-4">
                  <p class="text-sm text-gray-700">
                    <%= @selected_approval.impact_analysis %>
                  </p>
                </div>
              </div>
            <% end %>
            
            <%= if @selected_approval.status != "pending" do %>
              <div>
                <h4 class="text-sm font-medium text-gray-900 mb-3">Review</h4>
                <div class={[
                  "rounded-lg p-4",
                  if @selected_approval.status == "approved" do
                    "bg-green-50"
                  else
                    "bg-red-50"
                  end
                ]}>
                  <div class="flex items-center mb-2">
                    <span class="text-sm font-medium text-gray-900">
                      <%= @selected_approval.reviewed_by %>
                    </span>
                    <span class="ml-2 text-xs text-gray-500">
                      <%= time_ago(@selected_approval.updated_at) %>
                    </span>
                  </div>
                  <%= if @selected_approval.review_comments do %>
                    <p class="text-sm text-gray-700">
                      <%= @selected_approval.review_comments %>
                    </p>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
          
          <!-- Modal Actions -->
          <%= if @selected_approval.status == "pending" do %>
            <div class="flex justify-end space-x-3 mt-6 pt-6 border-t border-gray-200">
              <button
                phx-click="close_details"
                class="btn btn-outline"
              >
                Close
              </button>
              <button
                phx-click="reject_request"
                phx-value-approval_id={@selected_approval.id}
                phx-value-reason="Rejected from details view"
                data-confirm="Reject this approval request?"
                class="btn btn-red"
              >
                Reject
              </button>
              <button
                phx-click="approve_request"
                phx-value-approval_id={@selected_approval.id}
                class="btn btn-green"
              >
                Approve
              </button>
            </div>
          <% else %>
            <div class="flex justify-end mt-6 pt-6 border-t border-gray-200">
              <button
                phx-click="close_details"
                class="btn btn-primary"
              >
                Close
              </button>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <script>
      function showRejectModal(approvalId) {
        const reason = prompt("Please provide a reason for rejection:");
        if (reason) {
          const event = new CustomEvent('phx:reject_request', {
            detail: { approval_id: approvalId, reason: reason }
          });
          document.dispatchEvent(event);
        }
      }
    </script>
    """
  end

  # Private helper functions

  defp assign_initial_state(socket) do
    socket
    |> assign(:filter_status, "")
    |> assign(:filter_priority, "")
    |> assign(:filter_requester, "")
    |> assign(:all_pending_approvals, [])
    |> assign(:filtered_approvals, [])
    |> assign(:approval_history, [])
    |> assign(:selected_approvals, [])
    |> assign(:show_details_modal, false)
    |> assign(:selected_approval, nil)
    |> assign(:stats, %{})
    |> assign(:requesters, [])
  end

  defp assign_filters(socket, params) do
    socket
    |> assign(:filter_status, params["status"] || "")
    |> assign(:filter_priority, params["priority"] || "")
    |> assign(:filter_requester, params["requester"] || "")
  end

  defp assign_filter_params(socket, params) do
    socket
    |> assign(:filter_status, params["status"] || "")
    |> assign(:filter_priority, params["priority"] || "")
    |> assign(:filter_requester, params["requester"] || "")
  end

  defp load_pending_approvals(socket) do
    approvals = get_all_approvals()
    stats = calculate_approval_stats()
    requesters = get_unique_requesters(approvals)

    socket
    |> assign(:all_pending_approvals, approvals)
    |> assign(:stats, stats)
    |> assign(:requesters, requesters)
  end

  defp load_approval_history(socket) do
    history = get_approval_history()
    assign(socket, :approval_history, history)
  end

  defp apply_filters(socket) do
    approvals =
      socket.assigns.all_pending_approvals
      |> filter_by_status(socket.assigns.filter_status)
      |> filter_by_priority(socket.assigns.filter_priority)
      |> filter_by_requester(socket.assigns.filter_requester)

    assign(socket, :filtered_approvals, approvals)
  end

  defp filter_by_status(approvals, ""), do: approvals

  defp filter_by_status(approvals, status) do
    Enum.filter(approvals, &(&1.status == status))
  end

  defp filter_by_priority(approvals, ""), do: approvals

  defp filter_by_priority(approvals, priority) do
    Enum.filter(approvals, &(&1.priority == priority))
  end

  defp filter_by_requester(approvals, ""), do: approvals

  defp filter_by_requester(approvals, requester_id) do
    Enum.filter(approvals, &(&1.requested_by_id == requester_id))
  end

  defp subscribe_to_approval_events do
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "approval_events")
  end

  # Mock data functions (would integrate with actual approval system)

  defp get_all_approvals do
    [
      %{
        id: "approval_1",
        preference_key: "code_quality.global.enabled",
        old_value: "false",
        new_value: "true",
        reason: "Enable code quality checks for better code standards",
        priority: "high",
        status: "pending",
        requested_by: "John Doe",
        requested_by_id: "user_1",
        project_id: "proj_1",
        project_name: "Main Project",
        category: "code_quality",
        created_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        updated_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      },
      %{
        id: "approval_2",
        preference_key: "llm.providers.primary",
        old_value: "openai",
        new_value: "anthropic",
        reason: "Switch to Anthropic for better performance on our use cases",
        priority: "medium",
        status: "approved",
        requested_by: "Jane Smith",
        requested_by_id: "user_2",
        project_id: nil,
        project_name: nil,
        category: "llm",
        created_at: DateTime.add(DateTime.utc_now(), -7200, :second),
        updated_at: DateTime.add(DateTime.utc_now(), -1800, :second),
        reviewed_by: "Admin User",
        review_comments: "Approved - good justification and testing plan"
      },
      %{
        id: "approval_3",
        preference_key: "budgeting.monthly_limit",
        old_value: "100",
        new_value: "200",
        reason: "Increase budget limit for expanded team usage",
        priority: "low",
        status: "pending",
        requested_by: "Bob Wilson",
        requested_by_id: "user_3",
        project_id: "proj_2",
        project_name: "Research Project",
        category: "budgeting",
        created_at: DateTime.add(DateTime.utc_now(), -1800, :second),
        updated_at: DateTime.add(DateTime.utc_now(), -1800, :second)
      }
    ]
  end

  defp calculate_approval_stats do
    %{
      approved_today: 5,
      rejected_today: 1,
      avg_response_time: 4.2
    }
  end

  defp get_unique_requesters(approvals) do
    approvals
    |> Enum.map(&%{id: &1.requested_by_id, name: &1.requested_by})
    |> Enum.uniq_by(& &1.id)
  end

  defp get_approval_history do
    # Mock implementation
    []
  end

  defp get_approval_details(approval_id) do
    case Enum.find(get_all_approvals(), &(&1.id == approval_id)) do
      nil ->
        {:error, "Approval not found"}

      approval ->
        {:ok,
         Map.merge(approval, %{
           impact_analysis:
             "This change will affect code quality checks across all project files."
         })}
    end
  end

  # View helpers

  defp priority_color("high"), do: "bg-red-100 text-red-800"
  defp priority_color("medium"), do: "bg-yellow-100 text-yellow-800"
  defp priority_color("low"), do: "bg-green-100 text-green-800"
  defp priority_color(_), do: "bg-gray-100 text-gray-800"

  defp status_color("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("approved"), do: "bg-green-100 text-green-800"
  defp status_color("rejected"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86_400)} days ago"
    end
  end
end
