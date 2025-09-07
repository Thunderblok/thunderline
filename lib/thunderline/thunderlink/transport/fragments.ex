defmodule Thunderline.Thunderlink.Transport.Fragments do
  @moduledoc """
  Fragmentation/assembly behaviour under Thunderlink.
  """
  @typedoc "Fragment identifier"
  @type fid :: binary()

  @callback ingest_fragment(fid(), binary(), map()) :: :more | :complete | {:error, term()}
end
