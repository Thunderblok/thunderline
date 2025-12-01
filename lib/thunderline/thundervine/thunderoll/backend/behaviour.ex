defmodule Thunderline.Thundervine.Thunderoll.Backend do
  @moduledoc """
  Behaviour for Thunderoll compute backends.

  Backends handle the core EGGROLL math:
  - Computing aggregated updates from perturbation seeds and fitness vectors
  - Optionally: parameter storage and delta application

  ## Implementations

  - `RemoteJax` - HTTP/gRPC client for JAX EGGROLL server (Phase 1)
  - `NxNative` - Pure Elixir/Nx implementation (Phase 2)

  ## Backend Selection

  Remote backends are useful when:
  - You have GPU clusters available
  - You want to leverage JAX's XLA compilation
  - Population sizes are very large (>100k)

  Native backends are useful when:
  - Running on-device / embedded
  - Low latency is critical
  - Population sizes are moderate (<10k)
  """

  @doc """
  Compute the aggregated EGGROLL update.

  Given perturbation seeds and fitness values, compute:
    Δ = (1/Nσ) * Σᵢ(fᵢ * Aᵢ * Bᵢᵀ)

  ## Parameters

  - `perturbation_seeds` - List of integer seeds for perturbation reconstruction
  - `fitness_vector` - List of fitness values, one per population member
  - `config` - Backend configuration:
    - `:rank` - Low-rank dimension
    - `:sigma` - Perturbation standard deviation
    - `:param_shape` - Shape of parameter matrix {m, n}

  ## Returns

  - `{:ok, delta}` - Delta parameter map
  - `{:error, reason}` - On failure
  """
  @callback compute_update([integer()], [float()], map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Check if backend is available and healthy.
  """
  @callback healthy?() :: boolean()

  @doc """
  Get backend capabilities and configuration.
  """
  @callback info() :: map()

  @optional_callbacks [healthy?: 0, info: 0]
end
