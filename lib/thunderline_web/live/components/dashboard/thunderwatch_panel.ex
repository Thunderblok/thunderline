defmodule ThunderlineWeb.DashboardComponents.ThunderwatchPanel do
  @moduledoc """
  Dashboard tile showing Thunderwatch (internal file watcher) statistics.
  """
  use Phoenix.Component
  alias Thundergate.Thunderwatch.Manager

  attr :stats, :map, default: %{}

  def thunderwatch_panel(assigns) do
    ~H"""
    <div class="p-3 rounded-md bg-slate-900 border border-slate-600 shadow-sm flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold tracking-wide text-slate-200">Thunderwatch</h3>
        <span class="text-[10px] uppercase text-slate-400">file change radar</span>
      </div>
      <div class="grid grid-cols-3 gap-2 text-center text-xs">
        <div>
          <div class="text-slate-300 font-mono"><%= @stats.files_indexed || 0 %></div>
          <div class="text-slate-500">files</div>
        </div>
        <div>
          <div class="text-slate-300 font-mono"><%= @stats.events_last_min || 0 %></div>
          <div class="text-slate-500">events/min</div>
        </div>
        <div>
          <div class="text-slate-300 font-mono"><%= @stats.seq || 0 %></div>
          <div class="text-slate-500">seq</div>
        </div>
      </div>
      <div class="h-1.5 w-full bg-slate-800 rounded overflow-hidden">
        <div class="h-full bg-indigo-500 transition-all" style={"width: #{progress(@stats)}%"}></div>
      </div>
      <div class="flex flex-wrap gap-1">
        <%= for {domain, count} <- (@stats.domain_counts || %{}) |> Enum.sort_by(&elem(&1,1), :desc) |> Enum.take(10) do %>
          <span class="px-1.5 py-0.5 rounded text-[10px] bg-slate-800/70 text-slate-300">
            <%= domain %>: <%= count %>
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  def sample_stats do
    seq = Manager.current_seq()
    snap = Manager.snapshot()
    files_indexed = map_size(snap)
    domain_counts = snap |> Enum.map(fn {_p,m}-> m[:domain] end) |> Enum.frequencies() |> Enum.sort_by(&elem(&1,1), :desc)
    events_last_min = Manager.changes_since(seq - 500) |> Enum.count(fn e -> recent?(e, 60_000_000) end)

    %{
      seq: seq,
      files_indexed: files_indexed,
      events_last_min: events_last_min,
      domain_counts: domain_counts,
    utilization: min((events_last_min / 200.0) * 100.0, 100.0)
    }
  rescue
    _ -> %{}
  end

  defp progress(%{utilization: u}), do: trunc(u)
  defp progress(_), do: 0
  defp recent?(%{at: at}, window), do: System.system_time(:microsecond) - at < window
  defp recent?(_, _), do: false
end
