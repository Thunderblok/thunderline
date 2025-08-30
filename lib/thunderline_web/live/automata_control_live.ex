defmodule ThunderlineWeb.AutomataControlLive do
  use ThunderlineWeb, :live_view

  alias Thunderline.Thunderbolt.Resources.AutomataRun

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:running, false)
     |> assign(:snapshot_id, nil)
     |> assign(:message, nil)}
  end

  @impl true
  def handle_event("start", _params, socket) do
    {:ok, %{run_id: run_id}} = AutomataRun.start(%{size: 64, tick_ms: 50})
    {:noreply, socket |> assign(:running, true) |> assign(:run_id, run_id)}
  end

  def handle_event("stop", _params, socket) do
    if run_id = socket.assigns[:run_id] do
      _ = AutomataRun.stop(%{run_id: run_id})
    end
    {:noreply, assign(socket, :running, false)}
  end

  def handle_event("snapshot", _params, socket) do
    {:ok, %{snapshot_id: snap_id}} = AutomataRun.snapshot(%{run_id: socket.assigns[:run_id]})
    {:noreply, assign(socket, :snapshot_id, snap_id)}
  end

  def handle_event("restore", %{"_id" => id}, socket) do
    _ = AutomataRun.restore(%{run_id: socket.assigns[:run_id], snapshot_id: id})
    {:noreply, assign(socket, :message, "restore requested for #{id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-4">
        <h2 class="text-xl font-semibold">Automata Controls</h2>
        <div class="flex items-center gap-2">
          <button phx-click="start" class="btn">Start</button>
          <button phx-click="stop" class="btn" disabled={!@running}>Stop</button>
          <button phx-click="snapshot" class="btn">Snapshot</button>
          <form phx-submit="restore" class="flex gap-2">
            <input name="_id" placeholder="snapshot id" class="input"/>
            <button class="btn">Restore</button>
          </form>
        </div>
        <div :if={@snapshot_id}>Last snapshot: {@snapshot_id}</div>
        <div :if={@message} class="text-sm text-gray-500">{@message}</div>
      </div>
    </Layouts.app>
    """
  end
end
