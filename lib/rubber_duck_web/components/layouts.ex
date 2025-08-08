defmodule RubberDuckWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RubberDuckWeb, :html

  @doc """
  Renders your app layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the current authenticated user"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar bg-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <.rubber_duck size="sm" />
          <span class="text-xl font-bold">RubberDuck</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <%= if @current_user do %>
            <li>
              <span class="text-sm">
                <%= @current_user.email || @current_user[:email] %>
              </span>
            </li>
            <li>
              <a href="/code" class="btn btn-ghost">Code</a>
            </li>
            <li>
              <form action="/sign-out" method="post">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <button type="submit" class="btn btn-ghost">Sign Out</button>
              </form>
            </li>
          <% else %>
            <li>
              <a href="/sign-in" class="btn btn-primary">Sign In</a>
            </li>
          <% end %>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="min-h-screen">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-4 right-4 z-50">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Hang in there while we get back on track
        <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      class={[
        "alert shadow-lg",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}
      role="alert"
      {@rest}
    >
      <.icon :if={@kind == :info} name="hero-information-circle" class="w-5 h-5" />
      <.icon :if={@kind == :error} name="hero-exclamation-circle" class="w-5 h-5" />
      <div>
        <h3 :if={@title} class="font-bold"><%= @title %></h3>
        <div class="text-sm"><%= msg %></div>
      </div>
      <button
        type="button"
        class="btn btn-sm btn-ghost"
        aria-label="close"
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      >
        ✕
      </button>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <label tabindex="0" class="btn btn-ghost btn-circle">
        <.icon name="hero-sun" class="w-5 h-5 swap-on" />
        <.icon name="hero-moon" class="w-5 h-5 swap-off" />
      </label>
      <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
        <li>
          <button phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="light">
            <.icon name="hero-sun" class="w-4 h-4" /> Light
          </button>
        </li>
        <li>
          <button phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="dark">
            <.icon name="hero-moon" class="w-4 h-4" /> Dark
          </button>
        </li>
        <li>
          <button phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system">
            <.icon name="hero-computer-desktop" class="w-4 h-4" /> System
          </button>
        </li>
      </ul>
    </div>
    """
  end

  embed_templates "layouts/*"
end