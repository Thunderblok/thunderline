defmodule ThunderlineWeb.DashboardComponents.EventFlow do
  @moduledoc """
  Event flow stream panel.

  Supports domain-based color mapping. Expects each event map to include:
    :domain (atom | string)
    :message (string)
    :status (string | atom)
    :timestamp (NaiveDateTime | DateTime | integer system time)
    :kind (optional classification e.g. :telemetry, :domain_event)
    :source (optional)
  """
  use Phoenix.Component

  # Accept either a plain list of events (legacy) or use LiveView stream :dashboard_events
  attr :events, :list, default: []
  attr :max, :integer, default: 50
  # Allow parent to pass LiveView streams explicitly so we can render stream updates
  attr :streams, :map, default: %{}

  def event_flow_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-2">
        <div class="text-xl">⚡</div>
        <h3 class="text-sm font-semibold text-white tracking-wide">Event Flow</h3>
        <span class="text-[10px] text-gray-500">last {min(length(@events), @max)} events</span>
      </div>
      <div class="flex-1 overflow-hidden">
        <div
          id="event-flow"
          phx-hook="EventFlowScroll"
          phx-update="stream"
          class="space-y-1.5 h-full overflow-y-auto pr-1 scrollbar-thin scrollbar-thumb-cyan-600/40 scrollbar-track-transparent"
        >
          <%= if Map.has_key?(assigns, :streams) and Map.has_key?(assigns.streams, :dashboard_events) do %>
            <%= for {dom_id, event} <- @streams.dashboard_events do %>
              <div
                id={dom_id}
                class={[
                  "group relative rounded-md border px-2 py-1.5 backdrop-blur transition-colors",
                  domain_card_class(event.domain)
                ]}
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center space-x-1.5">
                    <span class={[
                      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium ring-1 ring-inset",
                      domain_pill_class(event.domain)
                    ]}>
                      {pretty_domain(event.domain)}
                    </span>
                    <span class="text-[11px] text-gray-400/70 font-mono">
                      {format_timestamp(event.timestamp)}
                    </span>
                  </div>
                  <div class={[
                    "w-2 h-2 rounded-full shadow-inner",
                    status_indicator_class(event.status)
                  ]}>
                  </div>
                </div>
                <div class="mt-1.5 text-[11px] leading-tight text-gray-200/90 group-hover:text-white truncate">
                  {event.message}
                </div>
                <%= if event[:source] do %>
                  <div class="mt-1 text-[10px] text-gray-500/70 font-mono truncate">
                    {event.source}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% else %>
            <%= for event <- Enum.take(@events, @max) do %>
              <div class={[
                "group relative rounded-md border px-2 py-1.5 backdrop-blur transition-colors",
                domain_card_class(event.domain)
              ]}>
                <div class="flex items-center justify-between">
                  <div class="flex items-center space-x-1.5">
                    <span class={[
                      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium ring-1 ring-inset",
                      domain_pill_class(event.domain)
                    ]}>
                      {pretty_domain(event.domain)}
                    </span>
                    <span class="text-[11px] text-gray-400/70 font-mono">
                      {format_timestamp(event.timestamp)}
                    </span>
                  </div>
                  <div class={[
                    "w-2 h-2 rounded-full shadow-inner",
                    status_indicator_class(event.status)
                  ]}>
                  </div>
                </div>
                <div class="mt-1.5 text-[11px] leading-tight text-gray-200/90 group-hover:text-white truncate">
                  {event.message}
                </div>
                <%= if event[:source] do %>
                  <div class="mt-1 text-[10px] text-gray-500/70 font-mono truncate">
                    {event.source}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Domain styling helpers
  @domain_styles %{
    thunderbolt: %{
      card: "bg-blue-900/20 border-blue-500/20 hover:border-blue-400/40",
      pill: "bg-blue-500/15 text-blue-300 ring-blue-400/30"
    },
    thunderblock: %{
      card: "bg-emerald-900/15 border-emerald-500/20 hover:border-emerald-400/40",
      pill: "bg-emerald-500/15 text-emerald-300 ring-emerald-400/30"
    },
    thunderflow: %{
      card: "bg-cyan-900/15 border-cyan-500/20 hover:border-cyan-400/40",
      pill: "bg-cyan-500/15 text-cyan-300 ring-cyan-400/30"
    },
    thundergrid: %{
      card: "bg-indigo-900/20 border-indigo-500/20 hover:border-indigo-400/40",
      pill: "bg-indigo-500/15 text-indigo-300 ring-indigo-400/30"
    },
    thundercrown: %{
      card: "bg-amber-900/20 border-amber-500/20 hover:border-amber-400/40",
      pill: "bg-amber-500/15 text-amber-300 ring-amber-400/30"
    },
    thundergate: %{
      card: "bg-fuchsia-900/20 border-fuchsia-500/20 hover:border-fuchsia-400/40",
      pill: "bg-fuchsia-500/15 text-fuchsia-300 ring-fuchsia-400/30"
    },
    thunderlink: %{
      card: "bg-pink-900/15 border-pink-500/20 hover:border-pink-400/40",
      pill: "bg-pink-500/15 text-pink-300 ring-pink-400/30"
    },
    thunderlane: %{
      card: "bg-teal-900/15 border-teal-500/20 hover:border-teal-400/40",
      pill: "bg-teal-500/15 text-teal-300 ring-teal-400/30"
    },
    system: %{
      card: "bg-gray-800/40 border-gray-600/30 hover:border-gray-500/50",
      pill: "bg-gray-600/30 text-gray-200 ring-gray-400/30"
    },
    default: %{
      card: "bg-slate-800/30 border-slate-600/20 hover:border-slate-500/40",
      pill: "bg-slate-600/30 text-slate-200 ring-slate-400/30"
    }
  }

  defp domain_card_class(domain), do: domain_styles(domain).card
  defp domain_pill_class(domain), do: domain_styles(domain).pill

  defp domain_styles(domain) do
    Map.get(@domain_styles, normalize_domain(domain), @domain_styles[:default])
  end

  defp normalize_domain(nil), do: :unknown
  defp normalize_domain(d) when is_atom(d), do: d

  defp normalize_domain(d) when is_binary(d) do
    d |> String.downcase() |> String.replace_prefix("thunderline_", "") |> String.to_atom()
  rescue
    _ -> :unknown
  end

  defp normalize_domain(_), do: :unknown

  defp pretty_domain(d) when is_atom(d),
    do: d |> Atom.to_string() |> String.replace_prefix("thunderline_", "")

  defp pretty_domain(d) when is_binary(d), do: d
  defp pretty_domain(_), do: "unknown"

  # Status indicator coloring
  defp status_indicator_class(status) when status in ["processing", :processing],
    do: "bg-yellow-400 animate-pulse"

  defp status_indicator_class(status) when status in ["completed", :completed, :ok],
    do: "bg-green-400"

  defp status_indicator_class(status) when status in ["error", :error, :failed], do: "bg-red-500"
  defp status_indicator_class(status) when status in ["warning", :warning], do: "bg-amber-400"
  defp status_indicator_class(_), do: "bg-gray-500"

  # Flexible timestamp formatting (DateTime, NaiveDateTime, integer system time)
  defp format_timestamp(%DateTime{} = dt),
    do: dt |> DateTime.to_time() |> Time.truncate(:second) |> to_string()

  defp format_timestamp(%NaiveDateTime{} = ndt),
    do: ndt |> NaiveDateTime.to_time() |> Time.truncate(:second) |> to_string()

  defp format_timestamp(int) when is_integer(int) do
    int
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> to_string()
  rescue
    _ -> "--:--:--"
  end

  defp format_timestamp(_), do: "--:--:--"
end
