defmodule Thunderline.EventProcessor do
  @moduledoc """
  Simple, direct event processor without orchestration overhead.
  
  Handles the basic claim → normalize → emit → ack flow efficiently.
  This is the default path (TL_ENABLE_REACTOR=false) that provides
  80% of operational benefits with minimal complexity.
  """
  
  require Logger
  alias Thunderline.{EventBus}
  
  @doc """
  Process a single event with basic error handling and cleanup.
  
  Flow: claim → normalize → parallel emit → ack
  Failures: best-effort cleanup, log and return error
  """
  @spec process_event(map()) :: {:ok, :acked} | {:error, term()}
  def process_event(event) when is_map(event) do
    with {:ok, claim_id} <- claim_event(event),
         {:ok, normalized} <- normalize_event(event),
         :ok <- emit_parallel(normalized),
         :ok <- ack_event(claim_id) do
      {:ok, :acked}
    else
      error ->
        # Best-effort cleanup; claim_id may not exist if earlier step failed
        _ = safe_cleanup(error)
        {:error, error}
    end
  end
  
  # Mock claim/ack for now - replace with actual MnesiaProducer when ready
  defp claim_event(_event) do
    claim_id = generate_claim_id()
    {:ok, claim_id}
  end
  
  defp ack_event(_claim_id) do
    :ok
  end
  
  defp normalize_event(event) do
    # Basic normalization - ensure required fields exist
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
    # Run two emits concurrently without Broadway/Reactor overhead
    t0 = System.monotonic_time()
    
    tasks = [
      Task.async(fn -> 
        EventBus.emit_realtime(:event_processed, event)
      end),
      Task.async(fn -> 
        EventBus.emit(:cross_domain_event, event)
      end)
    ]
    
    # Wait up to 5 seconds for both emits
    results = Task.yield_many(tasks, 5_000)
    
    # Record latency telemetry
    duration = System.monotonic_time() - t0
    :telemetry.execute(
      [:thunderline, :event_processor, :emit],
      %{duration: duration, count: 1},
      %{
        source_domain: event["source_domain"],
        target_domain: event["target_domain"]
      }
    )
    
    # Check if both tasks completed successfully
    case results do
      [{_task1, {:ok, :ok}}, {_task2, {:ok, :ok}}] -> 
        :ok
      _ ->
        Logger.warning("Event emit tasks did not complete successfully: #{inspect(results)}")
        # Clean up any running tasks
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
        {:error, :emit_failed}
    end
  end
  
  defp safe_cleanup({:ok, claim_id}) when is_binary(claim_id) do
    # If we got a claim_id, try to release it
    ack_event(claim_id)
  end
  
  defp safe_cleanup(_), do: :ok
  
  defp generate_claim_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end