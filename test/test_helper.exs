ExUnit.start()

unless System.get_env("SKIP_ASH_SETUP") in ["1", "true"] do
	Ecto.Adapters.SQL.Sandbox.mode(Thunderline.Repo, :manual)
end
