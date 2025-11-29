defmodule Thunderline.Thundergate.UPS do
  @moduledoc """
  UPS watcher (migrated from Thunderline.Hardware.UPS). Polls backend (NUT/APC) and
  emits status events to the bus. Old module remains as deprecated delegate.
  """
  use GenServer
  alias Thunderline.Thunderbolt.Signal.Sensor
  require Logger
  # Removed unused @legacy attribute (legacy module retained for reference)

  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)

  def init(_) do
    state = %{
      backend: System.get_env("UPS_BACKEND", "nut"),
      name: System.get_env("UPS_NAME", "ups@localhost"),
      poll: String.to_integer(System.get_env("UPS_POLL_MS", "2000")),
      close_ms: String.to_integer(System.get_env("UPS_CLOSE_TIMEOUT_MS", "200")),
      last: :unknown
    }

    Process.send_after(self(), :poll, 0)
    {:ok, state}
  end

  def handle_info(:poll, s) do
    {status, _raw} = read_status(s.backend, s.name)

    if status in [:on_battery, :low_battery] and s.last != status do
      with {:ok, ev} <-
             Thunderline.Event.new(%{
               name: "system.gate.system_power_event",
               type: :system_power_event,
               source: :gate,
               payload: %{stage: "paused", reason: to_string(status), source: "ups"},
               meta: %{pipeline: :realtime},
               priority: :high
             }) do
        case Thunderline.EventBus.publish_event(ev) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("[UPS] publish paused failed: #{inspect(reason)} status=#{status}")
        end
      end

      safe_boundary_close(s.close_ms)
    end

    if status == :online and s.last in [:on_battery, :low_battery] do
      with {:ok, ev} <-
             Thunderline.Event.new(%{
               name: "system.gate.system_power_event",
               type: :system_power_event,
               source: :gate,
               payload: %{stage: "power_restored", source: "ups"},
               meta: %{pipeline: :realtime},
               priority: :high
             }) do
        case Thunderline.EventBus.publish_event(ev) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("[UPS] publish power_restored failed: #{inspect(reason)}")
        end
      end
    end

    Process.send_after(self(), :poll, s.poll)
    {:noreply, %{s | last: status}}
  end

  defp safe_boundary_close(ms) do
    try do
      Sensor.boundary_close(ms)
    rescue
      _ -> :ok
    end
  end

  # (Copied from legacy implementation)
  defp read_status("nut", name) do
    case System.find_executable("upsc") do
      nil ->
        {:unknown, "upsc not found"}

      _ ->
        {out, _} = System.cmd("upsc", [name, "ups.status"], stderr_to_stdout: true)

        cond do
          String.contains?(out, "OB") -> {:on_battery, out}
          String.contains?(out, "LB") -> {:low_battery, out}
          String.contains?(out, "OL") -> {:online, out}
          true -> {:unknown, out}
        end
    end
  end

  defp read_status("apcupsd", _name) do
    case System.find_executable("apcaccess") do
      nil ->
        {:unknown, "apcaccess not found"}

      _ ->
        {out, _} = System.cmd("apcaccess", ["-p", "STATUS"], stderr_to_stdout: true)

        cond do
          String.contains?(out, "ONBATT") -> {:on_battery, out}
          String.contains?(out, "LOWBATT") -> {:low_battery, out}
          String.contains?(out, "ONLINE") -> {:online, out}
          true -> {:unknown, out}
        end
    end
  end

  defp read_status(_, name), do: read_status("nut", name)
end
