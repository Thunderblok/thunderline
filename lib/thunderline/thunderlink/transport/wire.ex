defmodule Thunderline.Thunderlink.Transport.Wire do
  @moduledoc """
  Wire-level contracts under Thunderlink Transport.
  """
  @typedoc "Opaque wire frame binary"
  @type frame :: binary()
  @typedoc "Wire version"
  @type version :: non_neg_integer()

  @callback current_version() :: version()
  @callback encode(map()) :: frame()
  @callback decode(frame()) :: {:ok, map()} | {:error, term()}
end
