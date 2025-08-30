defmodule Thunderline.Thunderbolt.VIM.Telemetry do
  @moduledoc "Canonical VIM Telemetry module under Thunderbolt; delegates to Thunderline.VIM.Telemetry."
  defdelegate solve_start(kind, meta \\ %{}), to: Thunderline.VIM.Telemetry
  defdelegate solve_stop(kind, measurements, meta \\ %{}), to: Thunderline.VIM.Telemetry
  defdelegate solve_error(kind, error, meta \\ %{}), to: Thunderline.VIM.Telemetry
end
