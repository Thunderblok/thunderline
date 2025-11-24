defmodule Thunderline.Thundergate.ServiceRegistry.HealthMonitor do
  @moduledoc """
  GenServer that monitors service health by checking for stale heartbeats.

  Services are expected to send heartbeats every `heartbeat_interval` seconds.
  If a service hasn't sent a heartbeat in `stale_threshold` seconds, it's marked unhealthy.
  """
  use GenServer
  require Logger
  alias Thunderline.Thundergate.ServiceRegistry.Service

  @heartbeat_check_interval :timer.seconds(30)
  @stale_threshold :timer.seconds(90)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first health check
    schedule_health_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_health, state) do
    check_all_services()
    schedule_health_check()
    {:noreply, state}
  end

  defp schedule_health_check do
    Process.send_after(self(), :check_health, @heartbeat_check_interval)
  end

  defp check_all_services do
    Logger.debug("Checking service health...")

    services = Service.list!()
    stale_cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold, :millisecond)

    Enum.each(services, fn service ->
      cond do
        # Service never sent a heartbeat and has been registered for too long
        is_nil(service.last_heartbeat_at) and
            DateTime.diff(DateTime.utc_now(), service.registered_at, :millisecond) >
              @stale_threshold ->
          Logger.warning(
            "Service #{service.service_id} (#{service.name}) never sent heartbeat, marking unhealthy"
          )

          Service.mark_unhealthy!(service)

        # Service heartbeat is stale
        service.last_heartbeat_at &&
            DateTime.compare(service.last_heartbeat_at, stale_cutoff) == :lt ->
          Logger.warning(
            "Service #{service.service_id} (#{service.name}) heartbeat stale (last: #{service.last_heartbeat_at}), marking unhealthy"
          )

          Service.mark_unhealthy!(service)

        # Service is healthy
        true ->
          :ok
      end
    end)
  end
end
