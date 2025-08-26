defmodule Thunderline.Thunderbolt.Signal.Sensor do
  @moduledoc "Sensor pipeline (migrated from Thunderline.Current.Sensor). Performs token stream dynamics, PLL/Hilbert phase tracking, Daisy orchestration, and event logging."
  use GenServer
  alias Thunderline.EventBus
  alias Thunderline.Somatic.Embed, as: E
  alias Thunderline.Somatic.Engine, as: Somatic
  alias Thunderline.Thundercrown.Daisy, as: Daisy
  alias Thunderline.Thunderbolt.Signal.{PLL, Lease}
  alias Thunderline.Thunderbolt.Signal.Hilbert, as: H
  alias Thunderline.Thunderbolt.Signal.PLV, as: PLV
  alias Thunderline.Thunderbolt.Signal.CircStats
  alias Thunderline.Thunderflow.Observability.NDJSON

  @cap 64
  @spark_cap 32
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(_), do: (EventBus.subscribe("tokens"); EventBus.subscribe("events"); {:ok, %{pll: %PLL{}, hilb: H.new(63), prev: [], win: [], hist: [], h_prev: 0.0, commits_pll: [], commits_hil: []}})
  def restore(%{pll: pll, echo: echo}), do: GenServer.cast(__MODULE__, {:restore, pll, echo})
  def boundary_close(timeout_ms \\ 200), do: GenServer.call(__MODULE__, {:boundary_close, timeout_ms}, timeout_ms + 100)
  def handle_cast({:restore, pll_map, echo}, s) do
    pll = case pll_map do
      %{"phi" => phi, "omega" => om, "eps" => eps, "kappa" => k} -> %PLL{phi: phi, omega: om, eps: eps, kappa: k}
      %{phi: phi, omega: om, eps: eps, kappa: k} -> %PLL{phi: phi, omega: om, eps: eps, kappa: k}
      _ -> %PLL{}
    end
  EventBus.emit_realtime(:system_status, %{stage: "resumed_prepare", phi_pll: pll.phi})
    {:noreply, %{s | pll: pll, hist: (echo || []) ++ s.hist}}
  end
  def handle_info({:token, tok}, s) do
    win = ([to_string(tok) | s.win] |> Enum.take(16)) |> Enum.reverse()
    v   = velocity(win, s.prev)
    h_t = entropy(win)
    s_t = h_t - s.h_prev
    rho = recurrence(win, s.hist, 16)
    a   = Somatic.tag(tok)
    i   = identity_density(win)
    r   = dot(weights(), Map.values(a)) + 0.6 * i
    pulse = boundary?(tok, v, s_t) or rho > 0.8
    pll   = PLL.step(s.pll, pulse)
    g = sigmoid(2.0*r + 1.0*rho - 1.5*abs(s_t) - 1.0*v - 0.5)
    {hilb, phi_h} = H.step(s.hilb, g)
    if PLL.prewindow?(pll) and :ets.lookup(:daisy_lease, :lease) == [] do
      {inj, del} = Daisy.preview_all_swarms()
      :ets.insert(:daisy_lease, {:lease, Lease.make(inj, del, 120)})
  EventBus.emit_realtime(:system_status, %{stage: "prewindow", phi_pll: pll.phi, phi_h: phi_h, gate_score: g})
    end
    {commits_pll, commits_hil} =
      if PLL.gate?(pll, g) do
        case :ets.lookup(:daisy_lease, :lease) do
          [{:lease, lease}] -> unless Lease.expired?(lease) do
            :ets.delete(:daisy_lease, :lease)
              # Canonical Cerebros inferencer (domain-sorted under Thunderbolt.Cerebros)
              Thunderline.Thunderbolt.Cerebros.Inferencer.apply_injection(lease.inj && lease.inj[:shard] || lease.inj)
            Daisy.commit_all_swarms(lease.inj, lease.del)
            commits_pll1 = [pll.phi | s.commits_pll] |> Enum.take(@cap)
            commits_hil1 = [phi_h   | s.commits_hil] |> Enum.take(@cap)
            plv_pll = PLV.plv(commits_pll1)
            plv_h   = PLV.plv(commits_hil1)
            {rbar_pll, _z_pll, p_pll} = CircStats.rayleigh(commits_pll1)
            {rbar_h,   _z_h,   p_h}   = CircStats.rayleigh(commits_hil1)
            mu_pll = CircStats.mean_dir(commits_pll1)
            mu_h   = CircStats.mean_dir(commits_hil1)
            on_beat = (plv_pll >= 0.75 and plv_h >= 0.75 and p_pll <= 0.05 and p_h <= 0.05)
            EventBus.emit_realtime(:system_status, %{stage: "committed", phi_pll: pll.phi, phi_h: phi_h, plv_pll: Float.round(plv_pll, 3), plv_h: Float.round(plv_h, 3), p_pll: Float.round(p_pll, 4), p_h: Float.round(p_h, 4), rbar_pll: Float.round(rbar_pll, 3), rbar_h: Float.round(rbar_h, 3), mu_pll: mu_pll, mu_h: mu_h, on_beat: on_beat, phases_pll: Enum.take(commits_pll1, @spark_cap) |> Enum.reverse(), phases_h: Enum.take(commits_hil1, @spark_cap) |> Enum.reverse(), inj: short(lease.inj), del: short(lease.del)})
            NDJSON.write(%{event: "commit", phi_pll: pll.phi, phi_h: phi_h, plv_pll: plv_pll, plv_h: plv_h, rbar_pll: rbar_pll, p_pll: p_pll, rbar_h: rbar_h, p_h: p_h, mu_pll: mu_pll, mu_h: mu_h, on_beat: on_beat})
            {commits_pll1, commits_hil1}
          else {s.commits_pll, s.commits_hil} end
          _ -> {s.commits_pll, s.commits_hil}
        end
      else {s.commits_pll, s.commits_hil} end
    NDJSON.write(%{token: tok, v: v, s: s_t, rho: rho, a: a, i: i, phi_pll: pll.phi, phi_h: phi_h, gate: g})
    {:noreply, %{s | pll: pll, hilb: hilb, prev: win, win: win, hist: [win | Enum.take(s.hist, 128)], h_prev: h_t, commits_pll: commits_pll, commits_hil: commits_hil}}
  end
  def handle_info({:event, _}, s), do: {:noreply, s}
  def handle_call({:boundary_close, _timeout_ms}, _from, s) do
    echo = Enum.take(s.hist, 3)
    NDJSON.write(%{event: "boundary_close_requested", phi_pll: s.pll.phi})
  EventBus.emit_realtime(:system_status, %{stage: "paused", reason: "boundary_close", phi_pll: s.pll.phi})
    {:reply, %{gate_ts: System.monotonic_time(:millisecond), phi_pll: s.pll.phi, echo_window: echo, pll_state: Map.from_struct(s.pll)}, s}
  end
  # Helper functions copied from legacy module
  defp velocity(_win, []), do: 0.0
  defp velocity(win, prev), do: 1.0 - E.cosine(E.vec(Enum.join(win, "")), E.vec(Enum.join(prev, "")))
  defp entropy(win) do
    chars = win |> Enum.join("") |> :binary.bin_to_list()
    total = max(length(chars), 1)
    chars |> Enum.frequencies() |> Map.values() |> Enum.reduce(0.0, fn c, acc -> p = c/total; acc - p * (:math.log(p + 1.0e-12)/:math.log(2)) end)
  end
  defp recurrence(win, hist, gap) do
    v = E.vec(Enum.join(win, ""))
    hist |> Enum.drop(gap) |> Enum.map(fn w -> E.cosine(v, E.vec(Enum.join(w, ""))) end) |> Enum.max(fn -> 0.0 end)
  end
  defp boundary?(tok, v, s) do
    t = to_string(tok)
    ends = String.ends_with?(t, [".","!","?",";",":"])
    ends and v < 0.05 and s < 0.0
  end
  defp dot(w, a), do: Enum.zip(w, a) |> Enum.reduce(0.0, fn {x,y}, acc -> acc + x*y end)
  defp weights, do: Enum.map(1..9, fn _ -> 1.0 end)
  defp sigmoid(x), do: 1.0/(1.0 + :math.exp(-x))
  defp identity_density(win) do
    toks = win |> Enum.join(" ") |> String.downcase() |> String.split()
    n = max(length(toks), 1)
    keys = MapSet.new(~w(i me my mine solus anchor))
    Enum.count(toks, &MapSet.member?(keys, &1)) / n
  end
  defp short(nil), do: nil
  defp short(map) when is_map(map), do: Map.take(map, [:score, :ts])
  defp short(x), do: x
end
