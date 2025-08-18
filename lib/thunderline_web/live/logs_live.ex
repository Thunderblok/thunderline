defmodule ThunderlineWeb.LogsLive do
  @moduledoc """
  Developer log viewer that tails the in‑memory ETS ring buffer (Thunderline.LogBuffer).

  Provides lightweight filtering by level / substring and periodic refresh.
  Only enabled in dev (route guarded in router under if Application.compile_env(:thunderline, :dev_routes, false)).
  """
  use ThunderlineWeb, :live_view

  @refresh 1_000
  @levels [:debug, :info, :warning, :error]

  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:logs, [])
     |> assign(:level, :debug)
     |> assign(:q, "")
     |> assign(:limit, 300)
     |> assign(:auto_scroll, true)}
  end

  def handle_info(:tick, socket) do
    logs = fetch(socket.assigns.limit, socket.assigns.level, socket.assigns.q)
    if connected?(socket), do: schedule_refresh()
    {:noreply, assign(socket, :logs, logs)}
  end

  def handle_event("set-level", %{"level" => lvl}, socket) do
    level = String.to_existing_atom(lvl)
    {:noreply, assign(socket, level: level)}
  rescue
    _ -> {:noreply, socket}
  end

  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, q: q)}
  end

  def handle_event("limit", %{"limit" => limit}, socket) do
    case Integer.parse(limit) do
      {n, _} when n > 0 and n <= 2_000 -> {:noreply, assign(socket, limit: n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle-scroll", _params, socket) do
    {:noreply, update(socket, :auto_scroll, &(!&1))}
  end

  def handle_event("clear", _params, socket) do
    Thunderline.LogBuffer.clear()
    {:noreply, assign(socket, :logs, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="p-4 space-y-3">
      <h2 class="text-xl font-semibold">Dev Log Viewer</h2>
      <div class="flex flex-wrap gap-2 items-end">
        <div class="flex gap-1">
          <%= for lvl <- @levels do %>
            <button phx-click="set-level" phx-value-level={lvl}
              class={level_button_classes(lvl, @level)}><%= Atom.to_string(lvl) %></button>
          <% end %>
        </div>
        <div>
          <label class="text-xs block uppercase tracking-wide">Search</label>
          <input type="text" name="q" value={@q} phx-debounce="300" phx-change="filter" class="input input-sm" placeholder="substring" />
        </div>
        <div>
          <label class="text-xs block uppercase tracking-wide">Limit</label>
          <input type="number" name="limit" value={@limit} phx-change="limit" class="input input-sm w-24" />
        </div>
        <div class="flex gap-2 items-center">
          <button phx-click="toggle-scroll" class="btn btn-xs">Scroll: <%= if @auto_scroll, do: "ON", else: "OFF" %></button>
          <button phx-click="clear" data-confirm="Clear log buffer?" class="btn btn-xs btn-error">Clear</button>
        </div>
      </div>
      <div id="log-container" phx-hook="AutoScroll" data-auto={@auto_scroll} class="bg-black text-gray-200 font-mono text-xs p-2 h-[70vh] overflow-y-auto rounded border border-gray-700">
        <%= for {lvl, md, msg} <- @logs do %>
          <div class={line_classes(lvl)}>
            <span class="opacity-70 mr-1">[<%= lvl %>]</span>
            <%= if md[:module] do %><span class="text-cyan-400"><%= inspect(md[:module]) %></span><% end %>
            <%= if md[:function] do %><span class="text-cyan-300">.<%= md[:function] %></span><% end %>
            <span class="ml-1"><%= msg %></span>
          </div>
        <% end %>
      </div>
    </div>
    <script>
      window.Hooks = window.Hooks || {};
      window.Hooks.AutoScroll = {
        updated(){
          if(this.el.dataset.auto === 'true'){
            this.el.scrollTop = this.el.scrollHeight;
          }
        }
      }
    </script>
    """
  end

  # Helpers
  defp schedule_refresh, do: Process.send_after(self(), :tick, @refresh)

  defp fetch(limit, level, q) do
    Thunderline.LogBuffer.recent(limit)
    |> Enum.filter(fn {lvl, _md, msg} ->
      level_filter?(lvl, level) and substring?(msg, q)
    end)
  end

  defp level_filter?(lvl, :debug), do: true
  defp level_filter?(lvl, :info), do: lvl in [:info, :warning, :error]
  defp level_filter?(lvl, :warning), do: lvl in [:warning, :error]
  defp level_filter?(lvl, :error), do: lvl == :error

  defp substring?(_msg, ""), do: true
  defp substring?(msg, q), do: String.contains?(String.downcase(msg), String.downcase(q))

  # CSS helpers (tailwind / daisy like utility classes)
  defp level_button_classes(lvl, current) do
    base = "px-2 py-1 rounded text-xs font-mono border"
    active = "bg-indigo-600 text-white border-indigo-600"
    inactive = "bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700"
    if lvl == current, do: base <> " " <> active, else: base <> " " <> inactive
  end

  defp line_classes(:debug), do: "text-gray-400"
  defp line_classes(:info), do: "text-gray-200"
  defp line_classes(:warning), do: "text-yellow-300"
  defp line_classes(:error), do: "text-red-400 font-semibold"
end
