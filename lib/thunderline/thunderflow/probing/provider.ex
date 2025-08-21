defmodule Thunderline.Thunderflow.Probing.Provider do
  @moduledoc """
  Behaviour for model/text generation providers used by probe runs.

  A provider receives the full prompt text and a spec map (model, any extra
  provider-specific options) and returns {:ok, text} | {:error, reason}.

  This is a trimmed integration of the former Raincatcher provider behaviour
  scoped under Thunderflow.
  """
  @callback generate(prompt :: String.t(), spec :: map()) :: {:ok, String.t()} | {:error, term()}
end
