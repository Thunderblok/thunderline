defmodule Thunderline.Thunderbolt.IsingMachine.Kernel do
  @moduledoc """
  Low-level compute kernels for Ising optimization.

  Contains Nx.Defn implementations of spin update rules,
  energy calculations, and other core operations.

  This is a stub module - full Nx kernel implementations pending.
  """

  import Nx.Defn

  @doc """
  Generate random spin configuration.

  Returns tensor of shape {height, width} with values -1 or +1.
  """
  def random_spins(height, width, opts \\ []) do
    key = Keyword.get(opts, :key, Nx.Random.key(System.system_time()))

    {random, _new_key} = Nx.Random.uniform(key, shape: {height, width})

    # Convert uniform [0,1) to {-1, +1}
    Nx.select(Nx.greater(random, 0.5), 1, -1)
  end

  @doc """
  Compute total energy for 2D grid with coupling matrix.

  E = -sum(J_ij * s_i * s_j) - sum(h_i * s_i)
  """
  defn total_energy_grid(spins, coupling_matrix, field_tensor) do
    # Interaction energy from neighbors
    {height, width} = Nx.shape(spins)

    # Horizontal neighbors
    h_energy =
      spins
      |> Nx.slice([0, 0], [height, width - 1])
      |> Nx.multiply(Nx.slice(spins, [0, 1], [height, width - 1]))
      |> Nx.sum()

    # Vertical neighbors
    v_energy =
      spins
      |> Nx.slice([0, 0], [height - 1, width])
      |> Nx.multiply(Nx.slice(spins, [1, 0], [height - 1, width]))
      |> Nx.sum()

    # Extract coupling strengths (assume first element is J for now)
    j = coupling_matrix[0][0]

    # Field energy
    field_energy = Nx.sum(Nx.multiply(field_tensor, spins))

    # Total energy
    -(j * (h_energy + v_energy)) - field_energy
  end

  @doc """
  Compute magnetization (mean spin value).
  """
  defn magnetization(spins) do
    Nx.mean(spins)
  end

  @doc """
  Single Metropolis-Hastings spin flip step.

  Returns updated spins and whether flip was accepted.
  """
  defn metropolis_step(spins, i, j, coupling_matrix, field, temperature, key) do
    {height, width} = Nx.shape(spins)

    current_spin = spins[i][j]
    new_spin = -current_spin

    # Compute local energy change (delta E)
    # Get neighbor spins with boundary handling
    top = Nx.select(i > 0, spins[i - 1][j], 0)
    bottom = Nx.select(i < height - 1, spins[i + 1][j], 0)
    left = Nx.select(j > 0, spins[i][j - 1], 0)
    right = Nx.select(j < width - 1, spins[i][j + 1], 0)

    neighbor_sum = top + bottom + left + right
    j_coupling = coupling_matrix[0][0]
    h_field = field[i][j]

    delta_e = 2 * current_spin * (j_coupling * neighbor_sum + h_field)

    # Metropolis acceptance
    {random, new_key} = Nx.Random.uniform(key)
    accept_prob = Nx.exp(-delta_e / temperature)
    accept = Nx.logical_or(delta_e < 0, random < accept_prob)

    # Update spins
    new_spins =
      Nx.select(accept, Nx.put_slice(spins, [i, j], Nx.reshape(new_spin, {1, 1})), spins)

    {new_spins, accept, new_key}
  end
end
