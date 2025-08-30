ExUnit.start(assert_receive_timeout: 200)

# Minimal baseline flags/config to avoid optional supervisors unless explicitly enabled in a test
Application.put_env(:thunderline, :features, [])
Application.put_env(:thunderline, :cerebros_bridge, [enabled: false, invoke: [default_timeout_ms: 100], cache: [ttl_ms: 1000, max_entries: 64]])
Application.put_env(:thunderline, :vim, [enabled: false, shadow_mode: true])

unless System.get_env("SKIP_ASH_SETUP") in ["1", "true"] do
	Ecto.Adapters.SQL.Sandbox.mode(Thunderline.Repo, :manual)
end

# Start the application tree (after sandbox config)
{:ok, _} = Application.ensure_all_started(:thunderline)

# Extra visibility for unusual early VM halts (temporary – remove once CI is green)
Logger.configure(level: :warning)
:telemetry.attach_many(
	"vm-halt-debug",
	[[:vm, :system, :halt]],
	fn event, meas, meta, _ ->
		IO.puts("[VM HALT TELEMETRY] event=#{inspect(event)} meas=#{inspect(meas)} meta=#{inspect(meta)}")
	end,
	nil
)
