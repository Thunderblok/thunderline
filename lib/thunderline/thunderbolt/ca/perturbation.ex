defmodule Thunderline.Thunderbolt.CA.Perturbation do
  @moduledoc """
  HC-55: Perturbation Layer - SLiM-style decorrelation for error tolerance.

  Implements research from "Hundred-Layer Photonic Deep Learning" (Nature 2024):
  - **Propagation Redundancy Breaking**: Inject noise to decorrelate error paths
  - **Layer-wise Perturbations**: Small perturbations prevent error accumulation
  - **Criticality-Aware Scaling**: Perturbation intensity based on λ̂ from LoopMonitor

  ## Why Perturbations?

  In deep networks (CA lattices, SNNs), errors propagate and accumulate.
  The SLiM paper shows that small perturbations at each layer:
  1. Break correlations between error paths
  2. Prevent catastrophic error accumulation
  3. Enable 100+ layer depth without degradation

  ## Perturbation Strategies

  - `:uniform` - Uniform noise in [-σ, +σ]
  - `:gaussian` - Gaussian noise with std σ
  - `:dropout` - Random zeroing with probability p
  - `:salt_pepper` - Binary noise (flip to min/max)

  ## Integration with LoopMonitor

  When λ̂ deviates from critical band [0.25, 0.35]:
  - λ̂ < 0.25 (ordered): Increase perturbation to add chaos
  - λ̂ > 0.35 (chaotic): Decrease perturbation to reduce noise
  - λ̂ ∈ [0.25, 0.35]: Minimal baseline perturbation

  ## Telemetry

  Emits `[:thunderline, :bolt, :ca, :perturbation]` with:
  - Applied noise statistics
  - Current σ value
  - LoopMonitor feedback
  """

  alias Thunderline.Thunderbolt.Signal.LoopMonitor

  @type strategy :: :uniform | :gaussian | :dropout | :salt_pepper
  @type config :: %{
          strategy: strategy(),
          sigma: float(),
          dropout_p: float(),
          min_sigma: float(),
          max_sigma: float(),
          adaptive: boolean(),
          loop_monitor: GenServer.server() | nil
        }

  @default_config %{
    strategy: :gaussian,
    sigma: 0.01,
    dropout_p: 0.1,
    min_sigma: 0.001,
    max_sigma: 0.1,
    adaptive: true,
    loop_monitor: nil
  }

  # ──────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Creates a perturbation configuration.

  ## Options

  - `:strategy` - Noise strategy (default: :gaussian)
  - `:sigma` - Noise standard deviation (default: 0.01)
  - `:dropout_p` - Dropout probability for :dropout strategy (default: 0.1)
  - `:min_sigma` - Minimum adaptive sigma (default: 0.001)
  - `:max_sigma` - Maximum adaptive sigma (default: 0.1)
  - `:adaptive` - Enable LoopMonitor-driven adaptation (default: true)
  - `:loop_monitor` - LoopMonitor server for criticality feedback
  """
  @spec new(keyword()) :: config()
  def new(opts \\ []) do
    Map.merge(@default_config, Map.new(opts))
  end

  @doc """
  Applies perturbation to a single numeric value.
  """
  @spec perturb(config(), number()) :: float()
  def perturb(config, value) when is_number(value) do
    sigma = effective_sigma(config)
    noise = generate_noise(config.strategy, sigma, config.dropout_p)

    emit_telemetry(:scalar, sigma, noise)

    value + noise
  end

  @doc """
  Applies perturbation to a list of values (e.g., CA state vector).
  """
  @spec perturb_list(config(), list(number())) :: list(float())
  def perturb_list(config, values) when is_list(values) do
    sigma = effective_sigma(config)

    result =
      Enum.map(values, fn v ->
        noise = generate_noise(config.strategy, sigma, config.dropout_p)
        v + noise
      end)

    emit_telemetry(:list, sigma, length(values))

    result
  end

  @doc """
  Applies perturbation to a 2D grid (e.g., CA lattice state).
  """
  @spec perturb_grid(config(), list(list(number()))) :: list(list(float()))
  def perturb_grid(config, grid) when is_list(grid) do
    sigma = effective_sigma(config)

    result =
      Enum.map(grid, fn row ->
        Enum.map(row, fn v ->
          noise = generate_noise(config.strategy, sigma, config.dropout_p)
          v + noise
        end)
      end)

    grid_size = length(grid) * length(List.first(grid) || [])
    emit_telemetry(:grid, sigma, grid_size)

    result
  end

  @doc """
  Applies binary perturbation (for discrete CA states).
  Flips cell state with probability p.
  """
  @spec perturb_binary(config(), list(0 | 1)) :: list(0 | 1)
  def perturb_binary(config, states) when is_list(states) do
    sigma = effective_sigma(config)
    # Use sigma as flip probability for binary states
    flip_p = min(sigma, 0.5)

    result =
      Enum.map(states, fn s ->
        if :rand.uniform() < flip_p do
          1 - s
        else
          s
        end
      end)

    emit_telemetry(:binary, flip_p, length(states))

    result
  end

  @doc """
  Applies dropout perturbation (for spike trains or activations).
  Sets values to 0 with probability p.
  """
  @spec dropout(config(), list(number())) :: list(number())
  def dropout(config, values) when is_list(values) do
    p = config.dropout_p

    result =
      Enum.map(values, fn v ->
        if :rand.uniform() < p, do: 0.0, else: v
      end)

    emit_telemetry(:dropout, p, length(values))

    result
  end

  @doc """
  Computes the effective sigma based on config and LoopMonitor feedback.
  """
  @spec effective_sigma(config()) :: float()
  def effective_sigma(%{adaptive: false, sigma: sigma}), do: sigma

  def effective_sigma(%{adaptive: true, loop_monitor: nil, sigma: sigma}), do: sigma

  def effective_sigma(%{adaptive: true, loop_monitor: monitor} = config) do
    try do
      recommended = LoopMonitor.recommended_perturbation(monitor)
      # Clamp to configured bounds
      max(config.min_sigma, min(recommended, config.max_sigma))
    rescue
      _ -> config.sigma
    catch
      :exit, _ -> config.sigma
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Layer-wise Perturbation (SLiM-style)
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Applies layer-wise perturbations for multi-layer CA/SNN.

  The SLiM paper shows that perturbations should scale with layer depth:
  - Earlier layers: Lower perturbation (less accumulated error)
  - Later layers: Higher perturbation (more error accumulation)

  ## Options

  - `:layer_index` - Current layer (0-indexed)
  - `:total_layers` - Total number of layers
  - `:scaling` - :linear, :sqrt, or :log scaling with depth
  """
  @spec perturb_layer(config(), list(number()), keyword()) :: list(float())
  def perturb_layer(config, values, opts \\ []) do
    layer_idx = Keyword.get(opts, :layer_index, 0)
    total_layers = Keyword.get(opts, :total_layers, 1)
    scaling = Keyword.get(opts, :scaling, :sqrt)

    # Compute depth-dependent scaling factor
    depth_ratio = (layer_idx + 1) / max(total_layers, 1)

    scale_factor =
      case scaling do
        :linear -> depth_ratio
        :sqrt -> :math.sqrt(depth_ratio)
        :log -> :math.log(depth_ratio + 1) / :math.log(2)
        _ -> 1.0
      end

    # Apply scaled perturbation
    base_sigma = effective_sigma(config)
    layer_sigma = base_sigma * scale_factor

    scaled_config = %{config | sigma: layer_sigma}
    perturb_list(scaled_config, values)
  end

  # ──────────────────────────────────────────────────────────────────────
  # Decorrelation Metrics
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Computes correlation between two state vectors.
  Used to verify perturbations are breaking error correlations.
  """
  @spec correlation(list(number()), list(number())) :: float()
  def correlation([], _), do: 0.0
  def correlation(_, []), do: 0.0

  def correlation(xs, ys) do
    n = min(length(xs), length(ys))
    xs = Enum.take(xs, n)
    ys = Enum.take(ys, n)

    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n

    cov =
      Enum.zip(xs, ys)
      |> Enum.map(fn {x, y} -> (x - mean_x) * (y - mean_y) end)
      |> Enum.sum()

    var_x = Enum.map(xs, fn x -> (x - mean_x) * (x - mean_x) end) |> Enum.sum()
    var_y = Enum.map(ys, fn y -> (y - mean_y) * (y - mean_y) end) |> Enum.sum()

    denom = :math.sqrt(var_x * var_y)

    if denom == 0.0 do
      0.0
    else
      cov / denom
    end
  end

  @doc """
  Measures decorrelation effectiveness by comparing pre/post perturbation.
  Returns a value in [0, 1] where 1 = fully decorrelated.
  """
  @spec decorrelation_score(list(number()), list(number())) :: float()
  def decorrelation_score(original, perturbed) do
    corr = abs(correlation(original, perturbed))
    1.0 - corr
  end

  # ──────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────

  defp generate_noise(:uniform, sigma, _p) do
    # Uniform in [-sigma, +sigma]
    (:rand.uniform() * 2.0 - 1.0) * sigma
  end

  defp generate_noise(:gaussian, sigma, _p) do
    :rand.normal() * sigma
  end

  defp generate_noise(:dropout, _sigma, p) do
    if :rand.uniform() < p, do: :dropout, else: 0.0
  end

  defp generate_noise(:salt_pepper, sigma, _p) do
    # Binary noise: either +sigma or -sigma
    if :rand.uniform() > 0.5, do: sigma, else: -sigma
  end

  defp generate_noise(_, sigma, _p) do
    # Default to gaussian
    :rand.normal() * sigma
  end

  defp emit_telemetry(mode, sigma, count) do
    :telemetry.execute(
      [:thunderline, :bolt, :ca, :perturbation],
      %{
        sigma: sigma,
        count: count
      },
      %{
        mode: mode,
        strategy: :perturbation
      }
    )
  end
end
