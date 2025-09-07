defmodule Thunderline.Thunderlink.Transport.Supervisor do
  @moduledoc """
  Thunderlink Transport Supervisor (wrapper)

  This module exists to consolidate the TOCP supervision tree under the
  Thunderlink namespace without changing the underlying implementation yet.

  It delegates start-up to `Thunderline.TOCP.Supervisor` so the existing
  TOCP modules continue to function unchanged while callers can depend on
  the Thunderlink namespace.
  """

  @doc false
  # Provide a child_spec that starts the existing TOCP supervisor.
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Thunderline.TOCP.Supervisor, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
