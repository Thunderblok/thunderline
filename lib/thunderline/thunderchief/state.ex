defmodule Thunderline.Thunderchief.State do
  @moduledoc """
  Chief observation state container.

  Provides a standardized structure for domain observations
  that chiefs use for action selection. Includes common fields
  across all domains plus extensible domain-specific data.

  ## Structure

  - `domain` - Which domain this state represents
  - `tick` - Current Thunderbeat tick number
  - `timestamp` - When observation was captured
  - `features` - Compressed feature vector for ML
  - `context` - Full domain context (for debugging/logging)
  - `metadata` - Additional tracking data

  ## Usage

  ```elixir
  state = State.new(:bit, %{
    pending_count: 5,
    energy_level: 0.8,
    active_category: :cognitive
  })

  # Convert to feature vector for policy
  features = State.to_features(state)
  ```
  """

  alias __MODULE__

  @type domain :: :bit | :vine | :crown | :ui | :link | :wall | atom()

  @type t :: %State{
          domain: domain(),
          tick: non_neg_integer(),
          timestamp: DateTime.t(),
          features: map(),
          context: map(),
          metadata: map()
        }

  defstruct [
    :domain,
    :tick,
    :timestamp,
    features: %{},
    context: %{},
    metadata: %{}
  ]

  @doc """
  Create a new state observation.

  ## Parameters

  - `domain` - Domain identifier atom
  - `features` - Map of observable features
  - `opts` - Additional options:
    - `:tick` - Current tick number (default: 0)
    - `:context` - Full domain context for debugging
    - `:metadata` - Additional tracking info

  ## Examples

      iex> State.new(:bit, %{pending: 5, energy: 0.8})
      %State{domain: :bit, features: %{pending: 5, energy: 0.8}, ...}
  """
  @spec new(domain(), map(), keyword()) :: t()
  def new(domain, features, opts \\ []) do
    %State{
      domain: domain,
      tick: Keyword.get(opts, :tick, 0),
      timestamp: DateTime.utc_now(),
      features: features,
      context: Keyword.get(opts, :context, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create state from domain context using observer function.

  Applies the observer to extract features from full context.

  ## Parameters

  - `domain` - Domain identifier
  - `context` - Full domain execution context
  - `observer` - Function that extracts features from context

  ## Examples

      iex> observer = fn ctx -> %{count: length(ctx.items)} end
      iex> State.from_context(:vine, %{items: [1,2,3]}, observer)
      %State{domain: :vine, features: %{count: 3}, ...}
  """
  @spec from_context(domain(), map(), (map() -> map())) :: t()
  def from_context(domain, context, observer) do
    features = observer.(context)

    %State{
      domain: domain,
      tick: Map.get(context, :tick, 0),
      timestamp: DateTime.utc_now(),
      features: features,
      context: context,
      metadata: %{
        observed_at: System.monotonic_time(:millisecond)
      }
    }
  end

  @doc """
  Convert state to flat feature vector for ML.

  Flattens nested maps and converts values to floats
  where possible for neural network input.

  ## Parameters

  - `state` - State struct to convert

  ## Returns

  List of {key, float_value} tuples suitable for Nx tensors.
  """
  @spec to_features(t()) :: [{atom(), float()}]
  def to_features(%State{features: features}) do
    features
    |> flatten_map([])
    |> Enum.map(fn {k, v} -> {k, to_float(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc """
  Convert state to tensor-ready format.

  Returns a map with feature names and values as separate lists
  for Nx tensor construction.
  """
  @spec to_tensor_input(t()) :: %{names: [atom()], values: [float()]}
  def to_tensor_input(%State{} = state) do
    pairs = to_features(state)
    %{
      names: Enum.map(pairs, &elem(&1, 0)),
      values: Enum.map(pairs, &elem(&1, 1))
    }
  end

  @doc """
  Update state with new features.
  """
  @spec update_features(t(), map()) :: t()
  def update_features(%State{} = state, new_features) do
    %{state | features: Map.merge(state.features, new_features)}
  end

  @doc """
  Add metadata to state.
  """
  @spec add_metadata(t(), map()) :: t()
  def add_metadata(%State{} = state, metadata) do
    %{state | metadata: Map.merge(state.metadata, metadata)}
  end

  @doc """
  Check if state indicates high priority situation.

  Domain-specific thresholds can be configured.
  """
  @spec high_priority?(t(), keyword()) :: boolean()
  def high_priority?(%State{features: features}, opts \\ []) do
    energy_threshold = Keyword.get(opts, :energy_threshold, 0.2)
    queue_threshold = Keyword.get(opts, :queue_threshold, 100)

    cond do
      Map.get(features, :energy_level, 1.0) < energy_threshold -> true
      Map.get(features, :pending_count, 0) > queue_threshold -> true
      Map.get(features, :error_rate, 0.0) > 0.5 -> true
      true -> false
    end
  end

  @doc """
  Calculate age of state in milliseconds.
  """
  @spec age_ms(t()) :: non_neg_integer()
  def age_ms(%State{timestamp: ts}) do
    DateTime.diff(DateTime.utc_now(), ts, :millisecond)
  end

  @doc """
  Check if state is stale (older than threshold).
  """
  @spec stale?(t(), non_neg_integer()) :: boolean()
  def stale?(%State{} = state, max_age_ms \\ 5000) do
    age_ms(state) > max_age_ms
  end

  # Private helpers

  defp flatten_map(map, prefix) when is_map(map) do
    Enum.flat_map(map, fn {k, v} ->
      key = if prefix == [], do: k, else: :"#{Enum.join(prefix, "_")}_#{k}"
      
      if is_map(v) and not is_struct(v) do
        flatten_map(v, prefix ++ [k])
      else
        [{key, v}]
      end
    end)
  end

  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_float(v), do: v
  defp to_float(true), do: 1.0
  defp to_float(false), do: 0.0
  defp to_float(nil), do: 0.0
  defp to_float(v) when is_atom(v), do: :erlang.phash2(v) / 4_294_967_295
  defp to_float(_), do: 0.0
end
