defmodule Thunderline.TOCP.Fragments do
  @moduledoc """
  Fragmentation/assembly behaviour.

  Week-2: CHUNK assembly with per-peer/global caps.
  """

  @typedoc "Fragment identifier"
  @type fid :: binary()

  @callback ingest_fragment(fid(), binary(), map()) :: :more | :complete | {:error, term()}
end
