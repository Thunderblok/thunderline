defmodule Thunderline.Thundergate.SelfTest do
  @moduledoc "Boot-time self test ensuring Gate enforcement is active (401 on protected route)."
  use GenServer
  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    if gate_selftest_disabled?() do
      Logger.info("Gate self-test disabled for this environment")
      {:ok, %{done: true, skipped: true}}
    else
      # Delay slightly to allow Endpoint to come up
      Process.send_after(self(), :probe, 800)
      {:ok, %{done: false}}
    end
  end

  @impl true
  def handle_info(:probe, state) do
    result = probe()
    :telemetry.execute([:thunderline, :gate, :self_test, :result], %{count: 1}, %{result: result})

    case result do
      :ok ->
        Logger.info("Gate self-test passed (401 confirmed)")

      :ok_forbidden ->
        Logger.warning(
          "Gate self-test acceptable (403) — refine policy to return 401 for unauthenticated, 403 for unauthorized."
        )

      other ->
        Logger.error("Gate self-test FAILED: #{inspect(other)}")
    end

    {:noreply, %{state | done: true}}
  end

  defp gate_selftest_disabled? do
    System.get_env("GATE_SELFTEST_DISABLED") in ["1", "true", "TRUE"] or
      Application.get_env(:thunderline, :gate_selftest_disabled, false)
  end

  defp probe do
    url = ~c"http://127.0.0.1:4000/admin"
    headers = []

    case :hackney.request(:get, url, headers, <<>>, []) do
      {:ok, status, _resp_headers, client} ->
        _ = :hackney.body(client)

        cond do
          status == 401 -> :ok
          status == 403 -> :ok_forbidden
          true -> {:unexpected_status, status}
        end

      other ->
        {:request_error, other}
    end
  rescue
    e -> {:exception, e}
  end
end
