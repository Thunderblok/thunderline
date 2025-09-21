defmodule Thunderline.Thunderflow.Support.Idempotency do
  @moduledoc """
  Simple ETS-backed idempotency key store keyed by {event.id, name, version}.
  """
  @table __MODULE__
  def start_link do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, @table}
  rescue
    ArgumentError -> {:ok, @table}
  end

  def seen?(key), do: :ets.member(@table, key)
  def mark!(key), do: :ets.insert(@table, {key, true})
end
