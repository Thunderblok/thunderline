defmodule Thunderline.Thunderbolt.VIM.Telemetry do
	@moduledoc "Telemetry helpers for VIM solve lifecycle events (Thunderbolt namespace)."
	@base [:vim]

	@spec solve_start(atom, map) :: :ok
	def solve_start(kind, meta \\ %{}), do: :telemetry.execute(@base ++ [kind, :solve, :start], %{}, meta)

	@spec solve_stop(atom, map, map) :: :ok
	def solve_stop(kind, measurements, meta \\ %{}),
		do: :telemetry.execute(@base ++ [kind, :solve, :stop], measurements, meta)

	@spec solve_error(atom, term, map) :: :ok
	def solve_error(kind, error, meta \\ %{}),
		do: :telemetry.execute(@base ++ [kind, :solve, :exception], %{}, Map.put(meta, :error, error))
end
