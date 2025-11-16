ExUnit.start(assert_receive_timeout: 200)

# Keep optional subsystems off unless a test opts in.
Application.put_env(:thunderline, :minimal_test_boot, true)
Application.put_env(:thunderline, :features, [])

Application.put_env(:thunderline, :cerebros_bridge,
  enabled: false,
  invoke: [default_timeout_ms: 100],
  cache: [ttl_ms: 1000, max_entries: 64]
)

Application.put_env(:thunderline, :vim, enabled: false, shadow_mode: true)

# Start the application - this starts Oban in :manual testing mode
{:ok, _} = Application.ensure_all_started(:thunderline)

unless System.get_env("SKIP_ASH_SETUP") in ["1", "true"] do
  # Ensure repo is in manual mode then checkout a shared connection for global processes.
  # NOTE: start_owner!/2 returns the owner pid directly (NOT {:ok, pid}); using start_owner!/2
  # with a tuple pattern match caused a MatchError during test boot (WARHORSE fix).
  # We keep a single global owner so background processes (telemetry, pipelines in minimal mode)
  # can safely execute Repo calls. Per-test DataCase will detect this and skip creating another owner.
  Ecto.Adapters.SQL.Sandbox.mode(Thunderline.Repo, :manual)
  owner_pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Thunderline.Repo, shared: true)
  Application.put_env(:thunderline, :global_repo_owner, owner_pid)
end

# Optional deeper debug hooks can be toggled locally when needed
# Logger.configure(level: :debug)
