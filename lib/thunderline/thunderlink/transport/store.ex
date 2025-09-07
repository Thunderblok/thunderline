defmodule Thunderline.Thunderlink.Transport.Store do
  @moduledoc """
  Store-and-forward retention policy behaviour under Thunderlink.
  """
  @typedoc "Stored message reference"
  @type ref :: binary()

  @callback offer(ref(), binary(), map()) :: :ok | {:error, term()}
  @callback request(ref()) :: {:ok, binary()} | {:error, :not_found}
end
