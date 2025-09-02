defmodule Thunderline.Thundergate.SelfTest do
  @moduledoc "Boot-time self test ensuring Gate enforcement is active (401 on protected route)."
  use GenServer
  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    # Delay slightly to allow Endpoint to come up
    Process.send_after(self(), :probe, 800)
    {:ok, %{done: false}}
  end

  @impl true
  def handle_info(:probe, state) do
    result = probe()
    :telemetry.execute([:thunderline, :gate, :self_test, :result], %{count: 1}, %{result: result})
    case result do
      :ok -> Logger.info("Gate self-test passed (401 confirmed)")
      other -> Logger.error("Gate self-test FAILED: #{inspect(other)}")
    end
    {:noreply, %{state | done: true}}
  end

  defp probe do
  url = ~c"http://127.0.0.1:4000/admin"
    headers = []
    case :hackney.request(:get, url, headers, <<>>, []) do
      {:ok, status, _resp_headers, client} ->
        _ = :hackney.body(client)
        if status == 401, do: :ok, else: {:unexpected_status, status}
      other -> {:request_error, other}
    end
  rescue
    e -> {:exception, e}
  end
end
