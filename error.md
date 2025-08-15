# KeyError at GET /

Exception:

    ** (KeyError) key :data_stream_rate not found in: %{
      total_nodes: "OFFLINE",
      current_load: "OFFLINE",
      active_nodes: "OFFLINE",
      active_zones: "OFFLINE",
      boundary_crossings: "OFFLINE",
      grid_efficiency: "OFFLINE",
      performance_ops: "OFFLINE",
      spatial_queries: "OFFLINE"
    }
        (thunderline 2.0.0) lib/thunderline_web/live/dashboard_live.html.heex:190: anonymous fn/2 in ThunderlineWeb.DashboardLive.render/1
        (phoenix_live_view 1.1.3) lib/phoenix_live_view/diff.ex:420: Phoenix.LiveView.Diff.traverse/6
        (phoenix_live_view 1.1.3) lib/phoenix_live_view/diff.ex:146: Phoenix.LiveView.Diff.render/4
        (phoenix_live_view 1.1.3) lib/phoenix_live_view/static.ex:291: Phoenix.LiveView.Static.to_rendered_content_tag/4
        (phoenix_live_view 1.1.3) lib/phoenix_live_view/static.ex:171: Phoenix.LiveView.Static.do_render/4
        (phoenix_live_view 1.1.3) lib/phoenix_live_view/controller.ex:39: Phoenix.LiveView.Controller.live_render/3
        (phoenix 1.8.0) lib/phoenix/router.ex:416: Phoenix.Router.__call__/5
        (thunderline 2.0.0) lib/thunderline_web/endpoint.ex:1: ThunderlineWeb.Endpoint.plug_builder_call/2
        (thunderline 2.0.0) deps/plug/lib/plug/debugger.ex:155: ThunderlineWeb.Endpoint."call (overridable 3)"/2
        (thunderline 2.0.0) lib/thunderline_web/endpoint.ex:1: ThunderlineWeb.Endpoint.call/2
        (phoenix 1.8.0) lib/phoenix/endpoint/sync_code_reload_plug.ex:22: Phoenix.Endpoint.SyncCodeReloadPlug.do_call/4
        (plug_cowboy 2.7.4) lib/plug/cowboy/handler.ex:11: Plug.Cowboy.Handler.init/2
        (cowboy 2.13.0) /home/mo/Thunderline/deps/cowboy/src/cowboy_handler.erl:37: :cowboy_handler.execute/2
        (cowboy 2.13.0) /home/mo/Thunderline/deps/cowboy/src/cowboy_stream_h.erl:310: :cowboy_stream_h.execute/3
        (cowboy 2.13.0) /home/mo/Thunderline/deps/cowboy/src/cowboy_stream_h.erl:299: :cowboy_stream_h.request_process/3
        (stdlib 5.2.3.5) proc_lib.erl:241: :proc_lib.init_p_do_apply/3
    

## Connection details

### Params

    %{}

### Request info

  * URI: http://localhost:4000/
  * Query string: 

### Session

    %{"_csrf_token" => "BylptYRyJotezRntjhuobq0_"}
