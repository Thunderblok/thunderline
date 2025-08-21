defmodule ThunderlineWeb.Live.ThunderlaneDashboard do
  @moduledoc """
  Placeholder wrapper LiveView for the Thunderlane dashboard route.

  The router expects a `ThunderlineWeb.Live.ThunderlaneDashboard` module.
  The more feature‑rich implementation currently lives in
  `ThunderlineWeb.Live.Components.ThunderlaneDashboard` (which is itself
  implemented as a LiveView today). To avoid a larger refactor right now,
  this wrapper simply mounts minimal assigns and renders a lightweight
  placeholder shell so the route resolves cleanly without warnings or
  undefined module errors.

  TODO (upgrade path):
  1. Convert `ThunderlineWeb.Live.Components.ThunderlaneDashboard` into a
     proper set of stateless function components (or a LiveComponent)
     and invoke it from here.
  2. Or, switch the router to point directly at the existing module and
     repurpose this wrapper as a coordination layer (telemetry, auth,
     feature flags, etc.).
  3. Consolidate duplicated gradient/animation CSS into an extracted
     asset or Tailwind component utilities.
  """
  use ThunderlineWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Logger.debug("[ThunderlaneDashboard] mounted placeholder LiveView")
    end

    {:ok,
     socket
     |> assign(:page_title, "Thunderlane Dashboard")
     |> assign(:placeholder, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="thunderlane-dashboard-placeholder px-8 py-10">
      <h1 class="text-3xl font-bold text-gray-900 mb-4">⚡ Thunderlane Dashboard</h1>
      <p class="text-gray-600 mb-6 max-w-2xl">This is a temporary placeholder LiveView. The immersive visualization (nested hexagonal lanes, radial consensus bursts, flowing performance gradients, and telemetry layers) is implemented in <code>ThunderlineWeb.Live.Components.ThunderlaneDashboard</code> and will be integrated here after component extraction/refactor.</p>

      <div class="mt-8 p-6 rounded-lg border border-dashed border-gray-300 bg-white shadow-sm">
        <h2 class="text-xl font-semibold mb-2">Next Steps</h2>
        <ul class="list-disc ml-6 space-y-1 text-sm text-gray-700">
          <li>Extract visual panels from the component module into function components.</li>
          <li>Stream real metrics & events via PubSub topics (e.g. <code>"thunderlane:dashboard"</code>).</li>
          <li>Attach telemetry handlers for per‑panel performance instrumentation.</li>
          <li>Add feature flag gating & role based authorization via AshPolicies.</li>
        </ul>
      </div>

      <div class="mt-10 text-xs text-gray-400 font-mono">placeholder:true • route alive • refactor pending</div>
    </div>
    """
  end
end
