defmodule ThunderlineWeb.ThunderfieldLive do
  @moduledoc """
  Thunderfield LiveView - The Visual Thunderbit Field

  HC-Δ-5.3: Thunderfield MVP - Wiring Protocol → UIContract → Live UI

  This is the first "dopamine hit" of the Thunderline vision:
  Type a sentence → See Thunderbits spawn and link in real-time.

  ## Features
  - Text input spawns sensory + cognitive Thunderbits
  - Real-time PubSub updates render bits in the field
  - Edges visualized as lines between linked bits
  - Category colors and shapes from the protocol
  - Click bits to see details

  ## Architecture

  ```
  User Input → Protocol.spawn_bit → UIContract.broadcast → PubSub → LiveView → JS Hook
  ```
  """

  use ThunderlineWeb, :live_view

  alias Thunderline.Thunderbit.{Context, UIContract, Demo}
  alias ThunderlineWeb.Live.Components.Thunderfield

  require Logger

  @topic "thunderbits:lobby"

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, @topic)
    end

    {:ok,
     socket
     |> assign(:page_title, "Thunderfield")
     |> assign(:bits, [])
     |> assign(:edges, [])
     |> assign(:selected_bit, nil)
     |> assign(:context, Context.new(pac_id: "field_user"))
     |> assign(:stats, %{total: 0, sensory: 0, cognitive: 0, linked: 0})}
  end

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col h-[calc(100vh-4rem)] bg-slate-950">
        <%!-- Header --%>
        <header class="flex items-center justify-between px-6 py-4 border-b border-cyan-500/20">
          <div class="flex items-center gap-4">
            <h1 class="text-2xl font-bold bg-gradient-to-r from-cyan-400 to-blue-500 bg-clip-text text-transparent">
              Thunderfield
            </h1>
            <span class="text-sm text-gray-500">HC-Δ-5.3 MVP</span>
          </div>
          <div class="flex items-center gap-4 text-sm text-gray-400">
            <span class="px-2 py-1 bg-slate-800 rounded">
              {@stats.total} bits
            </span>
            <span class="px-2 py-1 bg-blue-900/50 rounded text-blue-300">
              {@stats.sensory} sensory
            </span>
            <span class="px-2 py-1 bg-purple-900/50 rounded text-purple-300">
              {@stats.cognitive} cognitive
            </span>
            <span class="px-2 py-1 bg-cyan-900/50 rounded text-cyan-300">
              {@stats.linked} links
            </span>
          </div>
        </header>

        <%!-- Main Content --%>
        <div class="flex flex-1 overflow-hidden">
          <%!-- Thunderfield Canvas --%>
          <div class="flex-1 relative">
            <Thunderfield.thunderfield
              id="main-field"
              bits={@bits}
              selected={@selected_bit}
              on_select="select_bit"
              show_relations={true}
              class="absolute inset-0"
            />
          </div>

          <%!-- Detail Panel --%>
          <aside
            :if={@selected_bit}
            class="w-80 border-l border-cyan-500/20 bg-slate-900/50 p-4 overflow-y-auto"
          >
            <Thunderfield.thunderbit_detail
              bit={@selected_bit}
              on_close="close_detail"
            />
          </aside>
        </div>

        <%!-- Input Bar --%>
        <footer class="px-6 py-4 border-t border-cyan-500/20 bg-slate-900/50">
          <Thunderfield.thunderbit_input
            on_submit="submit_input"
            placeholder="Type something to spawn Thunderbits..."
            voice_enabled={false}
          />
          <div class="flex items-center justify-between mt-2 text-xs text-gray-500">
            <span>
              Try: "What is the weather?" or "Navigate to zone 4"
            </span>
            <button
              type="button"
              phx-click="run_demo"
              class="text-cyan-400 hover:text-cyan-300"
            >
              Run Demo
            </button>
          </div>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("submit_input", %{"content" => content}, socket) when content != "" do
    Logger.info("[ThunderfieldLive] Input: #{String.slice(content, 0, 50)}")

    # Use the Demo module's intake flow
    case Demo.intake(content, "field_user") do
      {:ok, bits, edges, ctx} ->
        # Broadcast to all subscribers (including self)
        UIContract.broadcast(bits, edges, :created)

        {:noreply,
         socket
         |> assign(:context, ctx)
         |> put_flash(:info, "Spawned #{length(bits)} bits")}

      {:error, reason} ->
        Logger.error("[ThunderfieldLive] Spawn failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to spawn: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_input", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("run_demo", _params, socket) do
    # Run the canonical demo
    case Demo.run("What is the weather in Tokyo?", "demo_pac") do
      :ok ->
        {:noreply, put_flash(socket, :info, "Demo complete!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Demo failed: #{inspect(reason)}")}
    end
  end

  def handle_event("select_bit", %{"id" => bit_id}, socket) do
    selected = Enum.find(socket.assigns.bits, &(&1["id"] == bit_id || &1[:id] == bit_id))

    {:noreply, assign(socket, :selected_bit, selected)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :selected_bit, nil)}
  end

  # ===========================================================================
  # PubSub Handlers
  # ===========================================================================

  @impl true
  def handle_info({:thunderbit_spawn, %{bits: new_bits, edges: new_edges}}, socket) do
    Logger.debug("[ThunderfieldLive] Received #{length(new_bits)} new bits")

    bits = merge_bits(socket.assigns.bits, new_bits)
    edges = merge_edges(socket.assigns.edges, new_edges)
    stats = compute_stats(bits, edges)

    {:noreply,
     socket
     |> assign(:bits, bits)
     |> assign(:edges, edges)
     |> assign(:stats, stats)}
  end

  def handle_info({:thunderbit_update, %{bits: updated_bits}}, socket) do
    bits =
      Enum.map(socket.assigns.bits, fn bit ->
        case Enum.find(updated_bits, &(&1["id"] == bit["id"])) do
          nil -> bit
          updated -> updated
        end
      end)

    {:noreply, assign(socket, :bits, bits)}
  end

  def handle_info({:thunderbit_retire, %{bits: retired_bits}}, socket) do
    retired_ids = Enum.map(retired_bits, & &1["id"])
    bits = Enum.reject(socket.assigns.bits, &(&1["id"] in retired_ids))
    stats = compute_stats(bits, socket.assigns.edges)

    {:noreply,
     socket
     |> assign(:bits, bits)
     |> assign(:stats, stats)}
  end

  def handle_info({:thunderbit_move, %{id: id, position: position}}, socket) do
    bits =
      Enum.map(socket.assigns.bits, fn bit ->
        if bit["id"] == id do
          put_in(bit, ["geometry", "position"], position)
        else
          bit
        end
      end)

    {:noreply, assign(socket, :bits, bits)}
  end

  def handle_info({:thunderbit_link, edge_dto}, socket) do
    edges = [edge_dto | socket.assigns.edges]
    stats = compute_stats(socket.assigns.bits, edges)

    {:noreply,
     socket
     |> assign(:edges, edges)
     |> assign(:stats, stats)}
  end

  def handle_info({:thunderbit_state, %{id: id, state: state}}, socket) do
    bits =
      Enum.map(socket.assigns.bits, fn bit ->
        if bit["id"] == id do
          Map.put(bit, "state", state)
        else
          bit
        end
      end)

    {:noreply, assign(socket, :bits, bits)}
  end

  # Catch-all for other messages
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp merge_bits(existing, new) do
    existing_ids = MapSet.new(existing, & &1["id"])

    # Add new bits that don't exist yet
    new_unique = Enum.reject(new, &((&1["id"] || &1[:id]) in existing_ids))

    existing ++ new_unique
  end

  defp merge_edges(existing, new) do
    existing_ids = MapSet.new(existing, & &1["id"])

    new_unique = Enum.reject(new, &((&1["id"] || &1[:id]) in existing_ids))

    existing ++ new_unique
  end

  defp compute_stats(bits, edges) do
    %{
      total: length(bits),
      sensory: Enum.count(bits, &(&1["category"] == "sensory")),
      cognitive: Enum.count(bits, &(&1["category"] == "cognitive")),
      linked: length(edges)
    }
  end
end
