defmodule Thunderline.Thunderbolt.ML.Types do
  @moduledoc false
  def now_utc, do: DateTime.utc_now()
  def uuid_v7, do: Thunderline.UUID.v7()
end
