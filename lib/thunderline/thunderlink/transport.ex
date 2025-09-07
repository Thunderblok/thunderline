defmodule Thunderline.Thunderlink.Transport do
  @moduledoc """
  Thunderlink Transport Facade

  Consolidates access to transport (TOCP) capabilities under the
  `Thunderline.Thunderlink` namespace while delegating to existing TOCP
  implementations. This allows gradual migration without breaking changes.

  Surface area:
  - Config: get/0, reload/0, get_in_path/1
  - Telemetry: emit/3
  - Metrics: snapshot/0, reset/0 (security counters)
  """

  # Config
  defdelegate get_config, to: Thunderline.Thunderlink.Transport.Config, as: :get
  defdelegate reload_config, to: Thunderline.Thunderlink.Transport.Config, as: :reload
  defdelegate config_in(path), to: Thunderline.Thunderlink.Transport.Config, as: :get_in_path

  # Telemetry
  @spec emit(atom(), map(), map()) :: :ok
  defdelegate emit(event, meas, meta), to: Thunderline.Thunderlink.Transport.Telemetry

  # Metrics (security counters aggregator)
  defdelegate snapshot, to: Thunderline.Thunderlink.Transport.Telemetry.Aggregator
  defdelegate reset, to: Thunderline.Thunderlink.Transport.Telemetry.Aggregator

  # Security helpers
  @spec sign(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  defdelegate sign(key_id, payload), to: Thunderline.Thunderlink.Transport.Security.Impl

  @spec verify(binary(), binary(), binary()) :: :ok | {:error, term()}
  defdelegate verify(key_id, payload, sig), to: Thunderline.Thunderlink.Transport.Security.Impl

  @spec replay_seen?(binary(), binary(), non_neg_integer()) :: boolean()
  defdelegate replay_seen?(key_id, mid, ts_ms), to: Thunderline.Thunderlink.Transport.Security.Impl
end
