defmodule ThunderlineWeb.ThunderprismLive do
  @moduledoc """
  ThunderPrism 3D DAG Visualizer LiveView.

  Interactive 3D force-directed graph visualization of ML decision trails
  from the ThunderPrism DAG scratchpad. Enables exploration of:
  - PAC (Parzen Adaptive Controller) decision history
  - Model selection patterns over iterations
  - Decision node relationships and flow

  Features:
  - 3D force-directed graph with Three.js
  - Node selection and inspection
  - Real-time updates via PubSub
  - Filtering by PAC ID and time range
  """
  use ThunderlineWeb, :live_view

  require Logger

  @pubsub_topic "thunderprism:updates"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, @pubsub_topic)
    end

    # Ensure current_scope is assigned (may be set by AshAuthentication.Phoenix.LiveSession on_mount)
    current_scope = Map.get(socket.assigns, :current_scope)

    socket =
      socket
      |> assign_new(:current_scope, fn -> current_scope end)
      |> assign(:page_title, "ThunderPrism DAG")
      |> assign(:selected_node, nil)
      |> assign(:pac_filter, nil)
      |> assign(:limit, 100)
      |> assign(:node_count, 0)
      |> assign(:link_count, 0)
      |> assign(:loading, true)
      |> assign(:pac_ids, [])
      |> load_pac_ids()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    pac_filter = params["pac_id"]
    limit = parse_int(params["limit"], 100)

    socket =
      socket
      |> assign(:pac_filter, pac_filter)
      |> assign(:limit, limit)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-base-200">
        <!-- Header -->
        <div class="navbar bg-base-300 border-b border-white/10">
          <div class="flex-1">
            <div class="flex items-center gap-3">
              <div class="w-3 h-3 rounded-full bg-cyan-400 animate-pulse" />
              <h1 class="text-lg font-semibold">ThunderPrism DAG</h1>
              <span class="badge badge-outline badge-sm">ML Decision Trails</span>
            </div>
          </div>
          <div class="flex-none gap-2">
            <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Dashboard
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-4 gap-4 p-4">
          <!-- Controls Panel -->
          <div class="lg:col-span-1 space-y-4">
            <!-- Filters -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-funnel" class="w-4 h-4" /> Filters
                </h2>

                <form phx-change="filter_changed" class="space-y-3">
                  <div class="form-control">
                    <label class="label py-1">
                      <span class="label-text text-xs">PAC ID</span>
                    </label>
                    <select name="pac_id" class="select select-bordered select-sm w-full">
                      <option value="">All PACs</option>
                      <%= for pac_id <- @pac_ids do %>
                        <option value={pac_id} selected={@pac_filter == pac_id}>
                          {pac_id}
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="form-control">
                    <label class="label py-1">
                      <span class="label-text text-xs">Node Limit</span>
                    </label>
                    <select name="limit" class="select select-bordered select-sm w-full">
                      <%= for limit <- [50, 100, 200, 500] do %>
                        <option value={limit} selected={@limit == limit}>
                          {limit} nodes
                        </option>
                      <% end %>
                    </select>
                  </div>
                </form>

                <div class="divider my-2" />
                
    <!-- Stats -->
                <div class="stats stats-vertical shadow bg-base-200">
                  <div class="stat py-2">
                    <div class="stat-title text-xs">Nodes</div>
                    <div class="stat-value text-lg text-cyan-400">{@node_count}</div>
                  </div>
                  <div class="stat py-2">
                    <div class="stat-title text-xs">Links</div>
                    <div class="stat-value text-lg text-emerald-400">{@link_count}</div>
                  </div>
                </div>

                <button phx-click="refresh_graph" class="btn btn-primary btn-sm w-full mt-2">
                  <.icon name="hero-arrow-path" class="w-4 h-4" /> Refresh
                </button>

                <button phx-click="generate_test_data" class="btn btn-secondary btn-sm w-full mt-2">
                  <.icon name="hero-beaker" class="w-4 h-4" /> Generate Test Data
                </button>
              </div>
            </div>
            
    <!-- Node Inspector -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-magnifying-glass" class="w-4 h-4" /> Node Inspector
                </h2>

                <%= if @selected_node do %>
                  <div class="space-y-3">
                    <div class="flex items-center justify-between">
                      <span class="badge badge-primary">{@selected_node.chosen_model}</span>
                      <button phx-click="clear_selection" class="btn btn-ghost btn-xs">
                        <.icon name="hero-x-mark" class="w-3 h-3" />
                      </button>
                    </div>

                    <div class="text-xs space-y-2">
                      <div class="flex justify-between">
                        <span class="text-base-content/60">ID</span>
                        <span class="font-mono">{short_id(@selected_node.id)}</span>
                      </div>
                      <div class="flex justify-between">
                        <span class="text-base-content/60">PAC</span>
                        <span class="font-mono">{@selected_node.pac_id}</span>
                      </div>
                      <div class="flex justify-between">
                        <span class="text-base-content/60">Iteration</span>
                        <span class="font-mono">{@selected_node.iteration}</span>
                      </div>
                    </div>

                    <%= if @selected_node.meta && @selected_node.meta != %{} do %>
                      <div class="divider my-1 text-xs">Metadata</div>
                      <div class="bg-base-200 rounded-lg p-2 text-xs font-mono overflow-x-auto">
                        <pre class="whitespace-pre-wrap">{Jason.encode!(@selected_node.meta, pretty: true)}</pre>
                      </div>
                    <% end %>

                    <div class="flex gap-2">
                      <button
                        phx-click="view_edges"
                        phx-value-id={@selected_node.id}
                        class="btn btn-outline btn-xs flex-1"
                      >
                        View Edges
                      </button>
                      <button
                        phx-click="filter_by_pac"
                        phx-value-pac={@selected_node.pac_id}
                        class="btn btn-outline btn-xs flex-1"
                      >
                        Filter PAC
                      </button>
                    </div>
                  </div>
                <% else %>
                  <div class="text-center py-8 text-base-content/50">
                    <.icon name="hero-cursor-arrow-rays" class="w-8 h-8 mx-auto mb-2 opacity-50" />
                    <p class="text-xs">Click a node to inspect</p>
                  </div>
                <% end %>
              </div>
            </div>
            
    <!-- Legend -->
            <div class="card bg-base-300 shadow-xl">
              <div class="card-body p-4">
                <h2 class="card-title text-sm">
                  <.icon name="hero-swatch" class="w-4 h-4" /> Legend
                </h2>
                <div class="space-y-2 text-xs">
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-cyan-400" />
                    <span>model_a</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-emerald-400" />
                    <span>model_b</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-amber-400" />
                    <span>model_c</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-violet-400" />
                    <span>model_d</span>
                  </div>
                </div>
                <div class="divider my-1" />
                <div class="text-xs text-base-content/60">
                  <p>• Node size = iteration depth</p>
                  <p>• Lines = decision flow</p>
                  <p>• Drag to rotate, scroll to zoom</p>
                </div>
              </div>
            </div>
          </div>
          
    <!-- 3D Graph Container - React Three Fiber -->
          <div class="lg:col-span-3">
            <div class="card bg-base-300 shadow-xl h-[calc(100vh-8rem)]">
              <div class="card-body p-0 overflow-hidden rounded-2xl">
                <div
                  id="thunderprism-root"
                  phx-hook="ThunderPrismReact"
                  phx-update="ignore"
                  data-pac-id={@pac_filter || ""}
                  data-limit={@limit}
                  class="w-full h-full min-h-[500px]"
                >
                  <%= if @loading do %>
                    <div class="flex items-center justify-center h-full">
                      <span class="loading loading-spinner loading-lg text-primary"></span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter_changed", %{"pac_id" => pac_id, "limit" => limit}, socket) do
    pac_filter = if pac_id == "", do: nil, else: pac_id
    limit = parse_int(limit, 100)

    socket =
      socket
      |> assign(:pac_filter, pac_filter)
      |> assign(:limit, limit)
      |> push_event("graph_updated", load_graph_data(pac_filter, limit))

    {:noreply, socket}
  end

  def handle_event("filter_changed", params, socket) do
    pac_id = Map.get(params, "pac_id", "")
    limit = Map.get(params, "limit", "100")
    handle_event("filter_changed", %{"pac_id" => pac_id, "limit" => limit}, socket)
  end

  def handle_event("refresh_graph", _params, socket) do
    data = load_graph_data(socket.assigns.pac_filter, socket.assigns.limit)

    socket =
      socket
      |> push_event("graph_updated", data)

    {:noreply, socket}
  end

  def handle_event("node_selected", params, socket) do
    node = %{
      id: params["id"],
      pac_id: params["pac_id"],
      iteration: params["iteration"],
      chosen_model: params["chosen_model"],
      meta: params["meta"] || %{}
    }

    {:noreply, assign(socket, :selected_node, node)}
  end

  def handle_event("node_deselected", _params, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("clear_selection", _params, socket) do
    socket =
      socket
      |> assign(:selected_node, nil)
      |> push_event("clear_selection", %{})

    {:noreply, socket}
  end

  def handle_event("graph_loaded", %{"node_count" => nc, "link_count" => lc}, socket) do
    socket =
      socket
      |> assign(:node_count, nc)
      |> assign(:link_count, lc)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  def handle_event("view_edges", %{"id" => id}, socket) do
    # Could open a modal or navigate to edges view
    Logger.info("View edges for node: #{id}")
    {:noreply, put_flash(socket, :info, "Edge view coming soon for #{short_id(id)}")}
  end

  def handle_event("filter_by_pac", %{"pac" => pac_id}, socket) do
    socket =
      socket
      |> assign(:pac_filter, pac_id)
      |> push_event("graph_updated", load_graph_data(pac_id, socket.assigns.limit))

    {:noreply, socket}
  end

  def handle_event("generate_test_data", _params, socket) do
    # Generate sample PAC decision nodes
    pac_ids = ["pac_alpha", "pac_beta", "pac_gamma"]
    models = [:model_a, :model_b, :model_c, :model_d]

    # Create nodes for each PAC with sequential iterations
    created_nodes =
      for pac_id <- pac_ids, iteration <- 1..10 do
        chosen = Enum.random(models)
        probs = generate_model_probs(models, chosen)
        dists = generate_model_distances(models, chosen)

        attrs = %{
          pac_id: pac_id,
          iteration: iteration,
          chosen_model: chosen,
          model_probabilities: probs,
          model_distances: dists,
          timestamp: DateTime.utc_now(),
          meta: %{
            "generated" => true,
            "seed" => :rand.uniform(1000)
          }
        }

        Thunderline.Thunderprism.MLTap.log_node(attrs)
      end

    # Wait briefly for async tasks
    Process.sleep(500)

    # Reload graph and update PAC IDs
    socket =
      socket
      |> load_pac_ids()
      |> push_event(
        "graph_updated",
        load_graph_data(socket.assigns.pac_filter, socket.assigns.limit)
      )
      |> put_flash(:info, "Generated #{length(created_nodes)} test nodes!")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:prism_node_created, _node}, socket) do
    # Real-time update when new nodes are created
    data = load_graph_data(socket.assigns.pac_filter, socket.assigns.limit)

    socket =
      socket
      |> push_event("graph_updated", data)

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Private functions

  defp load_pac_ids(socket) do
    case Ash.read(Thunderline.Thunderprism.PrismNode) do
      {:ok, nodes} ->
        pac_ids =
          nodes
          |> Enum.map(& &1.pac_id)
          |> Enum.uniq()
          |> Enum.sort()

        assign(socket, :pac_ids, pac_ids)

      {:error, _} ->
        assign(socket, :pac_ids, [])
    end
  end

  defp load_graph_data(pac_filter, limit) do
    query =
      Thunderline.Thunderprism.PrismNode
      |> Ash.Query.load([:out_edges])
      |> Ash.Query.limit(limit)

    query =
      if pac_filter && pac_filter != "" do
        require Ash.Query
        Ash.Query.filter(query, pac_id: pac_filter)
      else
        query
      end

    case Ash.read(query) do
      {:ok, nodes} ->
        graph_nodes =
          Enum.map(nodes, fn node ->
            %{
              id: node.id,
              pac_id: node.pac_id,
              iteration: node.iteration,
              chosen_model: node.chosen_model,
              meta: node.meta
            }
          end)

        graph_links =
          nodes
          |> Enum.flat_map(fn node ->
            Enum.map(node.out_edges || [], fn edge ->
              %{
                source: edge.from_id,
                target: edge.to_id,
                relation_type: edge.relation_type
              }
            end)
          end)

        %{nodes: graph_nodes, links: graph_links}

      {:error, _} ->
        %{nodes: [], links: []}
    end
  end

  defp short_id(nil), do: "n/a"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(id), do: to_string(id)

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  defp generate_model_probs(models, chosen) do
    # Give chosen model highest probability
    base_probs =
      models
      |> Enum.map(fn model ->
        if model == chosen do
          {model, 0.5 + :rand.uniform() * 0.3}
        else
          {model, :rand.uniform() * 0.2}
        end
      end)
      |> Map.new()

    # Normalize to sum to 1.0
    total = base_probs |> Map.values() |> Enum.sum()
    Map.new(base_probs, fn {k, v} -> {k, Float.round(v / total, 3)} end)
  end

  defp generate_model_distances(models, chosen) do
    # Give chosen model lowest distance
    models
    |> Enum.map(fn model ->
      dist =
        if model == chosen do
          :rand.uniform() * 0.1
        else
          0.1 + :rand.uniform() * 0.4
        end

      {model, Float.round(dist, 4)}
    end)
    |> Map.new()
  end
end
