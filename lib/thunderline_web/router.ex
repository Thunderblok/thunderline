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
    # Populate current_user for non-LiveView requests (e.g. AshAdmin forward)
    plug ThunderlineWeb.Plugs.LoadCurrentUser
  # NOTE: Removed AshAuthentication.Plug invocation because current
  # authentication flow relies on live_session on_mount hooks
  # (AshAuthentication.Phoenix.LiveSession + ThunderlineWeb.Live.Auth)
  # and the plug module emitted warnings (no init/call). If we later
  # need per-request user loading for non-LiveView controllers, we can
  # introduce a custom plug that verifies the session token and assigns
  # current_user.
  end

  # Demo security pipeline (rate limiting, basic auth, security headers)
  pipeline :demo_security do
    plug ThunderlineWeb.Plugs.DemoSecurity
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

  # MCP tool access pipeline (AshAI). API key auth optional initially; tighten later.
  pipeline :mcp do
    plug :accepts, ["json"]
    # TODO (FLAG-G1 follow-up): flip required?: true once API keys issued.
    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Thunderline.Thundergate.Resources.User,
      required?: false
  end

  pipeline :graphql do
    plug AshGraphql.Plug
  end

  pipeline :admin do
    plug ThunderlineWeb.Plugs.RequireRoles, roles: [:owner, :steward]
  end

  scope "/", ThunderlineWeb do
    # If DEMO_MODE enabled, insert demo_security pipeline before dashboard
    if System.get_env("DEMO_MODE") in ["1","true","TRUE"] do
      pipe_through [:demo_security, :dashboard]
    else
      pipe_through :dashboard
    end

  # Thunderline Nexus dashboard at root
  get "/probe_root", PageController, :probe
  live "/", ThunderlineDashboardLive, :index
    # Legacy dashboard preserved at /dashboard (previous root)
    live "/dashboard", DashboardLive, :home
  # (Removed legacy /oko route after rebrand)
  end

  live_session :default, on_mount: [AshAuthentication.Phoenix.LiveSession, ThunderlineWeb.Live.Auth] do
    scope "/", ThunderlineWeb do
      if System.get_env("DEMO_MODE") in ["1","true","TRUE"] do
        pipe_through [:demo_security, :browser]
      else
        pipe_through :browser
      end

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

  # Production MCP server (AshAI tools) - served separately from dev AshAi.Mcp.Dev plug.
  scope "/mcp" do
    pipe_through [:mcp]

    forward "/", AshAi.Mcp.Router,
      tools: [
        :run_agent
      ],
      # Until upstream clients adopt 2025-03-26, we default to older statement (overridable via env).
      protocol_version_statement: System.get_env("MCP_PROTOCOL_VERSION", "2024-11-05"),
      otp_app: :thunderline
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

  # Admin UI (AshAdmin) behind Gate roles; enable in all envs as needed
  scope "/admin" do
    pipe_through [:browser, :admin]

    forward "/", AshAdmin.Router,
      otp_app: :thunderline,
      apis: [
        Thunderline.Thunderblock.Domain,
        Thunderline.Thunderflow.Domain,
        Thunderline.Thunderlink.Domain,
        Thunderline.Thundercrown.Domain,
        Thunderline.Thundergate.Domain,
        Thunderline.Thundercom.Domain
      ]
  end
end
