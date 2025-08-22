defmodule Thunderline.Boot.Resurrector do
  @moduledoc """Heals on boot if a pending resurrection marker exists."""
  use GenServer
  alias Thunderline.Persistence.Checkpoint
  alias Thunderline.Log.NDJSON

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(_), do: (Process.send_after(self(), :maybe_resurrect, 0); {:ok, %{}})

  def handle_info(:maybe_resurrect, s) do
    case Checkpoint.read() do
      {:ok, %{"pending" => true} = m} -> do_resurrect(m)
      {:ok, %{pending: true} = m}     -> do_resurrect(m)
      _ -> :noop
    end
    {:noreply, s}
  end

  defp do_resurrect(m) do
    case Map.get(m, :daisy_snapshot) || Map.get(m, "daisy_snapshot") do
      nil -> :ok
      snap -> Thunderline.Daisy.restore_all_swarms(snap)
    end
    pll = Map.get(m, :pll_state) || Map.get(m, "pll_state") || %{"phi" => 0.0, "omega" => 0.25, "eps" => 0.1, "kappa" => 0.05}
    echo = Map.get(m, :echo_window) || Map.get(m, "echo_window") || []
    Thunderline.Current.Sensor.restore(%{pll: pll, echo: echo})
    NDJSON.write(%{event: "resumed", reason: Map.get(m, :reason) || Map.get(m, "reason") || "unknown", gate_ts: Map.get(m, :gate_ts) || Map.get(m, "gate_ts")})
    Checkpoint.mark_pending(false, "resumed")
    :ok
  end
end
