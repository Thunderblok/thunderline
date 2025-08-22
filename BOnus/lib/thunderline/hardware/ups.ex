defmodule Thunderline.Hardware.UPS do
  @moduledoc """Watches UPS via NUT or apcupsd and triggers boundary close on battery."""
  use GenServer
  alias Thunderline.Bus

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
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
      Bus.broadcast_status(%{stage: "paused", reason: "#{status}", source: "ups"})
      try do _ = Thunderline.Current.Sensor.boundary_close(s.close_ms) rescue _ -> :ok end
    end
    if status == :online and s.last in [:on_battery, :low_battery] do
      Bus.broadcast_status(%{stage: "power_restored", source: "ups"})
    end
    Process.send_after(self(), :poll, s.poll)
    {:noreply, %{s | last: status}}
  end

  defp read_status("nut", name) do
    case System.find_executable("upsc") do
      nil -> {:unknown, "upsc not found"}
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
      nil -> {:unknown, "apcaccess not found"}
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
