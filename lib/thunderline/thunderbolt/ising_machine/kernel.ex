if Application.compile_env(:thunderline, :enable_ising, false) do
  defmodule Thunderline.Thunderbolt.IsingMachine.Kernel do
  @moduledoc """
  Stub numerical kernels for the Ising machine.

  These return simple deterministic Nx tensors / values so higher layers can
  integrate without crashing. Real implementations would use Nx.Defn for
  vectorized performance.
  """
  require Nx

  # Deterministic-ish RNG helper that adapts to Nx API versions.
  # Avoids warnings from unused default parameters and missing arities.
  defp rng(shape, min, max, type) do
    # Prefer newer API forms if present; otherwise fall back to older variants.
    cond do
      function_exported?(Nx, :random_uniform, 4) -> Nx.random_uniform(min, max, shape, type: type)
      function_exported?(Nx, :random_uniform, 3) -> Nx.random_uniform(shape, min, max)
      true ->
        # Fallback: build a deterministic tensor from a simple linear progression
        total = Tuple.product(List.wrap(shape))
        base = Nx.iota({total}, type: :f32)
        scaled = base / Nx.Constants.pi() |> Nx.subtract(Nx.floor(base / 10))
        reshaped = Nx.reshape(scaled, shape)
        span = max - min
        Nx.add(Nx.multiply(Nx.divide(reshaped, Nx.max(reshaped) |> Nx.add(1.0e-9)), span), min)
        |> Nx.as_type(type)
    end
  rescue
    _ -> Nx.broadcast(Nx.tensor(0.0, type: type), shape)
  end

  def random_spins(height, width, _opts \\ []) do
    shape = {height, width}
    rng(shape, -1.0, 1.0, :f32)
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
end
