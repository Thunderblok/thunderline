defmodule Thunderline.Thunderflow.Processor do
  @moduledoc """
  Canonical event processor (migrated from Thunderline.EventProcessor).

  Provides a minimal claim → normalize → emit → ack flow without orchestration
  overhead. Emits telemetry on each emit batch.
  """
  require Logger
  alias Thunderline.EventBus

  @spec process_event(map()) :: {:ok, :acked} | {:error, term()}
  def process_event(event) when is_map(event) do
    with {:ok, claim_id} <- claim_event(event),
         {:ok, normalized} <- normalize_event(event),
         :ok <- emit_parallel(normalized),
         :ok <- ack_event(claim_id) do
      {:ok, :acked}
    else
      error -> _ = safe_cleanup(error); {:error, error}
    end
  end

  defp claim_event(_), do: {:ok, generate_claim_id()}
  defp ack_event(_), do: :ok

  defp normalize_event(event) do
    normalized = %{
      "type" => Map.get(event, "type", Map.get(event, :type, "unknown")),
      "payload" => Map.get(event, "payload", Map.get(event, :payload, %{})),
      "timestamp" => Map.get(event, "timestamp", DateTime.utc_now()),
      "source_domain" => Map.get(event, "source_domain", "unknown"),
      "target_domain" => Map.get(event, "target_domain", "broadcast")
    }
    {:ok, normalized}
  end

  defp emit_parallel(event) do
    t0 = System.monotonic_time()
    tasks = [
      Task.async(fn -> EventBus.emit_realtime(:event_processed, event) end),
      Task.async(fn -> EventBus.emit(:cross_domain_event, event) end)
    ]
    results = Task.yield_many(tasks, 5_000)
    duration = System.monotonic_time() - t0
    :telemetry.execute([:thunderline, :event_processor, :emit], %{duration: duration, count: 1}, %{source_domain: event["source_domain"], target_domain: event["target_domain"]})
    case results do
      [{_, {:ok, :ok}}, {_, {:ok, :ok}}] -> :ok
      _ ->
        Logger.warning("Event emit tasks did not complete successfully: #{inspect(results)}")
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
        {:error, :emit_failed}
    end
  end

  defp safe_cleanup({:ok, claim_id}) when is_binary(claim_id), do: ack_event(claim_id)
  defp safe_cleanup(_), do: :ok
  defp generate_claim_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
