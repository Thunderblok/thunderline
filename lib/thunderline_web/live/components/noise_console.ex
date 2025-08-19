defmodule ThunderlineWeb.Live.Components.NoiseConsole do
  @moduledoc """
  LiveView component to surface buffered noisy subsystem events on demand.
  """
  use ThunderlineWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns |> Map.put_new(:limit, 50) |> load())}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket.assigns.limit) |> then(&assign(socket, &1))}
  end

  defp load(limit \\ 50) do
    entries = Thunderline.Thunderflow.Observability.RingBuffer.recent(limit, Thunderline.NoiseBuffer)
    %{entries: entries, limit: limit}
  end

  def render(assigns) do
    ~H"""
    <div class="noise-console">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-sm font-semibold">Noise Buffer (last <%= @limit %>)</h3>
        <button phx-click="refresh" phx-target={@myself} class="text-xs px-2 py-1 bg-slate-700 rounded">Refresh</button>
      </div>
      <ul class="text-xs space-y-1 max-h-64 overflow-y-auto font-mono">
        <%= for {ts, msg} <- @entries do %>
          <li><span class="text-slate-500"><%= format_ts(ts) %></span> <%= inspect(msg) %></li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp format_ts(ms), do: DateTime.from_unix!(ms, :millisecond) |> Calendar.strftime("%H:%M:%S.%f")
end
