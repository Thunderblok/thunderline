defmodule Thunderline.TOCP.Routing do
  @moduledoc """
  Routing directory contracts – relay adverts & selection with hysteresis.

  Week-1: Provide selection algorithm for zone/relay with 15% hysteresis.
  Future: Multi-metric scoring, congestion awareness.
  """

  @typedoc "Opaque route target"
  @type route :: %{
          dest: binary(),
          via: [binary()],
          score: number(),
          kind: :direct | :relay | :multi
        }

  @callback select_route(binary(), keyword()) :: {:ok, route()} | {:error, term()}
  @callback advertise(map()) :: :ok
end
