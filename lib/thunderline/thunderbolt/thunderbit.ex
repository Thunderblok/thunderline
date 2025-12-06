defmodule Thunderline.Thunderbolt.Thunderbit do
  @moduledoc """
  Single voxel cell in the 3D CA lattice.

  Combines:
  - Classical CA state
  - CAT transform coefficients
  - Routing/presence metadata
  - Security key fragments

  The Thunderbit is both a **compute cell** (evolving a CA) and a
  **transform cell** (encoding evolution as orthogonal CAT coefficients).

  ## Local Decision Rules

  Each voxel makes small local decisions:
  - "I'm stable enough to relay" (σ_flow > threshold)
  - "I have enough trust to bridge two users" (trust_score > threshold)
  - "I can maintain ϕ-coherence for a WebRTC handshake" (PLV in band)
  - "I should collapse this path due to high λ̂" (chaos detection)
  - "I'm under attack → collapse presence field" (security response)

  ## Reference

  See `docs/HC_ARCHITECTURE_SYNTHESIS.md` for the full specification.
  """

  @enforce_keys [:id, :coord]
  defstruct [
    # ─────────────────────────────────────────────────────────────
    # Identity
    # ─────────────────────────────────────────────────────────────
    :id,
    :coord,

    # ─────────────────────────────────────────────────────────────
    # CA State (v2: Ternary)
    # ─────────────────────────────────────────────────────────────
    # Ternary state: :neg | :zero | :pos (v2)
    ternary_state: :zero,
    # Legacy binary/integer state (v1 compat)
    state: 0,
    # Multi-channel state vector for NCA (v2)
    state_vector: [],
    rule_id: :demo,
    # Rule version: 1 = classic, 2 = ternary/reversible
    rule_version: 1,
    neighborhood: [],

    # ─────────────────────────────────────────────────────────────
    # Dynamics Metrics (for LoopMonitor / Criticality)
    # ─────────────────────────────────────────────────────────────
    # Phase for PLV (Phase-Locking Value) synchrony measurement
    phi_phase: 0.0,
    # Propagatability / connectivity metric (σ_flow)
    sigma_flow: 1.0,
    # Local FTLE (Finite-Time Lyapunov Exponent) - chaos/stability indicator (λ̂)
    lambda_sensitivity: 0.0,

    # ─────────────────────────────────────────────────────────────
    # Ising Physics (v2: HC-87)
    # ─────────────────────────────────────────────────────────────
    # External field / policy pressure
    bias: 0.0,
    # Local energy coupling coefficient
    coupling: 1.0,
    # Noise/randomness parameter (Boltzmann T)
    temperature: 0.1,

    # ─────────────────────────────────────────────────────────────
    # MIRAS Memory (v2: HC-90, HC-91)
    # ─────────────────────────────────────────────────────────────
    # Current |predicted - observed| gradient magnitude
    surprise_metric: 0.0,
    # Memory decay control [0, 1]
    retention_gate: 1.0,
    # β-EMA smoothed surprise
    momentum_surprise: 0.0,
    # Previous ternary state (for second-order reversibility)
    previous_state: :zero,

    # ─────────────────────────────────────────────────────────────
    # Routing & Trust
    # ─────────────────────────────────────────────────────────────
    # Trust level for routing decisions
    trust_score: 0.5,
    # PAC presence fields - each user/PAC emits a presence wave
    presence_vector: %{},
    # Load balancing weight
    relay_weight: 1.0,
    # Bloom filter of destination IDs for routing
    route_tags: nil,

    # ─────────────────────────────────────────────────────────────
    # Channel & Security
    # ─────────────────────────────────────────────────────────────
    # Active channel UUID (nil if idle)
    channel_id: nil,
    # Thundergate session key reference
    key_id: nil,
    # Crypto key shard for distributed key exchange
    key_fragment: nil,

    # ─────────────────────────────────────────────────────────────
    # CAT Transform (Cellular Automata Transform)
    # ─────────────────────────────────────────────────────────────
    # CAT configuration: rule_id, dims, window_shape, time_depth, etc.
    cat_config: nil,
    # Latest transform coefficients (binary/Nx tensor)
    cat_coefficients: nil,

    # ─────────────────────────────────────────────────────────────
    # Doctrine Layer (Operation TIGER LATTICE)
    # ─────────────────────────────────────────────────────────────
    # Behavioral doctrine (algotype): router, healer, compressor, explorer, guardian, general
    doctrine: :general,
    # Hidden channels for inter-bit communication (NCA-style)
    # %{v: [float()], dim: non_neg_integer()}
    hidden_state: %{v: [], dim: 0},

    # ─────────────────────────────────────────────────────────────
    # Timestamps
    # ─────────────────────────────────────────────────────────────
    # Last CA tick that updated this bit
    last_tick: 0,
    created_at: nil,
    updated_at: nil
  ]

  @type coord :: {integer(), integer(), integer()}
  @type bloom_filter :: binary() | nil
  @type ternary :: :neg | :zero | :pos

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | String.t(),
          coord: coord(),
          # v2 ternary state
          ternary_state: ternary(),
          state: term(),
          state_vector: [float()],
          rule_id: atom() | integer(),
          rule_version: 1 | 2,
          neighborhood: [coord()],
          # Physics
          phi_phase: float(),
          sigma_flow: float(),
          lambda_sensitivity: float(),
          # v2 Ising
          bias: float(),
          coupling: float(),
          temperature: float(),
          # v2 MIRAS
          surprise_metric: float(),
          retention_gate: float(),
          momentum_surprise: float(),
          previous_state: ternary(),
          # Routing & Trust
          trust_score: float(),
          presence_vector: map(),
          relay_weight: float(),
          route_tags: bloom_filter(),
          channel_id: Ecto.UUID.t() | nil,
          key_id: String.t() | nil,
          key_fragment: binary() | nil,
          cat_config: map() | nil,
          cat_coefficients: binary() | nil,
          last_tick: non_neg_integer(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  # ═══════════════════════════════════════════════════════════════
  # Construction
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Creates a new Thunderbit at the given 3D coordinate.

  ## Options

  - `:id` - UUID or string ID (default: auto-generated UUID)
  - `:state` - Initial CA state (default: 0)
  - `:rule_id` - CA rule identifier (default: :demo)
  - `:trust_score` - Initial trust level (default: 0.5)
  - All other struct fields can be passed as options

  ## Examples

      iex> Thunderbit.new({0, 0, 0})
      %Thunderbit{id: "...", coord: {0, 0, 0}, ...}

      iex> Thunderbit.new({1, 2, 3}, state: 1, trust_score: 0.9)
      %Thunderbit{coord: {1, 2, 3}, state: 1, trust_score: 0.9, ...}
  """
  @spec new(coord(), keyword()) :: t()
  def new(coord, opts \\ []) do
    now = DateTime.utc_now()
    id = Keyword.get_lazy(opts, :id, fn -> Ecto.UUID.generate() end)

    defaults = [
      id: id,
      coord: coord,
      created_at: now,
      updated_at: now
    ]

    struct!(__MODULE__, Keyword.merge(defaults, opts))
  end

  @doc """
  Creates a new Thunderbit with computed neighborhood from grid bounds.

  The neighborhood is computed based on the `neighborhood_type`:
  - `:von_neumann` - 6-connected (face neighbors)
  - `:moore` - 26-connected (all adjacent cells)
  - `{:moore, radius}` - Extended Moore neighborhood

  ## Examples

      iex> Thunderbit.new_with_neighborhood({5, 5, 5}, {10, 10, 10}, :von_neumann)
      %Thunderbit{coord: {5, 5, 5}, neighborhood: [{4,5,5}, {6,5,5}, ...]}
  """
  @spec new_with_neighborhood(coord(), coord(), atom() | {atom(), integer()}, keyword()) :: t()
  def new_with_neighborhood(coord, grid_bounds, neighborhood_type, opts \\ []) do
    neighbors =
      Thunderline.Thunderbolt.CA.Neighborhood.compute(
        coord,
        grid_bounds,
        neighborhood_type
      )

    new(coord, Keyword.put(opts, :neighborhood, neighbors))
  end

  # ═══════════════════════════════════════════════════════════════
  # Local Decision Predicates
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns true if this Thunderbit is stable enough to relay messages.

  A bit is relay-capable when its flow metric (σ_flow) exceeds the threshold.
  """
  @spec can_relay?(t(), float()) :: boolean()
  def can_relay?(%__MODULE__{sigma_flow: flow}, threshold \\ 0.5) do
    flow > threshold
  end

  @doc """
  Returns true if this Thunderbit has sufficient trust to bridge two parties.
  """
  @spec can_bridge?(t(), float()) :: boolean()
  def can_bridge?(%__MODULE__{trust_score: trust}, threshold \\ 0.3) do
    trust > threshold
  end

  @doc """
  Returns true if this Thunderbit can maintain phase coherence for handshakes.

  Phase-Locking Value (PLV) must be within acceptable band.
  """
  @spec phase_coherent?(t(), {float(), float()}) :: boolean()
  def phase_coherent?(%__MODULE__{phi_phase: phase}, {low, high} \\ {0.0, 2 * :math.pi()}) do
    phase >= low and phase <= high
  end

  @doc """
  Returns true if chaos indicator suggests path collapse is needed.

  High λ̂_sensitivity indicates chaotic dynamics that should trigger path teardown.
  """
  @spec chaotic?(t(), float()) :: boolean()
  def chaotic?(%__MODULE__{lambda_sensitivity: lambda}, threshold \\ 0.8) do
    lambda > threshold
  end

  @doc """
  Returns true if this Thunderbit is currently idle (no active channel).
  """
  @spec idle?(t()) :: boolean()
  def idle?(%__MODULE__{channel_id: nil}), do: true
  def idle?(_), do: false

  @doc """
  Returns true if this Thunderbit has presence from the given PAC ID.
  """
  @spec has_presence?(t(), String.t()) :: boolean()
  def has_presence?(%__MODULE__{presence_vector: pv}, pac_id) do
    Map.has_key?(pv, pac_id)
  end

  # ═══════════════════════════════════════════════════════════════
  # State Updates
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Updates the CA state and metrics after a CA step.

  ## Options

  - `:state` - New CA state
  - `:phi_phase` - Updated phase value
  - `:sigma_flow` - Updated flow metric
  - `:lambda_sensitivity` - Updated chaos indicator
  - `:tick` - Current tick number
  """
  @spec update_state(t(), keyword()) :: t()
  def update_state(%__MODULE__{} = bit, opts) do
    now = DateTime.utc_now()
    tick = Keyword.get(opts, :tick, bit.last_tick + 1)

    updates =
      opts
      |> Keyword.take([:state, :phi_phase, :sigma_flow, :lambda_sensitivity])
      |> Keyword.put(:last_tick, tick)
      |> Keyword.put(:updated_at, now)

    struct!(bit, updates)
  end

  @doc """
  Adds or updates presence for a PAC in this Thunderbit.

  The presence value can be a strength float (0.0-1.0) or a map with metadata.
  """
  @spec add_presence(t(), String.t(), float() | map()) :: t()
  def add_presence(%__MODULE__{presence_vector: pv} = bit, pac_id, presence) do
    new_pv = Map.put(pv, pac_id, presence)
    %{bit | presence_vector: new_pv, updated_at: DateTime.utc_now()}
  end

  @doc """
  Removes presence for a PAC from this Thunderbit.
  """
  @spec remove_presence(t(), String.t()) :: t()
  def remove_presence(%__MODULE__{presence_vector: pv} = bit, pac_id) do
    new_pv = Map.delete(pv, pac_id)
    %{bit | presence_vector: new_pv, updated_at: DateTime.utc_now()}
  end

  @doc """
  Decays all presence values by the given factor.

  Used by Thunderwall for entropy management.
  """
  @spec decay_presence(t(), float()) :: t()
  def decay_presence(%__MODULE__{presence_vector: pv} = bit, decay_factor)
      when is_float(decay_factor) and decay_factor >= 0.0 and decay_factor <= 1.0 do
    decayed =
      pv
      |> Enum.map(fn
        {k, v} when is_float(v) -> {k, v * decay_factor}
        {k, %{strength: s} = v} -> {k, %{v | strength: s * decay_factor}}
        other -> other
      end)
      |> Enum.reject(fn
        {_k, v} when is_float(v) -> v < 0.01
        {_k, %{strength: s}} -> s < 0.01
        _ -> false
      end)
      |> Map.new()

    %{bit | presence_vector: decayed, updated_at: DateTime.utc_now()}
  end

  @doc """
  Assigns this Thunderbit to a channel.
  """
  @spec assign_channel(t(), Ecto.UUID.t(), String.t() | nil) :: t()
  def assign_channel(%__MODULE__{} = bit, channel_id, key_id \\ nil) do
    %{bit | channel_id: channel_id, key_id: key_id, updated_at: DateTime.utc_now()}
  end

  @doc """
  Releases this Thunderbit from its current channel.
  """
  @spec release_channel(t()) :: t()
  def release_channel(%__MODULE__{} = bit) do
    %{bit | channel_id: nil, key_id: nil, updated_at: DateTime.utc_now()}
  end

  @doc """
  Updates the trust score, clamped to [0.0, 1.0].
  """
  @spec update_trust(t(), float()) :: t()
  def update_trust(%__MODULE__{} = bit, delta) when is_float(delta) do
    new_trust = max(0.0, min(1.0, bit.trust_score + delta))
    %{bit | trust_score: new_trust, updated_at: DateTime.utc_now()}
  end

  # ═══════════════════════════════════════════════════════════════
  # Serialization
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Converts a Thunderbit to a minimal delta map for PubSub transmission.

  Includes only fields that have changed or are essential for visualization.
  """
  @spec to_delta(t()) :: map()
  def to_delta(%__MODULE__{} = bit) do
    {x, y, z} = bit.coord

    %{
      id: bit.id,
      coord: bit.coord,
      x: x,
      y: y,
      z: z,
      state: bit.state,
      energy: energy_from_metrics(bit),
      hex: state_color(bit),
      trust: bit.trust_score,
      flow: bit.sigma_flow,
      phase: bit.phi_phase,
      lambda: bit.lambda_sensitivity,
      channel: bit.channel_id,
      tick: bit.last_tick,
      # Doctrine Layer fields
      doctrine: bit.doctrine,
      hidden_state: bit.hidden_state
    }
  end

  # Energy is derived from dynamics metrics for visualization
  defp energy_from_metrics(%__MODULE__{sigma_flow: flow, trust_score: trust}) do
    # Normalize to 0-100 for backward compatibility
    round((flow * 0.5 + trust * 0.5) * 100)
  end

  # Color based on dynamics state for visualization
  defp state_color(%__MODULE__{lambda_sensitivity: lambda}) when lambda > 0.8, do: 0xFF0000
  defp state_color(%__MODULE__{sigma_flow: flow}) when flow > 0.7, do: 0x00FF00
  defp state_color(%__MODULE__{sigma_flow: flow}) when flow > 0.3, do: 0xFFFF00
  defp state_color(_), do: 0x333333

  # ═══════════════════════════════════════════════════════════════
  # v2 Ternary State Operations (HC-86/HC-87)
  # ═══════════════════════════════════════════════════════════════

  alias Thunderline.Thunderbolt.TernaryState

  @doc """
  Performs a ternary CA tick using reversible rules.

  Updates ternary_state based on neighbor states, stores previous_state for
  reversibility, and updates Ising physics parameters.

  ## Options

  - `:neighbors` - List of neighbor Thunderbits (required)
  - `:rule` - Rule atom (:feynman, :toffoli, :fredkin, :majority) (default: :majority)
  - `:tick` - Current tick number
  """
  @spec ternary_tick(t(), keyword()) :: t()
  def ternary_tick(%__MODULE__{ternary_state: current} = bit, opts) do
    neighbors = Keyword.fetch!(opts, :neighbors)
    rule = Keyword.get(opts, :rule, :majority)
    tick = Keyword.get(opts, :tick, bit.last_tick + 1)

    # Extract neighbor ternary states
    neighbor_states = Enum.map(neighbors, & &1.ternary_state)

    # Compute new state based on rule
    new_state =
      case rule do
        :majority ->
          TernaryState.majority(neighbor_states)

        :feynman when length(neighbor_states) >= 1 ->
          # Feynman gate: control + target mod 3
          TernaryState.feynman(current, hd(neighbor_states))

        :toffoli when length(neighbor_states) >= 2 ->
          # Toffoli gate: returns {c1, c2, new_target} - we want new_target
          [c1, c2 | _] = neighbor_states
          {_c1, _c2, new_target} = TernaryState.toffoli(c1, c2, current)
          new_target

        :weighted_vote ->
          # Use neighbor trust scores as weights
          weights = Enum.map(neighbors, fn n -> {n.ternary_state, n.trust_score} end)
          TernaryState.weighted_vote(weights)

        _ ->
          TernaryState.majority(neighbor_states)
      end

    # Compute local Ising energy
    new_energy = compute_ising_energy(bit, neighbor_states)

    %{bit |
      previous_state: current,
      ternary_state: new_state,
      sigma_flow: new_energy,
      last_tick: tick,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Updates MIRAS memory parameters based on surprise from state change.

  The surprise metric measures how unexpected the state transition was.
  Uses exponential moving average for momentum smoothing.

  ## Options

  - `:beta` - Momentum smoothing factor (default: 0.9)
  - `:alpha` - Learning rate for retention gate (default: 0.1)
  """
  @spec update_miras(t(), keyword()) :: t()
  def update_miras(%__MODULE__{} = bit, opts \\ []) do
    beta = Keyword.get(opts, :beta, 0.9)
    alpha = Keyword.get(opts, :alpha, 0.1)

    # Compute surprise as state change magnitude
    surprise = compute_surprise(bit.previous_state, bit.ternary_state)

    # Update momentum with EMA
    new_momentum = beta * bit.momentum_surprise + (1.0 - beta) * surprise

    # Update retention gate based on surprise (high surprise = more retention)
    new_retention = bit.retention_gate + alpha * (surprise - bit.retention_gate)
    new_retention = max(0.0, min(1.0, new_retention))

    %{bit |
      surprise_metric: surprise,
      momentum_surprise: new_momentum,
      retention_gate: new_retention,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Converts legacy state to ternary state based on threshold.

  Used for v1 → v2 migration. Maps arbitrary state values to ternary.
  """
  @spec to_ternary(t(), keyword()) :: t()
  def to_ternary(%__MODULE__{state: state} = bit, opts \\ []) do
    neg_threshold = Keyword.get(opts, :neg_threshold, -0.33)
    pos_threshold = Keyword.get(opts, :pos_threshold, 0.33)

    ternary =
      cond do
        is_number(state) and state < neg_threshold -> :neg
        is_number(state) and state > pos_threshold -> :pos
        state == 0 or state == :zero -> :zero
        state == 1 or state == :pos or state == true -> :pos
        state == -1 or state == :neg or state == false -> :neg
        true -> :zero
      end

    %{bit | ternary_state: ternary, rule_version: 2, updated_at: DateTime.utc_now()}
  end

  @doc """
  Returns true if this Thunderbit is using v2 ternary rules.
  """
  @spec v2?(t()) :: boolean()
  def v2?(%__MODULE__{rule_version: 2}), do: true
  def v2?(_), do: false

  @doc """
  Returns true if the Thunderbit is in a "frozen" state (high retention, low surprise).
  """
  @spec frozen?(t(), float()) :: boolean()
  def frozen?(%__MODULE__{retention_gate: r, momentum_surprise: m}, threshold \\ 0.1) do
    r > 0.9 and m < threshold
  end

  @doc """
  Returns true if the Thunderbit is "excited" (high surprise, state change expected).
  """
  @spec excited?(t(), float()) :: boolean()
  def excited?(%__MODULE__{momentum_surprise: m}, threshold \\ 0.7) do
    m > threshold
  end

  @doc """
  Computes the one-hot vector representation for ML integration.
  """
  @spec to_one_hot(t()) :: [float()]
  def to_one_hot(%__MODULE__{ternary_state: state}) do
    TernaryState.to_one_hot(state)
  end

  @doc """
  Updates ternary state from one-hot vector (argmax selection).
  """
  @spec from_one_hot(t(), [float()]) :: t()
  def from_one_hot(%__MODULE__{} = bit, one_hot) do
    new_state = TernaryState.from_one_hot(one_hot)
    %{bit | previous_state: bit.ternary_state, ternary_state: new_state, updated_at: DateTime.utc_now()}
  end

  # ═══════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════

  defp compute_ising_energy(%__MODULE__{ternary_state: s, bias: h, coupling: j}, neighbor_states) do
    TernaryState.ising_energy(s, neighbor_states, coupling: j, bias: h)
  end

  defp compute_surprise(old_state, new_state) when old_state == new_state, do: 0.0
  defp compute_surprise(:zero, _), do: 0.5
  defp compute_surprise(_, :zero), do: 0.5
  defp compute_surprise(:neg, :pos), do: 1.0
  defp compute_surprise(:pos, :neg), do: 1.0
  defp compute_surprise(_, _), do: 0.3
end
