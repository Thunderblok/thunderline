defmodule ThunderlineWeb.Router do
  use ThunderlineWeb, :router
  # Bring in AshAuthentication Phoenix router macros (auth_routes, sign_in_route, etc.)
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThunderlineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  # NOTE: Removed AshAuthentication.Plug invocation because current
  # authentication flow relies on live_session on_mount hooks
  # (AshAuthentication.Phoenix.LiveSession + ThunderlineWeb.Live.Auth)
  # and the plug module emitted warnings (no init/call). If we later
  # need per-request user loading for non-LiveView controllers, we can
  # introduce a custom plug that verifies the session token and assigns
  # current_user.
  end

  pipeline :dashboard do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThunderlineWeb.Layouts, :dashboard}
    plug :put_layout, false
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :graphql do
    plug AshGraphql.Plug
  end

  scope "/", ThunderlineWeb do
    pipe_through :dashboard

  # Thunderline Nexus dashboard at root
  live "/", ThunderlineDashboardLive, :index
    # Legacy dashboard preserved at /dashboard (previous root)
    live "/dashboard", DashboardLive, :home
  # (Removed legacy /oko route after rebrand)
  end

  live_session :default, on_mount: [AshAuthentication.Phoenix.LiveSession, ThunderlineWeb.Live.Auth] do
    scope "/", ThunderlineWeb do
      pipe_through :browser

    # Individual domain dashboards
  live "/thundercore", DashboardLive, :thundercore
    live "/thunderbit", DashboardLive, :thunderbit
    live "/thunderbolt", DashboardLive, :thunderbolt
    live "/thunderblock", DashboardLive, :thunderblock
    live "/thundergrid", DashboardLive, :thundergrid
  # Removed legacy /thundervault route (vault now part of thunderblock domain metrics)
    live "/thundercom", DashboardLive, :thundercom
    live "/thundereye", DashboardLive, :thundereye
    live "/thunderchief", DashboardLive, :thunderchief
    live "/thunderflow", DashboardLive, :thunderflow
    live "/thunderstone", DashboardLive, :thunderstone
    live "/thunderlink", DashboardLive, :thunderlink
  live "/thundercrown", DashboardLive, :thundercrown
  # Cerebros & Raincatcher (drift lab) interface
  if System.get_env("ENABLE_CEREBROS") == "true" do
    live "/cerebros", CerebrosLive, :index
  end
  # Interactive neural network playground (inspired by external visualizer)
  if System.get_env("ENABLE_NN_PLAYGROUND") == "true" do
    live "/nn", NNPlaygroundLive, :index
  end

  # Discord-style community & channel navigation
  # /c/:community_slug -> community overview (channel list, description)
  # /c/:community_slug/:channel_slug -> specific channel chat view
  live "/c/:community_slug", CommunityLive, :show
  live "/c/:community_slug/:channel_slug", ChannelLive, :show

    # Thunderlane Specialized Dashboard
  live "/dashboard/thunderlane", ThunderlineDashboard, :index

    # 3D Cellular Automata View
  live "/automata", AutomataLive, :index

    # Hologram 3D CA Visualization
  live "/ca-3d", CaVisualizationLive, :index

    # Admin and monitoring
      live "/metrics", MetricsLive, :index
    end
  end

  # Authentication routes & UI (sign in, registration, reset, strategy endpoints)
  scope "/" do
    pipe_through :browser

    # White-label sign-in (mounts live_session with AshAuthentication hooks)
    sign_in_route(path: "/sign-in", auth_routes_prefix: "/auth")

    # Password reset request & reset form
    reset_route(auth_routes_prefix: "/auth")

    # Strategy/router endpoints for our User resource
    auth_routes(ThunderlineWeb.AuthController, Thunderline.Thundergate.Resources.User, path: "/auth")

    # Optional sign-out endpoint (controller sign_out action)
    sign_out_route ThunderlineWeb.AuthController, "/sign-out"
  end

  # API routes for external integrations
  scope "/api", ThunderlineWeb do
    pipe_through :api

    get "/metrics", MetricsController, :index
    get "/health", HealthController, :check
    get "/domains/:domain/stats", DomainStatsController, :show
  end

  # GraphQL API
  scope "/gql" do
    pipe_through [:graphql]

    forward "/playground",
            Absinthe.Plug.GraphiQL,
            schema: Module.concat(["ThunderlineWeb.GraphqlSchema"]),
            interface: :playground

    forward "/",
      Absinthe.Plug,
      schema: Module.concat(["ThunderlineWeb.GraphqlSchema"])
  end

  # LiveDashboard for development
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dev/dashboard", metrics: ThunderlineWeb.Telemetry
    end
  end
end
