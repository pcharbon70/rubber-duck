defmodule RubberDuckWeb.Router do
  use RubberDuckWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {RubberDuckWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:load_from_session)
  end

  pipeline :api do
    plug(:accepts, ["json"])

    plug(AshAuthentication.Strategy.ApiKey.Plug,
      resource: RubberDuck.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false
    )

    plug(:load_from_bearer)
    plug(:set_actor, :user)
  end

  scope "/", RubberDuckWeb do
    pipe_through(:browser)

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {RubberDuckWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {RubberDuckWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {RubberDuckWeb.LiveUserAuth, :live_no_user}

      # Preference Management Routes
      live("/preferences", Preferences.DashboardLive, :index)
      live("/preferences/templates", Preferences.TemplateBrowserLive, :index)
      live("/preferences/analytics", Preferences.AnalyticsLive, :index)
      live("/preferences/edit/:key", Preferences.CategoryEditorLive, :edit)
      live("/preferences/approvals", Preferences.ApprovalWorkflowLive, :index)
    end
  end

  scope "/", RubberDuckWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    auth_routes(AuthController, RubberDuck.Accounts.User, path: "/auth")
    sign_out_route(AuthController)

    # Remove these if you'd like to use your own authentication views
    sign_in_route(
      register_path: "/register",
      reset_path: "/reset",
      auth_routes_prefix: "/auth",
      on_mount: [{RubberDuckWeb.LiveUserAuth, :live_no_user}],
      overrides: [
        RubberDuckWeb.AuthOverrides,
        AshAuthentication.Phoenix.Overrides.Default
      ]
    )

    # Remove this if you do not want to use the reset password feature
    reset_route(
      auth_routes_prefix: "/auth",
      overrides: [
        RubberDuckWeb.AuthOverrides,
        AshAuthentication.Phoenix.Overrides.Default
      ]
    )

    # Remove this if you do not use the confirmation strategy
    confirm_route(RubberDuck.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [RubberDuckWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(RubberDuck.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [RubberDuckWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  # API Routes
  scope "/api", RubberDuckWeb.API do
    pipe_through(:api)

    # Preference Management API
    scope "/v1" do
      # Preferences CRUD
      get("/preferences", PreferencesController, :index)
      post("/preferences", PreferencesController, :create)
      get("/preferences/:id", PreferencesController, :show)
      put("/preferences/:id", PreferencesController, :update)
      delete("/preferences/:id", PreferencesController, :delete)
      post("/preferences/batch", PreferencesController, :batch)

      # Templates
      get("/templates", TemplatesController, :index)
      post("/templates", TemplatesController, :create)
      get("/templates/:id", TemplatesController, :show)
      put("/templates/:id", TemplatesController, :update)
      delete("/templates/:id", TemplatesController, :delete)
      post("/templates/:id/apply", TemplatesController, :apply)

      # Analytics
      get("/analytics/usage", AnalyticsController, :usage)
      get("/analytics/trends", AnalyticsController, :trends)
      get("/analytics/recommendations", AnalyticsController, :recommendations)
      get("/analytics/inheritance", AnalyticsController, :inheritance)
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:rubber_duck, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: RubberDuckWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end

    scope "/" do
      pipe_through(:browser)

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:rubber_duck, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through(:browser)

      ash_admin("/")
    end
  end
end
