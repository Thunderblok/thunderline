defmodule Thunderline.Const do
  @moduledoc """
  Ring 0 constants gate.

  Centralized, audited access to read‑mostly global constants. Backed by
  `:persistent_term` for zero‑copy fanout reads. Only a *curated* key set is
  allowed (documented in ADR-001). All writes emit telemetry so we can graph
  swap frequency & payload sizes.

  Telemetry events:
    * [:thunderline, :const, :put_once]
    * [:thunderline, :const, :swap]

  Measurements: %{size_bytes: integer}
  Metadata: %{key: term, reason: binary | nil, who: pid | nil, version: term | nil}

  Usage tiers:
    * put_once/3  – boot‑time initialization, raises if key already set
    * swap!/3     – rare, audited version bump (e.g. new CA rule set)
    * fetch/1     – raises if missing (hot path should rely on invariants)
    * get/1       – tolerant, returns :error if unset
  """

  @missing :__thunderline_const_missing__
  @type key :: term()

  @doc "Fetch a constant or raise if missing."
  @spec fetch(key) :: term()
  def fetch(key) do
    case :persistent_term.get(key, @missing) do
      @missing -> raise ArgumentError, "Const not set: #{inspect(key)}"
      value -> value
    end
  end

  @doc "Return {:ok, value} | :error without raising."
  @spec get(key) :: {:ok, term()} | :error
  def get(key) do
    case :persistent_term.get(key, @missing) do
      @missing -> :error
      value -> {:ok, value}
    end
  end

  @doc "Idempotent write: succeed only if key is unset. Emits telemetry."
  @spec put_once(key, term(), keyword()) :: :ok
  def put_once(key, value, meta \\ []) do
    if :persistent_term.get(key, @missing) != @missing do
      raise "Attempt to overwrite existing const #{inspect(key)}"
    end
    :persistent_term.put(key, value)
    emit(:put_once, key, value, meta)
    :ok
  end

  @doc "Swap (or set) a constant with audit metadata. Use sparingly."
  @spec swap!(key, term(), keyword()) :: :ok
  def swap!(key, value, meta \\ []) do
    :persistent_term.put(key, value)
    emit(:swap, key, value, meta)
    :ok
  end

  defp emit(action, key, value, meta) do
    :telemetry.execute([
      :thunderline, :const, action
    ], %{size_bytes: :erlang.external_size(value)}, Map.new(meta) |> Map.put(:key, key))
  end
end
