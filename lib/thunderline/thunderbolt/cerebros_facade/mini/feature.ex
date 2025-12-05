defmodule Thunderline.Thunderbolt.CerebrosFacade.Mini.Feature do
  @moduledoc """
  Minimal feature extraction for Cerebros-mini scoring.

  Extracts a compact feature vector from Thunderbits for the lightweight
  scoring model. This is intentionally simpler than the full Features module
  used for TPE optimization.

  ## Feature Vector Structure

  The feature vector is a flat list of numerics suitable for inference:

      [bit_id_hash, pac_id_hash, zone_idx, category_idx, energy, age_ticks,
       health, salience, chain_depth, role_idx, status_idx, link_count]

  ## Usage

      # From a Thunderbit map
      {:ok, feature} = Feature.from_bit(thunderbit)

      # Get raw vector for inference
      vector = Feature.to_vector(feature)
      # => [123, 456, 0, 1, 0.85, 42, 1.0, 0.75, 2, 3, 1, 5]

  ## Architecture Note

  This module implements the "from_bit/1" portion of the Cerebros-mini MVP:

      Thunderbit → from_bit/1 → Feature → infer/1 → Result → apply_result/3 → Mutation

  See `Thunderline.Thunderbolt.CerebrosFacade.Mini.Scorer` for inference and
  `Thunderline.Thunderbolt.CerebrosFacade.Mini.Bridge` for the full pipeline.
  """

  @type t :: %__MODULE__{
          bit_id: String.t(),
          pac_id: String.t() | nil,
          zone_id: String.t() | nil,
          category: atom(),
          category_idx: non_neg_integer(),
          role: atom(),
          role_idx: non_neg_integer(),
          status: atom(),
          status_idx: non_neg_integer(),
          energy: float(),
          salience: float(),
          health: float(),
          age_ticks: non_neg_integer(),
          chain_depth: non_neg_integer(),
          link_count: non_neg_integer(),
          extracted_at: DateTime.t()
        }

  defstruct [
    :bit_id,
    :pac_id,
    :zone_id,
    :category,
    :category_idx,
    :role,
    :role_idx,
    :status,
    :status_idx,
    :energy,
    :salience,
    :health,
    :age_ticks,
    :chain_depth,
    :link_count,
    :extracted_at
  ]

  # Category index mapping (order matters for consistency)
  @category_indices %{
    sensory: 0,
    cognitive: 1,
    motor: 2,
    mnemonic: 3,
    social: 4,
    ethical: 5,
    perceptual: 6,
    executive: 7,
    governance: 8,
    meta: 9
  }

  # Role index mapping
  @role_indices %{
    observer: 0,
    transformer: 1,
    router: 2,
    actuator: 3,
    critic: 4,
    analyzer: 5,
    storage: 6,
    controller: 7
  }

  # Status index mapping
  @status_indices %{
    pending: 0,
    active: 1,
    spawning: 2,
    fading: 3,
    archived: 4,
    retired: 5
  }

  @doc """
  Extracts features from a Thunderbit map.

  Accepts either a Protocol Thunderbit (from spawn_bit) or a CA Thunderbit.
  Returns a structured feature set suitable for scoring.

  ## Parameters

  - `bit` - A Thunderbit map with at minimum `:id` and `:category`

  ## Returns

  - `{:ok, %Feature{}}` on success
  - `{:error, reason}` if required fields are missing

  ## Example

      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "hello"}, ctx)
      {:ok, feature} = Feature.from_bit(bit)
  """
  @spec from_bit(map()) :: {:ok, t()} | {:error, term()}
  def from_bit(%{id: id, category: category} = bit) do
    now = DateTime.utc_now()

    # Extract category info
    cat_atom = normalize_category(category)
    cat_idx = Map.get(@category_indices, cat_atom, 0)

    # Extract role
    role = Map.get(bit, :role, :transformer)
    role_idx = Map.get(@role_indices, role, 1)

    # Extract status
    status = Map.get(bit, :status, :active)
    status_idx = Map.get(@status_indices, status, 1)

    # Calculate age in ticks (approximate from inserted_at if available)
    age_ticks = calculate_age_ticks(bit, now)

    # Extract numeric features with defaults
    energy = normalize_float(Map.get(bit, :energy, 0.5))
    salience = normalize_float(Map.get(bit, :salience, 0.5))
    health = calculate_health(bit)
    chain_depth = Map.get(bit, :chain_depth, 0)
    link_count = calculate_link_count(bit)

    feature = %__MODULE__{
      bit_id: to_string(id),
      pac_id: get_pac_id(bit),
      zone_id: get_zone_id(bit),
      category: cat_atom,
      category_idx: cat_idx,
      role: role,
      role_idx: role_idx,
      status: status,
      status_idx: status_idx,
      energy: energy,
      salience: salience,
      health: health,
      age_ticks: age_ticks,
      chain_depth: chain_depth,
      link_count: link_count,
      extracted_at: now
    }

    {:ok, feature}
  end

  def from_bit(%{} = bit) do
    # Try to handle CA Thunderbit (has :coord instead of :category sometimes)
    cond do
      Map.has_key?(bit, :id) ->
        # Add default category if missing
        bit_with_category = Map.put_new(bit, :category, :sensory)
        from_bit(bit_with_category)

      true ->
        {:error, :missing_required_fields}
    end
  end

  def from_bit(_), do: {:error, :invalid_bit}

  @doc """
  Converts a Feature struct to a flat numeric vector for inference.

  The vector format is:

      [bit_hash, pac_hash, zone_idx, cat_idx, energy, age_ticks,
       health, salience, chain_depth, role_idx, status_idx, link_count]

  All values are normalized to be inference-friendly (floats 0-1 or integers).

  ## Parameters

  - `feature` - A Feature struct

  ## Returns

  A list of 12 numeric values.
  """
  @spec to_vector(t()) :: [number()]
  def to_vector(%__MODULE__{} = f) do
    [
      hash_to_int(f.bit_id),
      hash_to_int(f.pac_id),
      zone_to_idx(f.zone_id),
      f.category_idx,
      f.energy,
      # Normalize age
      min(f.age_ticks, 10000) / 10000.0,
      f.health,
      f.salience,
      # Normalize chain depth
      min(f.chain_depth, 10) / 10.0,
      # Normalize role
      f.role_idx / 7.0,
      # Normalize status
      f.status_idx / 5.0,
      # Normalize link count
      min(f.link_count, 20) / 20.0
    ]
  end

  @doc """
  Converts a Feature struct to a map suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = f) do
    %{
      bit_id: f.bit_id,
      pac_id: f.pac_id,
      zone_id: f.zone_id,
      category: Atom.to_string(f.category),
      role: Atom.to_string(f.role),
      status: Atom.to_string(f.status),
      energy: f.energy,
      salience: f.salience,
      health: f.health,
      age_ticks: f.age_ticks,
      chain_depth: f.chain_depth,
      link_count: f.link_count,
      extracted_at: DateTime.to_iso8601(f.extracted_at)
    }
  end

  @doc """
  Returns the dimension count of the feature vector.
  """
  @spec dimension() :: non_neg_integer()
  def dimension, do: 12

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp normalize_category(cat) when is_atom(cat), do: cat

  defp normalize_category(cat) when is_binary(cat) do
    String.to_existing_atom(cat)
  rescue
    ArgumentError -> :sensory
  end

  defp normalize_category(_), do: :sensory

  defp normalize_float(val) when is_float(val), do: max(0.0, min(1.0, val))
  defp normalize_float(val) when is_integer(val), do: normalize_float(val / 1.0)
  defp normalize_float(_), do: 0.5

  defp calculate_age_ticks(bit, now) do
    cond do
      Map.has_key?(bit, :age_ticks) ->
        bit.age_ticks

      Map.has_key?(bit, :inserted_at) && bit.inserted_at ->
        # Approximate: 1 tick = 1 second
        DateTime.diff(now, bit.inserted_at, :second)

      Map.has_key?(bit, :created_at) && bit.created_at ->
        DateTime.diff(now, bit.created_at, :second)

      true ->
        0
    end
  end

  defp calculate_health(bit) do
    # Health composite: energy + trust - decay
    energy = normalize_float(Map.get(bit, :energy, 0.5))
    trust = normalize_float(Map.get(bit, :trust_score, 0.5))
    decay = normalize_float(Map.get(bit, :decay_rate, 0.0))

    max(0.0, min(1.0, (energy + trust) / 2.0 - decay * 0.1))
  end

  defp calculate_link_count(bit) do
    links = Map.get(bit, :links, [])
    io_outputs = get_in(bit, [:io_state, :outputs]) || %{}

    length(links) + map_size(io_outputs)
  end

  defp get_pac_id(bit) do
    cond do
      Map.has_key?(bit, :owner) ->
        to_string(bit.owner)

      Map.has_key?(bit, :pac_id) ->
        to_string(bit.pac_id)

      metadata = Map.get(bit, :metadata, %{}) ->
        to_string(Map.get(metadata, :pac_id) || Map.get(metadata, :owner))

      true ->
        nil
    end
  end

  defp get_zone_id(bit) do
    cond do
      Map.has_key?(bit, :zone) ->
        to_string(bit.zone)

      metadata = Map.get(bit, :metadata, %{}) ->
        zone = Map.get(metadata, :zone)
        if zone, do: to_string(zone), else: nil

      true ->
        nil
    end
  end

  defp hash_to_int(nil), do: 0

  defp hash_to_int(str) when is_binary(str) do
    # Simple hash to bounded integer for embedding
    :erlang.phash2(str, 1_000_000) / 1_000_000.0
  end

  defp hash_to_int(_), do: 0

  defp zone_to_idx(nil), do: 0.0
  defp zone_to_idx("local"), do: 0.1
  defp zone_to_idx("global"), do: 0.2
  defp zone_to_idx("agent"), do: 0.3
  defp zone_to_idx(zone) when is_binary(zone), do: hash_to_int(zone)
  defp zone_to_idx(_), do: 0.0
end
