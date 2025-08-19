defmodule Thunderline.Thunderbolt.IsingMachine.Kernel do
  @moduledoc """
  Stub numerical kernels for the Ising machine.

  These return simple deterministic Nx tensors / values so higher layers can
  integrate without crashing. Real implementations would use Nx.Defn for
  vectorized performance.
  """
  require Nx

  def random_spins(height, width, _opts \\ []) do
    shape = {height, width}
    # Nx.random_uniform/2 signature: (shape, opts). Generate [0,1) then scale to [-1,1]
  Nx.random_uniform(shape, type: :f32, min: -1.0, max: 1.0)
    |> Nx.sign()
    |> Nx.as_type(:s8)
  end

  def total_energy_grid(spins, _coupling_matrix, field_tensor) do
    aligned = Nx.sum(spins * field_tensor)
    Nx.negate(aligned) |> Nx.as_type(:f32)
  end

  def magnetization(spins) do
    Nx.mean(spins) |> Nx.as_type(:f32)
  end
end
