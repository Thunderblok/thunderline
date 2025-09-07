defmodule Thunderline.TOCP.Wire do
  @moduledoc """
  Deprecated: Wire-level constants & envelope encoding/decoding contracts.
  Prefer `Thunderline.Thunderlink.Transport.Wire`.

  Defines the public behaviours for packing/unpacking TOCP frames (ETF/BERT envelope),
  version negotiation, and frame classification. No logic yet – scaffold only.
  """

  @typedoc "Opaque wire frame binary"
  @type frame :: binary()

  @typedoc "TOCP wire version"
  @type version :: non_neg_integer()

  @callback current_version() :: version()
  @callback encode(map()) :: frame()
  @callback decode(frame()) :: {:ok, map()} | {:error, term()}
end
