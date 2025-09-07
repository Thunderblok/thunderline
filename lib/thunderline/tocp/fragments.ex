defmodule Thunderline.TOCP.Fragments do
  @moduledoc """
  Deprecated: Fragmentation/assembly behaviour.
  Prefer `Thunderline.Thunderlink.Transport.Fragments`.

  Week-2: CHUNK assembly with per-peer/global caps.
  """

  @typedoc "Fragment identifier"
  @type fid :: binary()

  @callback ingest_fragment(fid(), binary(), map()) :: :more | :complete | {:error, term()}
end
