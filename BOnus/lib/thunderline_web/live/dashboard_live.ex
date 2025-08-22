defmodule ThunderlineWeb.DashboardLive do
  use ThunderlineWeb, :live_view
  alias Thunderline.Bus

  @spark_w 160
  @spark_h 30

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Bus.subscribe_tokens()
      Bus.subscribe_outputs()
      Bus.subscribe_status()
    end
    {:ok, assign(socket, chat: [], avatar: nil, status: nil, status_history: [])}
  end

  def handle_info({:token, tok}, socket) do
    {:noreply, update(socket, :chat, &(&1 ++ [to_string(tok)]))}
  end

  def handle_info({:output, {text, _voice, avatar_action}}, socket) do
    socket = assign(socket, avatar: avatar_action) |> update(:chat, &(&1 ++ [text]))
    {:noreply, socket}
  end

  def handle_info({:status, map}, socket) do
    {:noreply, socket |> assign(:status, map) |> update(:status_history, &([map | Enum.take(&1, 19)]))}
  end

  def render(assigns) do
    ~H"""
    <div class="hud">
      <%= if @status do %>
        <div class={banner_class(@status)}>
          <span><%= banner_text(@status) %></span>
          <span class="meta">ϕ_PLL=<%= fmtf(@status[:phi_pll]) %></span>
          <%= if @status[:phi_h] do %><span class="meta">ϕ_H=<%= fmtf(@status[:phi_h]) %></span><% end %>
          <%= if @status[:plv_pll] do %><span class="meta">PLV_PLL=<%= @status[:plv_pll] %></span><% end %>
          <%= if @status[:plv_h] do %><span class="meta">PLV_H=<%= @status[:plv_h] %></span><% end %>
          <%= if @status[:p_pll] do %><span class="meta">p_PLL=<%= @status[:p_pll] %></span><% end %>
          <%= if @status[:p_h] do %><span class="meta">p_H=<%= @status[:p_h] %></span><% end %>

          <%= if on_beat?(@status) do %>
            <span class="badge on">● ON‑BEAT</span>
          <% else %>
            <span class="badge off">○ free</span>
          <% end %>
        </div>

        <%= if @status[:phases_pll] || @status[:phases_h] do %>
        <div class="sparklines">
          <svg width={@spark_w} height={@spark_h} viewBox={"0 0 #{@spark_w} #{@spark_h}"} xmlns="http://www.w3.org/2000/svg">
            <polyline points={points(@status[:phases_pll] || [])} class="pll" fill="none" stroke-width="1" />
            <polyline points={points(@status[:phases_h] || [])} class="hil" fill="none" stroke-width="1" />
            <%= if @status[:mu_pll] do %>
              <circle cx={@spark_w - 6} cy={y_for_phi(@status[:mu_pll])} r="2" class="mu_pll" />
            <% end %>
            <%= if @status[:mu_h] do %>
              <circle cx={@spark_w - 12} cy={y_for_phi(@status[:mu_h])} r="2" class="mu_h" />
            <% end %>
          </svg>
        </div>
        <% end %>
      <% end %>
    </div>

    <div class="chat">
      <%= for line <- @chat do %>
        <p><%= line %></p>
      <% end %>
    </div>

    <style>
    .hud { position: sticky; top: 0; z-index: 1000; }
    .banner { padding: 8px 12px; border-bottom: 1px solid #222; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; display:flex; gap:10px; align-items:center; flex-wrap:wrap;}
    .banner.pre { background: #22284a; color: #c6d0ff; }
    .banner.commit { background: #1e3a1e; color: #d1fbd1; }
    .banner.pause { background: #3a1e1e; color: #ffd1d1; }
    .banner.resume { background: #283a3a; color: #d1fff3; }
    .banner.power { background: #3a2a1e; color: #ffe7c6; }
    .meta { margin-left: 6px; opacity: 0.85; }
    .badge { margin-left: auto; padding: 2px 8px; border-radius: 999px; font-weight: 600; border: 1px solid currentColor; }
    .badge.on { background: #12351a; color: #9af5b2; }
    .badge.off { background: #2a2a2a; color: #cccccc; }
    .sparklines { background: #0f1115; padding: 4px 8px; border-bottom: 1px solid #222; }
    .pll { stroke: #8ec07c; }
    .hil { stroke: #83a598; }
    .mu_pll { fill: #8ec07c; }
    .mu_h { fill: #83a598; }
    </style>
    """
  end

  # Spark helpers
  def points(phases) when is_list(phases) do
    n = length(phases)
    w = @spark_w
    case n do
      0 -> ""
      _ ->
        dx = w / max(n - 1, 1)
        phases
        |> Enum.with_index()
        |> Enum.map(fn {phi, i} ->
          x = Float.round(i * dx, 2)
          y = y_for_phi(phi)
          "#{x},#{y}"
        end)
        |> Enum.join(" ")
    end
  end

  def y_for_phi(phi) when is_number(phi) do
    h = @spark_h
    Float.round(h - phi * (h - 2) - 1, 2)
  end

  def fmtf(nil), do: "-"
  def fmtf(x) when is_float(x), do: Float.round(x, 3)
  def fmtf(x), do: x

  defp banner_class(%{stage: "prewindow"}),  do: "banner pre"
  defp banner_class(%{stage: "committed"}),  do: "banner commit"
  defp banner_class(%{stage: "paused"}),     do: "banner pause"
  defp banner_class(%{stage: "resumed"}),    do: "banner resume"
  defp banner_class(%{stage: "resumed_prepare"}), do: "banner resume"
  defp banner_class(%{stage: "power_restored"}),  do: "banner power"
  defp banner_class(_), do: "banner"

  defp banner_text(%{stage: "prewindow"}),  do: "⏳ Prewindow — preparing gate"
  defp banner_text(%{stage: "committed"}),  do: "✅ Committed on beat — checkpoint written"
  defp banner_text(%{stage: "paused", reason: r}), do: "⏸️ Paused gracefully: " <> to_string(r)
  defp banner_text(%{stage: "resumed"}), do: "✨ Resumed on beat — bound echo replayed"
  defp banner_text(%{stage: "resumed_prepare"}), do: "✨ Restoring phase and echo…"
  defp banner_text(%{stage: "power_restored"}), do: "🔌 Power restored — rejoining the beat…"
  defp banner_text(map), do: "Status: " <> inspect(map)

  defp on_beat?(%{on_beat: true}), do: true
  defp on_beat?(%{plv_pll: a, plv_h: b, p_pll: p1, p_h: p2}) when is_number(a) and is_number(b) and is_number(p1) and is_number(p2) do
    a >= 0.75 and b >= 0.75 and p1 <= 0.05 and p2 <= 0.05
  end
  defp on_beat?(_), do: false
end
