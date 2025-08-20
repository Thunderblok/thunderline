defmodule ThunderlineWeb.NNPlaygroundLive do
  @moduledoc """
  Interactive neural network playground LiveView.

  Inspired by public NN visualizers (e.g. nn.ameo.dev / TensorFlow Playground),
  this view lets users dynamically configure a small feed-forward network and
  watch forward activations update in real-time.

  Phase 1 (this commit):
    * Layer list with add/remove hidden layers
    * Per-layer neuron count slider
    * Activation function select (subset)
    * Simple synthetic 2D dataset selector
    * Forward pass visualization (activations as colored grid)
    * Live recompute as params change (no train loop yet)

  Future phases:
    * Training loop with adjustable learning rate & batch size
    * Weight initialization strategies & live weight histogram
    * Loss curve plot via hooks / chart library
    * Decision boundary plot using canvas/WebGL
    * Export/import model config
  """
  use ThunderlineWeb, :live_view
  require Logger

  alias Nx.Tensor

  # Supported activation function atoms. Implementations handled in apply_activation/2.
  @activation_functions [:relu, :tanh, :sigmoid, :linear]

  @datasets [:circles, :xor, :gaussians]

  # -- Public LiveView callbacks ------------------------------------------------
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :recompute, 10)

    {:ok,
     socket
     |> assign(:page_title, "NN Playground")
     |> assign(:layers, default_layers())
     |> assign(:input_dim, 2)
     |> assign(:output_dim, 1)
     |> assign(:dataset, :xor)
     |> assign(:activations, [])
     |> assign(:activation_preview, nil)
  |> assign(:activation_functions, @activation_functions)
     |> assign(:datasets, @datasets)
     |> assign(:dirty?, true)
     |> assign(:seed, System.unique_integer())}
  end

  @impl true
  def handle_info(:recompute, socket) do
    socket = recompute_forward(socket)
    {:noreply, socket}
  end

  # UI Events ------------------------------------------------------------------
  @impl true
  def handle_event("add_hidden_layer", _params, socket) do
    layers = socket.assigns.layers ++ [hidden_layer(16)]
    {:noreply, mark_dirty(socket |> assign(:layers, layers))}
  end

  def handle_event("remove_layer", %{"index" => idx}, socket) do
    {i, _} = Integer.parse(idx)
    layers = socket.assigns.layers |> Enum.with_index() |> Enum.reject(fn {_l, j} -> j == i end) |> Enum.map(&elem(&1,0))
    {:noreply, mark_dirty(assign(socket, :layers, layers))}
  end

  def handle_event("update_neurons", %{"index" => idx, "value" => v}, socket) do
    {i, _} = Integer.parse(idx)
    {n, _} = Integer.parse(v)
    layers = update_in(socket.assigns.layers, [Access.at(i), :neurons], fn _ -> clamp(n, 1, 256) end)
    {:noreply, mark_dirty(assign(socket, :layers, layers))}
  end

  def handle_event("set_activation", %{"index" => idx, "value" => act}, socket) do
    {i, _} = Integer.parse(idx)
    act_atom = String.to_existing_atom(act)
    layers = update_in(socket.assigns.layers, [Access.at(i), :activation], fn _ -> act_atom end)
    {:noreply, mark_dirty(assign(socket, :layers, layers))}
  end

  def handle_event("select_dataset", %{"dataset" => ds}, socket) do
    ds_atom = String.to_existing_atom(ds)
    {:noreply, mark_dirty(assign(socket, :dataset, ds_atom))}
  end

  def handle_event("reseed", _params, socket) do
    {:noreply, mark_dirty(assign(socket, :seed, System.unique_integer()))}
  end

  # -- Rendering ----------------------------------------------------------------
  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-6 py-4 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-semibold text-white">Neural Network Playground</h1>
        <div class="flex items-center gap-4 text-xs text-gray-400">
          <span>Dataset:</span>
          <select name="dataset" phx-change="select_dataset" class="bg-gray-800 text-white rounded px-2 py-1 border border-gray-600">
            <%= for d <- @datasets do %>
              <option value={d} selected={d == @dataset}><%= d %></option>
            <% end %>
          </select>
          <button phx-click="reseed" class="px-2 py-1 bg-indigo-600 text-white rounded">Reseed</button>
          <button phx-click="add_hidden_layer" class="px-2 py-1 bg-emerald-600 text-white rounded">Add Layer</button>
          <%= if @dirty? do %>
            <span class="ml-4 text-yellow-400">(recomputing)</span>
          <% end %>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="space-y-4">
          <h2 class="text-sm font-semibold text-gray-300">Architecture</h2>
          <div class="space-y-4">
            <%= for {layer, idx} <- Enum.with_index(@layers) do %>
              <div class="p-3 rounded bg-gray-800 border border-gray-700 space-y-2">
                <div class="flex items-center justify-between text-gray-200 text-sm">
                  <span>Hidden Layer <%= idx+1 %></span>
                  <button phx-click="remove_layer" phx-value-index={idx} class="text-red-400 hover:text-red-300">✕</button>
                </div>
                <div class="flex items-center gap-3 text-xs text-gray-400">
                  <label>Neurons</label>
                  <input type="range" min="1" max="256" value={layer.neurons} phx-change="update_neurons" phx-value-index={idx} class="flex-1" />
                  <span class="w-10 text-right text-gray-300"><%= layer.neurons %></span>
                </div>
                <div class="flex items-center gap-3 text-xs text-gray-400">
                  <label class="whitespace-nowrap">Activation</label>
                  <select phx-change="set_activation" phx-value-index={idx} class="bg-gray-900 text-white rounded px-2 py-1 border border-gray-600">
                    <%= for a <- @activation_functions do %>
                      <option value={a} selected={a == layer.activation}><%= a %></option>
                    <% end %>
                  </select>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div>
          <h2 class="text-sm font-semibold text-gray-300 mb-2">Activations Preview</h2>
          <div class="space-y-4">
            <%= for {act, idx} <- Enum.with_index(@activations) do %>
              <div>
                <div class="text-xs mb-1 text-gray-400">Layer <%= idx+1 %> activations (min=<%= Float.round(act.min,4) %> max=<%= Float.round(act.max,4) %>)</div>
                <div class="grid gap-0.5" style={"grid-template-columns: repeat(#{act.width}, minmax(0, 1fr));"}>
                  <%= for cell <- act.cells do %>
                    <div style={"background: #{cell}; padding-top: 100%;"} class="rounded-sm"></div>
                  <% end %>
                </div>
              </div>
            <% end %>
            <%= if @activations == [] do %>
              <div class="text-xs text-gray-500">(No activations yet)</div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Forward pass simulation --------------------------------------------------
  defp recompute_forward(socket) do
    layers = socket.assigns.layers
    dataset = build_dataset(socket.assigns.dataset, socket.assigns.seed)

    # Build weight matrices + pass
    {acts, _last} =
      Enum.reduce(layers, {[], dataset}, fn layer, {acc, input} ->
        w = Nx.random_uniform({input.shape[1], layer.neurons}, -0.5, 0.5, key: random_key(layer.neurons, socket.assigns.seed))
        z = Nx.dot(input, w)
        a = apply_activation(z, layer.activation)
        vis = activation_visual(a)
        {[vis | acc], a}
      end)

    socket
    |> assign(:activations, Enum.reverse(acts))
    |> assign(:dirty?, false)
  rescue
    e ->
      Logger.error("NN recompute failed: #{inspect(e)}")
      socket |> assign(:dirty?, false)
  end

  defp activation_visual(%Tensor{} = t) do
    flat = Nx.flatten(t)
    min = Nx.to_number(Nx.reduce_min(flat))
    max = Nx.to_number(Nx.reduce_max(flat))
    vals = Nx.to_flat_list(flat)
    width = t.shape |> Tuple.to_list() |> List.last()

    cells =
      Enum.map(vals, fn v ->
        norm = if max == min, do: 0.5, else: (v - min) / (max - min)
        heat_color(norm)
      end)

    %{min: min, max: max, width: width, cells: cells}
  end

  defp heat_color(n) do
    # simple blue -> red gradient
    r = trunc(n * 255)
    b = trunc((1 - n) * 255)
    g = trunc(100 * (1 - abs(0.5 - n)))
    "rgb(#{r},#{g},#{b})"
  end

  defp apply_activation(t, :relu), do: Nx.max(t, 0)
  defp apply_activation(t, :tanh), do: Nx.tanh(t)
  defp apply_activation(t, :sigmoid), do: sigmoid_tensor(t)
  defp apply_activation(t, :linear), do: t
  defp apply_activation(t, other) do
    Logger.warning("Unknown activation #{inspect(other)} – defaulting to linear")
    t
  end

  defp sigmoid(x) when is_number(x), do: 1.0 / (1.0 + :math.pow(:math.e(), -x))
  defp sigmoid_tensor(t), do: Nx.divide(1, Nx.add(1, Nx.exp(Nx.multiply(-1, t))))

  defp random_key(n, seed) do
    # Derive a deterministic key from seed + n
    <<k::128>> = :crypto.hash(:sha256, :erlang.term_to_binary({seed, n})) |> binary_part(0, 16)
    {hi, lo} = :binary.match(k, <<>>)
    {hi || 1, lo || 2}
  end

  # Simple synthetic datasets (Nx tensors)
  defp build_dataset(:xor, seed) do
    points = Nx.tensor([[0.0,0.0],[0.0,1.0],[1.0,0.0],[1.0,1.0]])
    shuffle(points, seed)
  end
  defp build_dataset(:circles, seed) do
    # Two concentric circles (rough)
    angles = Enum.map(0..31, &(&1 * :math.pi()/16))
    inner = Enum.map(angles, & [0.5*:math.cos(&1), 0.5*:math.sin(&1)])
    outer = Enum.map(angles, & [1.0*:math.cos(&1), 1.0*:math.sin(&1)])
    data = inner ++ outer
    shuffle(Nx.tensor(data), seed)
  end
  defp build_dataset(:gaussians, seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    cluster = fn cx, cy -> Enum.map(1..32, fn _ -> [cx + :rand.normal() * 0.1, cy + :rand.normal() * 0.1] end) end
    data = cluster.(0.0,0.0) ++ cluster.(1.0,1.0)
    shuffle(Nx.tensor(data), seed)
  end

  defp shuffle(t, seed) do
    idx = Enum.shuffle(:rand.seed_s(:exsss, {seed, seed, seed}) |> elem(1), Enum.to_list(0..(t.shape[0]-1)))
    Nx.take(t, Nx.tensor(idx))
  rescue
    _ -> t
  end

  # Helpers ---------------------------------------------------------------------
  defp default_layers, do: [hidden_layer(12), hidden_layer(8)]
  defp hidden_layer(n), do: %{neurons: n, activation: :relu}
  defp clamp(v, min, max) when v < min, do: min
  defp clamp(v, min, max) when v > max, do: max
  defp clamp(v, _min, _max), do: v
  defp mark_dirty(socket), do: (Process.send_after(self(), :recompute, 50); assign(socket, :dirty?, true))
end
