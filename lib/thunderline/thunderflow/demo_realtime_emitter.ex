defmodule Thunderline.Thunderflow.DemoRealtimeEmitter do
  @moduledoc """
  Demo realtime event emitter to drive the dashboard in environments
  where no upstream producers are yet generating realtime events.

  Emits a small burst of :dashboard_update and related realtime events
  every interval. Safe to run in dev/demo only; guarded by feature flag
  `:demo_realtime_emitter` or env `ENABLE_DEMO_EMITTER=1`.
  """
  use GenServer
  require Logger

  @interval 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if enabled?() do
      Logger.info("[DemoRealtimeEmitter] enabled; emitting every #{@interval}ms")
      schedule_tick()
      {:ok, %{seq: 0}}
    else
      Logger.info("[DemoRealtimeEmitter] disabled (feature flag or env not set)")
      :ignore
    end
  end

  defp enabled? do
    Application.get_env(:thunderline, :features, []) |> Enum.member?(:demo_realtime_emitter) or
      System.get_env("ENABLE_DEMO_EMITTER") in ["1", "true", "TRUE"]
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval)

  @impl true
  def handle_info(:tick, %{seq: seq} = state) do
    now = DateTime.utc_now()
    burst = demo_events(seq, now)

    Enum.each(burst, fn attrs ->
      case Thunderline.Event.new(attrs) do
        {:ok, ev} ->
          # Force realtime pipeline via meta + high priority so dashboard sees it fast
          ev = %{ev | meta: Map.put(ev.meta, :pipeline, :realtime), priority: :high}
          case Thunderline.EventBus.publish_event(ev) do
            {:ok, _} -> :ok
            {:error, reason} -> Logger.debug("[DemoRealtimeEmitter] drop #{inspect(reason)}")
          end
        {:error, errs} ->
          Logger.debug("[DemoRealtimeEmitter] invalid attrs #{inspect(errs)}")
      end
    end)

    schedule_tick()
    {:noreply, %{state | seq: seq + 1}}
  end

  defp demo_events(seq, now) do
    base = %{
      payload: %{},
      source: :flow,
      timestamp: now
    }

    [
      Map.merge(base, %{
        name: "dashboard_update.ops",
        type: :dashboard_update,
        payload: %{component: "kpi_panel", key: "ops", value: :rand.uniform(500), seq: seq}
      }),
      Map.merge(base, %{
        name: "dashboard_update.health",
        type: :dashboard_update,
        payload: %{component: "system_health", status: Enum.random([:ok, :warn, :crit]), seq: seq}
      }),
      Map.merge(base, %{
        name: "dashboard_update.chart",
        type: :dashboard_update,
        payload: %{component: "chart_data", key: "throughput", value: :rand.uniform(), seq: seq}
      })
    ]
  end
end
