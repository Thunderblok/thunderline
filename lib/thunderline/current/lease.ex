defmodule Thunderline.Current.Lease do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Signal.Lease"
  @deprecated "Use Thunderline.Thunderbolt.Signal.Lease"
  require Logger
  def make(inj, del, ttl_ms) do emit(); Thunderline.Thunderbolt.Signal.Lease.make(inj, del, ttl_ms) end
  def expired?(lease) do emit(); Thunderline.Thunderbolt.Signal.Lease.expired?(lease) end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderbolt.Signal.Lease")
  end
  def __deprecated_test_emit__, do: emit()
end
