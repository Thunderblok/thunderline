defmodule Thunderline.Thunderblock.Health do
  @moduledoc """
  Centralized Repo-level health checks confined to the Thunderblock domain.

  Provides helpers for other domains to verify database connectivity without
  instantiating direct Repo calls.
  """

  @spec ping() :: :ok | {:error, term()}
  def ping do
    case Thunderline.Repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec now() :: {:ok, NaiveDateTime.t()} | {:error, term()}
  def now do
    case Thunderline.Repo.query("SELECT now()", []) do
      {:ok, %{rows: [[timestamp]]}} -> {:ok, timestamp}
      {:error, reason} -> {:error, reason}
    end
  end
end
