defmodule Thunderline.Thunderlink.Transport.Security.Pruner do
  @moduledoc """
  Periodic pruning task for the replay window ETS table under Thunderlink.
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
      Thunderline.Thunderlink.Transport.Security.Impl.prune_expired()
    rescue
      e -> Logger.error("[Thunderlink][Security.Pruner] prune error: #{inspect(e)}")
    end

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :prune, @interval)
end
