ExUnit.start(assert_receive_timeout: 200)

# Keep optional subsystems off unless a test opts in.
Application.put_env(:thunderline, :minimal_test_boot, true)
Application.put_env(:thunderline, :features, [])
Application.put_env(:thunderline, :cerebros_bridge, [enabled: false, invoke: [default_timeout_ms: 100], cache: [ttl_ms: 1000, max_entries: 64]])
Application.put_env(:thunderline, :vim, [enabled: false, shadow_mode: true])

{:ok, _} = Application.ensure_all_started(:thunderline)

unless System.get_env("SKIP_ASH_SETUP") in ["1", "true"] do
  # Ensure repo is in manual mode then checkout a shared connection for global processes
  Ecto.Adapters.SQL.Sandbox.mode(Thunderline.Repo, :manual)
  {:ok, _pid} = Ecto.Adapters.SQL.Sandbox.start_owner!(Thunderline.Repo, shared: true)
end

# Optional deeper debug hooks can be toggled locally when needed
# Logger.configure(level: :debug)
