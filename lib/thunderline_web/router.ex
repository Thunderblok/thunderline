defmodule ThunderlineWeb.Router do
  use ThunderlineWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThunderlineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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

    # Main Thunderblock Dashboard - Real-time LiveView
    live "/", DashboardLive, :home
  end

  scope "/", ThunderlineWeb do
    pipe_through :browser

    # Individual domain dashboards
    live "/thundercore", DashboardLive, :thundercore
    live "/thunderbit", DashboardLive, :thunderbit
    live "/thunderbolt", DashboardLive, :thunderbolt
    live "/thunderblock", DashboardLive, :thunderblock
    live "/thundergrid", DashboardLive, :thundergrid
    live "/thundervault", DashboardLive, :thundervault
    live "/thundercom", DashboardLive, :thundercom
    live "/thundereye", DashboardLive, :thundereye
    live "/thunderchief", DashboardLive, :thunderchief
    live "/thunderflow", DashboardLive, :thunderflow
    live "/thunderstone", DashboardLive, :thunderstone
    live "/thunderlink", DashboardLive, :thunderlink
    live "/thundercrown", DashboardLive, :thundercrown

    # Thunderlane Specialized Dashboard
    live "/dashboard/thunderlane", ThunderlineWeb.Live.Components.ThunderlaneDashboard, :index

    # 3D Cellular Automata View
    live "/automata", AutomataLive, :index

    # Hologram 3D CA Visualization
    live "/ca-3d", CaVisualizationLive, :index

    # Admin and monitoring
    live "/metrics", MetricsLive, :index
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
