# Install / Wire-up

## 0) Deps (mix.exs)
Add (if not already present):
```elixir
{:jason, "~> 1.4"},
{:oban, "~> 2.18"},
{:phoenix_pubsub, "~> 2.1"}
```

## 1) Copy files
Drop `lib/` and `docs/` from this bundle into your Thunderline app.

## 2) Supervision Tree
In `application.ex`:
```elixir
children = [
  Thunderline.Repo,
  {Phoenix.PubSub, name: Thunderline.PubSub},
  ThunderlineWeb.Telemetry,
  ThunderlineWeb.Endpoint,
  {Oban, oban_config()},
  {Thunderline.Log.NDJSON, [path: "logs/probe.ndjson"]},
  {Thunderline.Persistence.Checkpoint, []},
  {Thunderline.Somatic.Engine, []},
  {Thunderline.Federated.Multiplex, []},
  {Thunderline.Daisy.Identity,  [name: Thunderline.Daisy.Identity]},
  {Thunderline.Daisy.Affect,    [name: Thunderline.Daisy.Affect]},
  {Thunderline.Daisy.Novelty,   [name: Thunderline.Daisy.Novelty]},
  {Thunderline.Daisy.Ponder,    [name: Thunderline.Daisy.Ponder]},
  {Thunderline.Thunderache.AcheDream, [name: Thunderline.Thunderache.AcheDream]},
  {Thunderline.Current.Sensor, []},
  {Thunderline.Cerebros.Inferencer, %{}},
  {Thunderline.Current.SafeClose, []},
  {Thunderline.Boot.Resurrector, []},
  # optional UPS watcher if you have NUT/apcupsd installed:
  {Thunderline.Hardware.UPS, []}
]
```

Before starting the above, call:
```elixir
Thunderline.Bus.init_tables()
```

## 3) LiveView HUD
Mount `ThunderlineWeb.DashboardLive` in your router to view the status banner + sparklines.

## 4) UPS env (optional)
```
UPS_BACKEND=nut|apcupsd
UPS_NAME=ups@localhost
UPS_POLL_MS=2000
UPS_CLOSE_TIMEOUT_MS=200
```

## 5) Run
Start the app. You should see `logs/probe.ndjson` fill and the HUD banner flip through
`prewindow → committed`. Kill the node → `resurrection_marker`. Start again → `resumed`.
