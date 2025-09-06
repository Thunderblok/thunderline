if Application.compile_env(:thunderline, [:thunderbolt, :enable_non_ising], false) do
  defmodule Thunderline.Thunderbolt.IsingMachine.Anneal do
    @moduledoc """
    Stub annealing process supervisor (non-Ising path; gated by :enable_non_ising flag).
    """
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, [])
    def init(opts), do: {:ok, %{opts: opts, steps: 0}}
  end
end
