defmodule Thunderline.Thundervine.Thunderoll.Backend.RemoteJax do
  @moduledoc """
  HTTP/gRPC client for JAX EGGROLL backend.

  The backend server handles:
  - Low-rank perturbation math (A·Bᵀ operations)
  - Aggregated update computation
  - Optionally: model storage and delta application

  Thunderline handles:
  - Orchestration and scheduling
  - Fitness evaluation (rollouts)
  - Policy enforcement
  - Persistence and auditing

  ## Configuration

  Set the backend URL via config:

      config :thunderline, Thunderline.Thundervine.Thunderoll.Backend.RemoteJax,
        url: "http://localhost:8080",
        timeout: 30_000

  Or via environment variable:

      THUNDEROLL_JAX_URL=http://localhost:8080

  ## Server Protocol

  The server expects POST requests to `/compute_update` with JSON body:

      {
        "seeds": [123, 456, ...],        // Perturbation seeds
        "fitness": [0.5, 0.7, ...],      // Fitness values
        "rank": 1,                       // Low-rank dimension
        "sigma": 0.02,                   // Perturbation std
        "param_shape": [256, 256]        // Parameter shape [m, n]
      }

  Response:

      {
        "delta": {
          "weights": [[...], [...]]      // Encoded weight delta
        }
      }
  """

  @behaviour Thunderline.Thundervine.Thunderoll.Backend

  require Logger

  @default_url "http://localhost:8080"
  @default_timeout 60_000

  # ═══════════════════════════════════════════════════════════════
  # BEHAVIOUR IMPLEMENTATION
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def compute_update(perturbation_seeds, fitness_vector, config) do
    url = backend_url()

    payload = %{
      "seeds" => perturbation_seeds,
      "fitness" => fitness_vector,
      "rank" => config.rank,
      "sigma" => config.sigma,
      "param_shape" => Tuple.to_list(config.param_shape)
    }

    Logger.debug("[Thunderoll.RemoteJax] Sending update request to #{url}")

    case Req.post(url <> "/compute_update",
           json: payload,
           receive_timeout: request_timeout()
         ) do
      {:ok, %{status: 200, body: body}} ->
        delta = decode_delta(body)
        {:ok, delta}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[Thunderoll.RemoteJax] Backend error: #{status} - #{inspect(body)}")
        {:error, {:backend_error, status, body}}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("[Thunderoll.RemoteJax] Transport error: #{inspect(reason)}")
        {:error, {:connection_error, reason}}

      {:error, reason} ->
        Logger.error("[Thunderoll.RemoteJax] Request error: #{inspect(reason)}")
        {:error, {:request_error, reason}}
    end
  end

  @impl true
  def healthy? do
    url = backend_url()

    case Req.get(url <> "/health", receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @impl true
  def info do
    %{
      type: :remote_jax,
      url: backend_url(),
      timeout: request_timeout(),
      healthy: healthy?()
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # CONFIGURATION
  # ═══════════════════════════════════════════════════════════════

  defp backend_url do
    Application.get_env(:thunderline, __MODULE__, [])
    |> Keyword.get(:url)
    |> Kernel.||(System.get_env("THUNDEROLL_JAX_URL"))
    |> Kernel.||(@default_url)
  end

  defp request_timeout do
    Application.get_env(:thunderline, __MODULE__, [])
    |> Keyword.get(:timeout, @default_timeout)
  end

  # ═══════════════════════════════════════════════════════════════
  # ENCODING/DECODING
  # ═══════════════════════════════════════════════════════════════

  defp decode_delta(%{"delta" => delta}) do
    decode_delta(delta)
  end

  defp decode_delta(%{"weights" => weights}) when is_list(weights) do
    # Convert nested list to Nx tensor
    tensor = Nx.tensor(weights, type: :f32)
    %{weights: tensor}
  end

  defp decode_delta(other) do
    Logger.warning("[Thunderoll.RemoteJax] Unexpected delta format: #{inspect(other)}")
    %{}
  end
end
