defmodule ThunderlineWeb.PacConsoleLive do
  @moduledoc """
  PAC Console - Real-time PAC state viewer and controller.

  Shows:
  - PAC current state and lifecycle position
  - Memory state and trait vector
  - Intent queue
  - Lineage history (state snapshots)
  - Real-time event stream

  Part of Boss 3: Persistence + Thunderprism Slice
  """
  use ThunderlineWeb, :live_view

  alias Phoenix.PubSub
  alias Thunderline.Thunderpac.Resources.PAC

  @refresh_interval 5_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case load_pac(id) do
        {:ok, pac} ->
          if connected?(socket) do
            # Subscribe to PAC-specific lifecycle events
            PubSub.subscribe(Thunderline.PubSub, "pac:lifecycle:#{pac.id}")
            # Subscribe to global PAC state changes
            PubSub.subscribe(Thunderline.PubSub, "pac.state.changed")
            schedule_refresh()
          end

          socket
          |> assign(:page_title, "PAC: #{pac.name}")
          |> assign(:pac, pac)
          |> assign(:pac_id, id)
          |> assign(:error, nil)
          |> assign(:recent_events, [])
          |> stream(:events, [])

        {:error, reason} ->
          socket
          |> assign(:page_title, "PAC Not Found")
          |> assign(:pac, nil)
          |> assign(:pac_id, id)
          |> assign(:error, reason)
          |> assign(:recent_events, [])
          |> stream(:events, [])
      end

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    # List view - show all PACs
    pacs = list_pacs()

    socket =
      socket
      |> assign(:page_title, "PAC Console")
      |> assign(:pac, nil)
      |> assign(:pac_id, nil)
      |> assign(:error, nil)
      |> stream(:pacs, pacs)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case load_pac(id) do
      {:ok, pac} ->
        {:noreply,
         socket
         |> assign(:page_title, "PAC: #{pac.name}")
         |> assign(:pac, pac)
         |> assign(:pac_id, id)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:page_title, "PAC Not Found")
         |> assign(:pac, nil)
         |> assign(:pac_id, id)
         |> assign(:error, reason)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ═══════════════════════════════════════════════════════════════
  # EVENT HANDLERS - User Actions
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def handle_event("ignite", _params, socket) do
    handle_pac_action(socket, :ignite, "PAC ignited!")
  end

  def handle_event("activate", _params, socket) do
    handle_pac_action(socket, :activate, "PAC activated!")
  end

  def handle_event("suspend", _params, socket) do
    handle_pac_action(socket, :suspend, "PAC suspended", reason: "manual")
  end

  def handle_event("archive", _params, socket) do
    handle_pac_action(socket, :archive, "PAC archived")
  end

  def handle_event("reactivate", _params, socket) do
    handle_pac_action(socket, :reactivate, "PAC reactivated!")
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, reload_pac(socket)}
  end

  # ═══════════════════════════════════════════════════════════════
  # EVENT HANDLERS - PubSub
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def handle_info({:pac_lifecycle, event}, socket) do
    # Add event to stream
    event_display = %{
      id: event.correlation_id || Ash.UUID.generate(),
      type: event.type,
      timestamp: DateTime.utc_now(),
      payload: event.payload
    }

    socket =
      socket
      |> stream_insert(:events, event_display, at: 0)
      |> reload_pac()

    {:noreply, socket}
  end

  def handle_info(%{name: "pac.state.changed", payload: %{pac_id: pac_id}}, socket) do
    if socket.assigns[:pac_id] == pac_id do
      {:noreply, reload_pac(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, reload_pac(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ═══════════════════════════════════════════════════════════════
  # RENDER
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def render(assigns) when assigns.pac_id == nil do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_scope]}>
      <div class="min-h-screen bg-gradient-to-br from-slate-900 via-indigo-900 to-slate-900 p-6">
        <div class="max-w-6xl mx-auto">
          <div class="mb-8">
            <h1 class="text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-purple-400">
              <.icon name="hero-cpu-chip" class="w-10 h-10 inline-block text-cyan-400" /> PAC Console
            </h1>
            <p class="mt-2 text-slate-300">Personal Autonomous Constructs - Lifecycle Management</p>
          </div>

          <div class="bg-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 overflow-hidden">
            <div class="px-6 py-4 border-b border-slate-700">
              <h2 class="text-lg font-semibold text-white">All PACs</h2>
            </div>
            <div id="pacs-list" phx-update="stream" class="divide-y divide-slate-700">
              <div :for={{dom_id, pac} <- @streams.pacs} id={dom_id} class="px-6 py-4 hover:bg-slate-700/50 transition-colors">
                <.link navigate={~p"/pac/#{pac.id}"} class="flex items-center justify-between">
                  <div class="flex items-center gap-4">
                    <div class={["w-3 h-3 rounded-full", status_color(pac.status)]}></div>
                    <div>
                      <p class="text-white font-medium">{pac.name}</p>
                      <p class="text-slate-400 text-sm">ID: {pac.id}</p>
                    </div>
                  </div>
                  <div class="flex items-center gap-4">
                    <span class={["px-3 py-1 rounded-full text-xs font-medium", status_badge(pac.status)]}>
                      {pac.status}
                    </span>
                    <.icon name="hero-chevron-right" class="w-5 h-5 text-slate-400" />
                  </div>
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) when assigns.error != nil do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_scope]}>
      <div class="min-h-screen bg-gradient-to-br from-slate-900 via-red-900 to-slate-900 p-6">
        <div class="max-w-2xl mx-auto text-center py-20">
          <.icon name="hero-exclamation-triangle" class="w-16 h-16 text-red-400 mx-auto mb-4" />
          <h1 class="text-3xl font-bold text-white mb-2">PAC Not Found</h1>
          <p class="text-slate-300 mb-6">ID: {@pac_id}</p>
          <.link navigate={~p"/pac"} class="text-cyan-400 hover:text-cyan-300">
            ← Back to PAC Console
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_scope]}>
      <div class="min-h-screen bg-gradient-to-br from-slate-900 via-indigo-900 to-slate-900 p-6">
        <div class="max-w-6xl mx-auto">
          <%!-- Header --%>
          <div class="mb-8 flex items-center justify-between">
            <div>
              <div class="flex items-center gap-3 mb-2">
                <.link navigate={~p"/pac"} class="text-slate-400 hover:text-white">
                  <.icon name="hero-arrow-left" class="w-5 h-5" />
                </.link>
                <h1 class="text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-purple-400">
                  <.icon name="hero-cpu-chip" class="w-10 h-10 inline-block text-cyan-400" /> {@pac.name}
                </h1>
              </div>
              <p class="text-slate-400 text-sm">ID: {@pac.id}</p>
            </div>
            <button
              phx-click="refresh"
              class="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-medium transition-colors flex items-center gap-2"
            >
              <.icon name="hero-arrow-path" class="w-5 h-5" /> Refresh
            </button>
          </div>

          <%!-- Status & Controls --%>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">
            <%!-- Current State --%>
            <div class="lg:col-span-2 bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700">
              <h2 class="text-lg font-semibold text-white mb-4">Lifecycle State</h2>
              <div class="flex items-center gap-6 mb-6">
                <div class={["w-4 h-4 rounded-full animate-pulse", status_color(@pac.status)]}></div>
                <span class={["px-4 py-2 rounded-full text-lg font-bold", status_badge(@pac.status)]}>
                  {@pac.status}
                </span>
              </div>

              <%!-- State Machine Visualization --%>
              <div class="flex items-center gap-2 text-sm mb-6 overflow-x-auto pb-2">
                <.state_node status={@pac.status} state={:seed} label="SEED" />
                <.arrow />
                <.state_node status={@pac.status} state={:dormant} label="DORMANT" />
                <.arrow />
                <.state_node status={@pac.status} state={:active} label="ACTIVE" />
                <.arrow />
                <.state_node status={@pac.status} state={:suspended} label="SUSPENDED" />
                <.arrow />
                <.state_node status={@pac.status} state={:archived} label="ARCHIVED" />
              </div>

              <%!-- Action Buttons --%>
              <div class="flex flex-wrap gap-3">
                <button
                  :if={@pac.status == :seed}
                  phx-click="ignite"
                  class="px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg font-medium transition-colors"
                >
                  <.icon name="hero-fire" class="w-4 h-4 inline mr-1" /> Ignite
                </button>
                <button
                  :if={@pac.status in [:dormant, :suspended]}
                  phx-click="activate"
                  class="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-medium transition-colors"
                >
                  <.icon name="hero-play" class="w-4 h-4 inline mr-1" /> Activate
                </button>
                <button
                  :if={@pac.status == :active}
                  phx-click="suspend"
                  class="px-4 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-lg font-medium transition-colors"
                >
                  <.icon name="hero-pause" class="w-4 h-4 inline mr-1" /> Suspend
                </button>
                <button
                  :if={@pac.status in [:dormant, :active, :suspended]}
                  phx-click="archive"
                  class="px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-medium transition-colors"
                >
                  <.icon name="hero-archive-box" class="w-4 h-4 inline mr-1" /> Archive
                </button>
                <button
                  :if={@pac.status == :archived}
                  phx-click="reactivate"
                  class="px-4 py-2 bg-cyan-600 hover:bg-cyan-500 text-white rounded-lg font-medium transition-colors"
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4 inline mr-1" /> Reactivate
                </button>
              </div>
            </div>

            <%!-- Stats --%>
            <div class="bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700">
              <h2 class="text-lg font-semibold text-white mb-4">Statistics</h2>
              <dl class="space-y-4">
                <div>
                  <dt class="text-slate-400 text-sm">Sessions</dt>
                  <dd class="text-2xl font-bold text-white">{@pac.session_count}</dd>
                </div>
                <div>
                  <dt class="text-slate-400 text-sm">Total Active Ticks</dt>
                  <dd class="text-2xl font-bold text-white">{@pac.total_active_ticks}</dd>
                </div>
                <div>
                  <dt class="text-slate-400 text-sm">Last Active</dt>
                  <dd class="text-white">{format_datetime(@pac.last_active_at)}</dd>
                </div>
                <div>
                  <dt class="text-slate-400 text-sm">Created</dt>
                  <dd class="text-white">{format_datetime(@pac.inserted_at)}</dd>
                </div>
              </dl>
            </div>
          </div>

          <%!-- Memory & Traits --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <%!-- Memory State --%>
            <div class="bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700">
              <h2 class="text-lg font-semibold text-white mb-4">
                <.icon name="hero-circle-stack" class="w-5 h-5 inline mr-1 text-purple-400" /> Memory State
              </h2>
              <pre class="bg-slate-900 rounded-lg p-4 text-sm text-slate-300 overflow-auto max-h-48"><code>{format_json(@pac.memory_state)}</code></pre>
            </div>

            <%!-- Trait Vector --%>
            <div class="bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700">
              <h2 class="text-lg font-semibold text-white mb-4">
                <.icon name="hero-chart-bar" class="w-5 h-5 inline mr-1 text-cyan-400" /> Trait Vector
              </h2>
              <%= if @pac.trait_vector != [] do %>
                <div class="flex flex-wrap gap-2">
                  <%= for {val, idx} <- Enum.with_index(@pac.trait_vector) do %>
                    <span class="px-2 py-1 bg-slate-700 rounded text-sm text-white">
                      [{idx}] {Float.round(val, 3)}
                    </span>
                  <% end %>
                </div>
              <% else %>
                <p class="text-slate-400">No traits yet</p>
              <% end %>
            </div>
          </div>

          <%!-- Intent Queue & Event Stream --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <%!-- Intent Queue --%>
            <div class="bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700">
              <h2 class="text-lg font-semibold text-white mb-4">
                <.icon name="hero-queue-list" class="w-5 h-5 inline mr-1 text-amber-400" /> Intent Queue
              </h2>
              <%= if @pac.intent_queue != [] do %>
                <div class="space-y-2">
                  <%= for intent <- @pac.intent_queue do %>
                    <div class="bg-slate-700/50 rounded-lg p-3">
                      <pre class="text-sm text-slate-300 overflow-auto"><code>{format_json(intent)}</code></pre>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-slate-400">Queue empty</p>
              <% end %>
            </div>

            <%!-- Real-time Events --%>
            <div class="bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700">
              <h2 class="text-lg font-semibold text-white mb-4">
                <.icon name="hero-bolt" class="w-5 h-5 inline mr-1 text-yellow-400" /> Recent Events
              </h2>
              <div id="events" phx-update="stream" class="space-y-2 max-h-64 overflow-y-auto">
                <p class="hidden only:block text-slate-400 text-center py-4">
                  Waiting for events...
                </p>
                <div :for={{dom_id, event} <- @streams.events} id={dom_id} class="bg-slate-700/50 rounded-lg p-3">
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-cyan-400 font-mono text-sm">{event.type}</span>
                    <span class="text-slate-500 text-xs">{format_time(event.timestamp)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ═══════════════════════════════════════════════════════════════
  # COMPONENTS
  # ═══════════════════════════════════════════════════════════════

  defp state_node(assigns) do
    active = assigns.status == assigns.state

    assigns =
      assigns
      |> assign(:active, active)
      |> assign(
        :classes,
        if(active,
          do: "bg-cyan-500 text-white border-cyan-400",
          else: "bg-slate-700 text-slate-400 border-slate-600"
        )
      )

    ~H"""
    <div class={["px-3 py-1 rounded-lg border text-xs font-medium", @classes]}>
      {@label}
    </div>
    """
  end

  defp arrow(assigns) do
    ~H"""
    <.icon name="hero-arrow-right" class="w-4 h-4 text-slate-500 flex-shrink-0" />
    """
  end

  # ═══════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp load_pac(id) do
    case PAC.with_history(id, authorize?: false, load: [:state_snapshots, :intents]) do
      {:ok, pac} -> {:ok, pac}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_pacs do
    require Ash.Query

    Thunderline.Thunderpac.Resources.PAC
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  rescue
    _ -> []
  end

  defp reload_pac(socket) do
    case socket.assigns[:pac_id] do
      nil ->
        socket

      id ->
        case load_pac(id) do
          {:ok, pac} -> assign(socket, :pac, pac)
          {:error, _} -> socket
        end
    end
  end

  defp handle_pac_action(socket, action, success_msg, opts \\ []) do
    pac = socket.assigns.pac

    result =
      case action do
        :ignite -> PAC.ignite(pac, authorize?: false)
        :activate -> PAC.activate(pac, authorize?: false)
        :suspend -> PAC.suspend(pac, opts[:reason], authorize?: false)
        :archive -> PAC.archive(pac, authorize?: false)
        :reactivate -> PAC.reactivate(pac, authorize?: false)
      end

    case result do
      {:ok, updated_pac} ->
        {:noreply,
         socket
         |> assign(:pac, updated_pac)
         |> put_flash(:info, success_msg)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Action failed: #{inspect(error)}")}
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp status_color(status) do
    case status do
      :seed -> "bg-slate-400"
      :dormant -> "bg-blue-400"
      :active -> "bg-green-400"
      :suspended -> "bg-amber-400"
      :archived -> "bg-red-400"
      _ -> "bg-slate-400"
    end
  end

  defp status_badge(status) do
    case status do
      :seed -> "bg-slate-500/20 text-slate-300"
      :dormant -> "bg-blue-500/20 text-blue-300"
      :active -> "bg-green-500/20 text-green-300"
      :suspended -> "bg-amber-500/20 text-amber-300"
      :archived -> "bg-red-500/20 text-red-300"
      _ -> "bg-slate-500/20 text-slate-300"
    end
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_time(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_json(_), do: "{}"
end
