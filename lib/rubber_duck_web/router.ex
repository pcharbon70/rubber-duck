defmodule RubberDuckWeb.Router do
  use RubberDuckWeb, :router
  use AshAuthentication.Phoenix.Router

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
    plug(:load_from_bearer)
  end

  scope "/", RubberDuckWeb do
    pipe_through(:browser)

    get("/", PageController, :home)

    # Demo authentication routes
    post("/demo-login", PageController, :demo_login)
    post("/demo-logout", PageController, :demo_logout)

    # Authentication routes with DaisyUI overrides
    auth_routes(AuthController, RubberDuck.Accounts.User, path: "/auth")
    sign_out_route(AuthController)

    # Sign in page with custom DaisyUI styling
    sign_in_route(
      overrides: [
        RubberDuckWeb.Auth.DaisyUIOverrides,
        AshAuthentication.Phoenix.Overrides.Default
      ],
      register_path: "/register",
      reset_path: "/password-reset"
    )

    # Protected routes
    live("/code", CollaborativeCodingLive)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:rubber_duck, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: RubberDuckWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
