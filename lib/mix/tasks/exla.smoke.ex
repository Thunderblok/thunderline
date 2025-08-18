defmodule Mix.Tasks.Exla.Smoke do
  @shortdoc "Run an EXLA/Nx backend smoke test (host + optional CUDA)"
  @moduledoc """
  Runs a minimal Nx computation using the EXLA backend and reports:
  * Availability of host client
  * Availability of CUDA client (if CUDA libraries present)
  * Active default backend
  * Sample tensor result

  Usage:
      SKIP_ASH_SETUP=true mix exla.smoke

  Set XLA_TARGET=cuda to force compilation for CUDA if needed.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.shell().info("[exla.smoke] Starting EXLA smoke test...")

    # Start only required part of the app (avoid full supervision tree complexity if desired)
    # Ensure dependent apps are started
    Enum.each([:telemetry, :nimble_pool, :complex, :nx], &Application.ensure_all_started/1)

    # Configure desired clients (host always; cuda optional)
    Application.put_env(:exla, :clients, [host: [platform: :host], cuda: [platform: :cuda]])

    case Application.ensure_all_started(:exla) do
      {:ok, _} -> Mix.shell().info("[exla.smoke] :exla started OK")
      other -> Mix.shell().error("[exla.smoke] Failed to start :exla: #{inspect(other)}")
    end

    # Attempt to set default backend
    case Nx.default_backend(EXLA.Backend) do
      :ok -> Mix.shell().info("[exla.smoke] Default backend set to EXLA.Backend")
      other -> Mix.shell().error("[exla.smoke] Could not set EXLA backend: #{inspect(other)}")
    end

    host_status = fetch_client(:host)
    cuda_status = fetch_client(:cuda)

    Mix.shell().info("[exla.smoke] Host client:  #{host_status}")
    Mix.shell().info("[exla.smoke] CUDA client:  #{cuda_status}")

    # Run a simple computation to verify backend functionality (falls back if EXLA not active)
    t = Nx.tensor([[1, 2], [3, 4]]) |> Nx.add(5) |> Nx.multiply(2)
    Mix.shell().info("[exla.smoke] Sample tensor result (shape #{inspect(Nx.shape(t))}, backend #{inspect(elem(Nx.backend(t),0))}):\n#{inspect(t)}")

    Mix.shell().info("[exla.smoke] Done")
  end

  defp fetch_client(name) do
    try do
      _client = EXLA.Client.fetch!(name)
      "available"
    rescue
      e -> "unavailable (#{Exception.message(e)})"
    end
  end
end
