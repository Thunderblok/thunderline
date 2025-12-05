defmodule Thunderline.Thunderpac.MemoryModule do
  @moduledoc """
  HC-75: Deep MLP memory substrate for PACs (Titans-style).

  Implements a surprise-gated memory system based on Google's Titans paper.
  The memory is a deep MLP whose weights encode compressed experience.

  ## Architecture (Titans)

  The memory is a multi-layer perceptron where:
  - Weights encode compressed historical information
  - Reads: Forward pass through MLP
  - Writes: Gradient-like weight updates (when surprised)
  - Forgetting: Weight decay (configurable retention)

  ## Surprise Gating

  Memory only writes when surprise exceeds threshold:
  - surprise = momentum-smoothed ‖∇ℓ‖ (from SurpriseMetrics)
  - High surprise → write to memory (novel experience)
  - Low surprise → no write (familiar input)

  ## MIRAS 4-Choice Configuration

  1. **Memory Architecture**: Deep MLP (configurable depth/width)
  2. **Attentional Bias**: Optional cross-attention on read
  3. **Retention Gate**: Weight decay coefficient
  4. **Update Algorithm**: Surprise-gated gradient descent

  ## Events

  - `pac.memory.write` - Emitted when memory is written
  - `pac.memory.read` - Emitted on memory read operations
  - `pac.memory.surprise` - Emitted on surprise threshold crossing

  ## Telemetry

  - `[:thunderline, :pac, :memory, :write]` - Write operations
  - `[:thunderline, :pac, :memory, :read]` - Read operations
  - `[:thunderline, :pac, :memory, :decay]` - Decay/forgetting events

  ## References

  - Titans: Learning to Memorize at Test Time (Google, 2025)
  - MIRAS: Unlocking Expressivity and Safety (2025)
  """

  use GenServer
  require Logger
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Thunderbolt.Signal.SurpriseMetrics

  # ──────────────────────────────────────────────────────────────────────
  # Types & Configuration
  # ──────────────────────────────────────────────────────────────────────

  @type config :: %{
          depth: pos_integer(),
          width: pos_integer(),
          input_dim: pos_integer(),
          output_dim: pos_integer(),
          surprise_threshold: float(),
          momentum_beta: float(),
          weight_decay: float(),
          write_lr: float(),
          activation: :relu | :tanh | :gelu | :linear
        }

  @type layer :: %{weights: list(list(float())), bias: list(float())}

  @type t :: %__MODULE__{
          pac_id: String.t(),
          config: config(),
          layers: list(layer()),
          surprise_state: SurpriseMetrics.surprise_state(),
          write_count: non_neg_integer(),
          read_count: non_neg_integer(),
          decay_count: non_neg_integer(),
          created_at: DateTime.t(),
          last_write_at: DateTime.t() | nil,
          last_read_at: DateTime.t() | nil
        }

  defstruct [
    :pac_id,
    :config,
    :layers,
    :surprise_state,
    write_count: 0,
    read_count: 0,
    decay_count: 0,
    created_at: nil,
    last_write_at: nil,
    last_read_at: nil
  ]

  @default_config %{
    depth: 3,
    width: 64,
    input_dim: 32,
    output_dim: 32,
    surprise_threshold: 0.1,
    momentum_beta: 0.9,
    weight_decay: 0.99,
    write_lr: 0.01,
    activation: :relu
  }

  # ──────────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Starts a MemoryModule for a specific PAC.

  ## Options

  - `:pac_id` - Required. PAC identifier.
  - `:config` - Optional. Memory configuration map (merged with defaults).
  - `:name` - Optional. GenServer name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    pac_id = Keyword.fetch!(opts, :pac_id)
    config = Keyword.get(opts, :config, %{})
    name = Keyword.get(opts, :name, via(pac_id))

    merged_config = Map.merge(@default_config, config)

    GenServer.start_link(__MODULE__, {pac_id, merged_config}, name: name)
  end

  @doc """
  Reads from memory by forwarding input through the MLP.
  Returns the output vector.
  """
  @spec read(String.t() | GenServer.server(), list(number())) :: {:ok, list(float())} | {:error, term()}
  def read(pac_id_or_server, query) when is_list(query) do
    server = resolve_server(pac_id_or_server)
    GenServer.call(server, {:read, query})
  end

  @doc """
  Attempts to write to memory if surprise exceeds threshold.
  Takes input, predicted output, and actual output.
  Computes surprise internally and gates the write.

  Returns `{:ok, :written}` or `{:ok, :skipped}` based on surprise.
  """
  @spec maybe_write(String.t() | GenServer.server(), list(number()), list(number()), list(number())) ::
          {:ok, :written | :skipped} | {:error, term()}
  def maybe_write(pac_id_or_server, input, predicted, actual)
      when is_list(input) and is_list(predicted) and is_list(actual) do
    server = resolve_server(pac_id_or_server)
    GenServer.call(server, {:maybe_write, input, predicted, actual})
  end

  @doc """
  Forces a write to memory regardless of surprise level.
  Use sparingly for explicit memory updates.
  """
  @spec force_write(String.t() | GenServer.server(), list(number())) :: :ok | {:error, term()}
  def force_write(pac_id_or_server, input) when is_list(input) do
    server = resolve_server(pac_id_or_server)
    GenServer.call(server, {:force_write, input})
  end

  @doc """
  Applies decay (forgetting) to memory weights.
  Called periodically to implement controlled forgetting.
  """
  @spec apply_decay(String.t() | GenServer.server()) :: :ok
  def apply_decay(pac_id_or_server) do
    server = resolve_server(pac_id_or_server)
    GenServer.cast(server, :apply_decay)
  end

  @doc """
  Gets the current memory state and statistics.
  """
  @spec get_state(String.t() | GenServer.server()) :: map()
  def get_state(pac_id_or_server) do
    server = resolve_server(pac_id_or_server)
    GenServer.call(server, :get_state)
  end

  @doc """
  Gets memory utilization metrics.
  """
  @spec get_metrics(String.t() | GenServer.server()) :: map()
  def get_metrics(pac_id_or_server) do
    server = resolve_server(pac_id_or_server)
    GenServer.call(server, :get_metrics)
  end

  @doc """
  Resets memory to initial random state.
  """
  @spec reset(String.t() | GenServer.server()) :: :ok
  def reset(pac_id_or_server) do
    server = resolve_server(pac_id_or_server)
    GenServer.call(server, :reset)
  end

  # ──────────────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ──────────────────────────────────────────────────────────────────────

  @impl true
  def init({pac_id, config}) do
    layers = initialize_layers(config)

    surprise_state = SurpriseMetrics.new(
      pac_id: pac_id,
      beta: config.momentum_beta,
      threshold: config.surprise_threshold
    )

    state = %__MODULE__{
      pac_id: pac_id,
      config: config,
      layers: layers,
      surprise_state: surprise_state,
      created_at: DateTime.utc_now()
    }

    Logger.debug("MemoryModule started for PAC #{pac_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:read, query}, _from, state) do
    output = forward_pass(state.layers, query, state.config.activation)

    new_state = %{
      state
      | read_count: state.read_count + 1,
        last_read_at: DateTime.utc_now()
    }

    emit_read_event(state.pac_id, query, output)
    emit_read_telemetry(state.pac_id)

    {:reply, {:ok, output}, new_state}
  end

  @impl true
  def handle_call({:maybe_write, input, predicted, actual}, _from, state) do
    raw_surprise = SurpriseMetrics.surprise_metric(predicted, actual)
    {new_surprise_state, should_write} = SurpriseMetrics.update(state.surprise_state, raw_surprise)

    {result, new_state} =
      if should_write do
        updated_layers = gradient_write(state.layers, input, state.config)
        emit_write_event(state.pac_id, input, new_surprise_state.momentum)
        emit_write_telemetry(state.pac_id, raw_surprise)

        new_state = %{
          state
          | layers: updated_layers,
            surprise_state: new_surprise_state,
            write_count: state.write_count + 1,
            last_write_at: DateTime.utc_now()
        }

        {{:ok, :written}, new_state}
      else
        new_state = %{state | surprise_state: new_surprise_state}
        {{:ok, :skipped}, new_state}
      end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:force_write, input}, _from, state) do
    updated_layers = gradient_write(state.layers, input, state.config)
    emit_write_event(state.pac_id, input, 1.0)
    emit_write_telemetry(state.pac_id, 1.0)

    new_state = %{
      state
      | layers: updated_layers,
        write_count: state.write_count + 1,
        last_write_at: DateTime.utc_now()
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      pac_id: state.pac_id,
      config: state.config,
      write_count: state.write_count,
      read_count: state.read_count,
      decay_count: state.decay_count,
      created_at: state.created_at,
      last_write_at: state.last_write_at,
      last_read_at: state.last_read_at,
      surprise_stats: SurpriseMetrics.statistics(state.surprise_state),
      layer_count: length(state.layers)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      pac_id: state.pac_id,
      write_count: state.write_count,
      read_count: state.read_count,
      decay_count: state.decay_count,
      write_rate: SurpriseMetrics.write_rate(state.surprise_state),
      memory_utilization: compute_utilization(state.layers),
      weight_magnitude: compute_weight_magnitude(state.layers),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.created_at)
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_layers = initialize_layers(state.config)
    new_surprise_state = SurpriseMetrics.new(
      pac_id: state.pac_id,
      beta: state.config.momentum_beta,
      threshold: state.config.surprise_threshold
    )

    new_state = %{
      state
      | layers: new_layers,
        surprise_state: new_surprise_state,
        write_count: 0,
        read_count: 0,
        decay_count: 0,
        created_at: DateTime.utc_now(),
        last_write_at: nil,
        last_read_at: nil
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:apply_decay, state) do
    decayed_layers = apply_weight_decay(state.layers, state.config.weight_decay)

    new_state = %{
      state
      | layers: decayed_layers,
        decay_count: state.decay_count + 1
    }

    emit_decay_telemetry(state.pac_id)
    {:noreply, new_state}
  end

  # ──────────────────────────────────────────────────────────────────────
  # Layer Operations (Pure Functions)
  # ──────────────────────────────────────────────────────────────────────

  @doc false
  def initialize_layers(config) do
    # Create layer dimensions: input -> hidden -> ... -> output
    dims = [config.input_dim] ++ List.duplicate(config.width, config.depth - 1) ++ [config.output_dim]

    dims
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [in_dim, out_dim] ->
      %{
        weights: random_matrix(in_dim, out_dim, 0.1),
        bias: List.duplicate(0.0, out_dim)
      }
    end)
  end

  defp random_matrix(rows, cols, scale) do
    for _ <- 1..rows do
      for _ <- 1..cols do
        (:rand.uniform() - 0.5) * 2 * scale
      end
    end
  end

  defp forward_pass(layers, input, activation) do
    Enum.reduce(layers, input, fn layer, acc ->
      # Matrix multiplication: acc @ weights + bias
      output = matmul(acc, layer.weights)
      |> add_bias(layer.bias)
      |> apply_activation(activation)

      output
    end)
  end

  defp matmul(vector, matrix) when is_list(vector) and is_list(matrix) do
    # vector: [n] x matrix: [n x m] -> [m]
    matrix
    |> transpose()
    |> Enum.map(fn col ->
      Enum.zip(vector, col)
      |> Enum.map(fn {v, c} -> v * c end)
      |> Enum.sum()
    end)
  end

  defp transpose(matrix) do
    matrix
    |> List.zip()
    |> Enum.map(&Tuple.to_list/1)
  end

  defp add_bias(vector, bias) do
    Enum.zip(vector, bias)
    |> Enum.map(fn {v, b} -> v + b end)
  end

  defp apply_activation(vector, :relu) do
    Enum.map(vector, &max(&1, 0.0))
  end

  defp apply_activation(vector, :tanh) do
    Enum.map(vector, &:math.tanh/1)
  end

  defp apply_activation(vector, :gelu) do
    # Approximate GELU: x * sigmoid(1.702 * x)
    Enum.map(vector, fn x ->
      x * (1.0 / (1.0 + :math.exp(-1.702 * x)))
    end)
  end

  defp apply_activation(vector, _), do: vector

  defp gradient_write(layers, input, config) do
    # Simplified Hebbian-style update: outer product of input with itself
    # In full implementation, would use actual gradients
    lr = config.write_lr

    # Normalize input for stable updates
    norm = :math.sqrt(Enum.sum(Enum.map(input, &(&1 * &1))) + 1.0e-8)
    normalized = Enum.map(input, &(&1 / norm))

    Enum.map(layers, fn layer ->
      # Update weights with outer-product-like term
      new_weights =
        Enum.with_index(layer.weights)
        |> Enum.map(fn {row, i} ->
          input_val = Enum.at(normalized, rem(i, length(normalized)), 0.0)

          Enum.with_index(row)
          |> Enum.map(fn {w, j} ->
            target_val = Enum.at(normalized, rem(j, length(normalized)), 0.0)
            w + lr * input_val * target_val
          end)
        end)

      # Update bias slightly
      new_bias =
        Enum.with_index(layer.bias)
        |> Enum.map(fn {b, i} ->
          input_val = Enum.at(normalized, rem(i, length(normalized)), 0.0)
          b + lr * 0.1 * input_val
        end)

      %{layer | weights: new_weights, bias: new_bias}
    end)
  end

  defp apply_weight_decay(layers, decay) do
    Enum.map(layers, fn layer ->
      decayed_weights = Enum.map(layer.weights, fn row ->
        Enum.map(row, &(&1 * decay))
      end)

      decayed_bias = Enum.map(layer.bias, &(&1 * decay))

      %{layer | weights: decayed_weights, bias: decayed_bias}
    end)
  end

  defp compute_utilization(layers) do
    # Compute fraction of weights above threshold (active capacity)
    threshold = 0.01
    total = 0
    active = 0

    {total, active} =
      Enum.reduce(layers, {total, active}, fn layer, {t, a} ->
        layer_total = length(layer.weights) * length(List.first(layer.weights, []))
        layer_active =
          layer.weights
          |> List.flatten()
          |> Enum.count(&(abs(&1) > threshold))

        {t + layer_total, a + layer_active}
      end)

    if total > 0, do: active / total, else: 0.0
  end

  defp compute_weight_magnitude(layers) do
    # L2 norm of all weights
    sum_sq =
      layers
      |> Enum.flat_map(fn layer ->
        List.flatten(layer.weights) ++ layer.bias
      end)
      |> Enum.map(&(&1 * &1))
      |> Enum.sum()

    :math.sqrt(sum_sq)
  end

  # ──────────────────────────────────────────────────────────────────────
  # Events & Telemetry
  # ──────────────────────────────────────────────────────────────────────

  defp emit_write_event(pac_id, input, surprise) do
    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "pac.memory.write",
             source: :thunderpac,
             payload: %{
               pac_id: pac_id,
               surprise: surprise,
               input_size: length(input)
             },
             meta: %{component: "memory_module", pipeline: :memory},
             type: :state_change
           ),
         {:ok, _} <- EventBus.publish_event(ev) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("MemoryModule write event failed: #{inspect(reason)}")
    end
  rescue
    _ -> :ok
  end

  defp emit_read_event(pac_id, query, output) do
    with {:ok, ev} <-
           Thunderline.Event.new(
             name: "pac.memory.read",
             source: :thunderpac,
             payload: %{
               pac_id: pac_id,
               query_size: length(query),
               output_size: length(output)
             },
             meta: %{component: "memory_module", pipeline: :memory},
             type: :query
           ),
         {:ok, _} <- EventBus.publish_event(ev) do
      :ok
    else
      {:error, reason} ->
        Logger.debug("MemoryModule read event failed: #{inspect(reason)}")
    end
  rescue
    _ -> :ok
  end

  defp emit_write_telemetry(pac_id, surprise) do
    :telemetry.execute(
      [:thunderline, :pac, :memory, :write],
      %{surprise: surprise, count: 1},
      %{pac_id: pac_id}
    )
  end

  defp emit_read_telemetry(pac_id) do
    :telemetry.execute(
      [:thunderline, :pac, :memory, :read],
      %{count: 1},
      %{pac_id: pac_id}
    )
  end

  defp emit_decay_telemetry(pac_id) do
    :telemetry.execute(
      [:thunderline, :pac, :memory, :decay],
      %{count: 1},
      %{pac_id: pac_id}
    )
  end

  # ──────────────────────────────────────────────────────────────────────
  # Registry & Resolution
  # ──────────────────────────────────────────────────────────────────────

  defp via(pac_id), do: {:via, Registry, {Thunderline.Thunderpac.Registry, {:memory, pac_id}}}

  defp resolve_server(pac_id) when is_binary(pac_id), do: via(pac_id)
  defp resolve_server(server), do: server
end
