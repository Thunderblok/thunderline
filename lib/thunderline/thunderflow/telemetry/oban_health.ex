defmodule Thunderline.Thunderflow.Telemetry.ObanHealth do
  @moduledoc """
  Canonical Oban health reporter (migrated from Thunderchief.ObanHealth).

  Periodically snapshots whether the Oban supervisor is alive along with queue
  names and broadcasts on `"oban:health"` via `Thunderline.PubSub`.
  """
  use GenServer
  require Logger
  alias Phoenix.PubSub

  @interval 5_000
  @topic "oban:health"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def subscribe, do: PubSub.subscribe(Thunderline.PubSub, @topic)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{last_status: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    status = snapshot()
    maybe_log_change(state.last_status, status)
    maybe_log_verbose(status)
    PubSub.broadcast(Thunderline.PubSub, @topic, {:oban_health, status})
    schedule()
    {:noreply, %{state | last_status: status}}
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval)

  defp snapshot do
    name = oban_instance_name()
    pid = Oban.whereis(name)
    %{
      running?: is_pid(pid) and Process.alive?(pid),
      queues: running_queues(pid),
      node: Node.self(),
      name: name,
      ts: DateTime.utc_now()
    }
  end

  defp running_queues(nil), do: []
  defp running_queues(pid) do
    try do
      :sys.get_state(pid)
      |> case do
        %{conf: %{queues: queues}} -> Enum.map(queues, fn {name, _opts} -> name end)
        _ -> []
      end
    rescue
      _ -> []
    end
  end

  defp maybe_log_change(nil, %{running?: false}) do
    Logger.warning("[ObanHealth] Oban not running at startup – jobs will be deferred until it comes online (name=#{inspect(oban_instance_name())}).")
  end
  defp maybe_log_change(%{running?: prev}, %{running?: now}) when prev != now do
    level = if now, do: :info, else: :error
    Logger.log(level, "[ObanHealth] Oban running? changed #{inspect(prev)} -> #{inspect(now)} (name=#{inspect(oban_instance_name())})")
  end
  defp maybe_log_change(_, _), do: :ok

  defp maybe_log_verbose(%{running?: running?, queues: queues} = status) do
    if verbose?() do
      Logger.info("[ObanHealth][tick] running=#{running?} queues=#{inspect(queues)} node=#{status.node} name=#{inspect(status.name)} ts=#{DateTime.to_iso8601(status.ts)}")
    end
  end

  defp verbose?, do: System.get_env("OBAN_HEALTH_VERBOSE") in ["1", "true", "TRUE", "yes", "Y"]

  defp oban_instance_name do
    Application.get_env(:thunderline, Oban, [])
    |> Keyword.get(:name, Oban)
  end
end
