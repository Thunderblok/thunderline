defmodule Thunderline.TOCP.Security.Pruner do
  @moduledoc """
  Periodic pruning task for the replay window ETS table.

  Lightweight :timer.send_interval loop – no GenServer state beyond interval.
  """
  use GenServer
  require Logger

  @interval 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune, state) do
    try do
      Thunderline.TOCP.Security.Impl.prune_expired()
    rescue
      e -> Logger.error("[TOCP][Security.Pruner] prune error: #{inspect(e)}")
    end
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :prune, @interval)
end
