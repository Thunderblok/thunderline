defmodule Thunderline.Event do
  @moduledoc """
  Canonical event struct for all Thunderline event processing.
  
  This struct provides a standardized shape for events flowing through
  Broadway pipelines, ensuring consistent field access and validation.
  
  ## Fields
  
  - `type` - Event type as atom (required)
  - `payload` - Event data as map (required)
  - `source_domain` - Origin domain (required)
  - `target_domain` - Destination domain (optional, defaults to "broadcast")
  - `timestamp` - Event creation time (auto-generated)
  - `correlation_id` - Tracing identifier (auto-generated)
  - `hop_count` - Cross-domain routing count (starts at 0)
  - `priority` - Processing priority (:low, :normal, :high, :critical)
  - `metadata` - Additional processing metadata
  """
  
  @type priority :: :low | :normal | :high | :critical
  
  @type t :: %__MODULE__{
    type: atom(),
    payload: map(),
    source_domain: String.t(),
    target_domain: String.t(),
    timestamp: DateTime.t(),
    correlation_id: String.t(),
    hop_count: non_neg_integer(),
    priority: priority(),
    metadata: map()
  }
  
  @enforce_keys [:type, :payload, :source_domain]
  defstruct [
    :type,
    :payload, 
    :source_domain,
    target_domain: "broadcast",
    timestamp: nil,
    correlation_id: nil,
    hop_count: 0,
    priority: :normal,
    metadata: %{}
  ]
  
  @doc """
  Normalize an event from various input formats to canonical `%Thunderline.Event{}`.
  
  Accepts:
  - Maps with string keys (Broadway pipeline format)
  - Maps with atom keys (EventBus format)
  - Existing `%Thunderline.Event{}` structs (passthrough)
  
  ## Examples
  
      iex> Thunderline.Event.normalize(%{"type" => "user_created", "payload" => %{"id" => 1}})
      {:ok, %Thunderline.Event{type: :user_created, payload: %{"id" => 1}, ...}}
      
      iex> Thunderline.Event.normalize(%{type: :agent_spawned, payload: %{agent_id: "123"}})
      {:ok, %Thunderline.Event{type: :agent_spawned, payload: %{agent_id: "123"}, ...}}
  """
  @spec normalize(map() | t()) :: {:ok, t()} | {:error, term()}
  def normalize(%__MODULE__{} = event), do: {:ok, event}
  
  def normalize(event) when is_map(event) do
    try do
      normalized = %__MODULE__{
        type: extract_type(event),
        payload: extract_payload(event),
        source_domain: extract_source_domain(event),
        target_domain: extract_target_domain(event),
        timestamp: extract_timestamp(event),
        correlation_id: extract_correlation_id(event),
        hop_count: extract_hop_count(event),
        priority: extract_priority(event),
        metadata: extract_metadata(event)
      }
      
      {:ok, normalized}
    rescue
      error -> {:error, {:normalization_failed, error}}
    end
  end
  
  def normalize(_), do: {:error, :invalid_event_format}
  
  @doc """
  Normalize an event, raising on failure.
  
  Same as `normalize/1` but raises `ArgumentError` on failure.
  """
  @spec normalize!(map() | t()) :: t()
  def normalize!(event) do
    case normalize(event) do
      {:ok, normalized} -> normalized
      {:error, reason} -> raise ArgumentError, "Event normalization failed: #{inspect(reason)}"
    end
  end
  
  @doc """
  Convert a canonical event back to a map for JSON serialization or external APIs.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "type" => to_string(event.type),
      "payload" => event.payload,
      "source_domain" => event.source_domain,
      "target_domain" => event.target_domain,
      "timestamp" => DateTime.to_iso8601(event.timestamp),
      "correlation_id" => event.correlation_id,
      "hop_count" => event.hop_count,
      "priority" => to_string(event.priority),
      "metadata" => event.metadata
    }
  end
  
  @doc """
  Increment hop count for cross-domain routing.
  """
  @spec increment_hop_count(t()) :: t()
  def increment_hop_count(%__MODULE__{} = event) do
    %{event | hop_count: event.hop_count + 1}
  end
  
  @doc """
  Add metadata to an event.
  """
  @spec put_metadata(t(), atom() | String.t(), term()) :: t()
  def put_metadata(%__MODULE__{} = event, key, value) do
    %{event | metadata: Map.put(event.metadata, key, value)}
  end
  
  @doc """
  Check if an event is high priority (high or critical).
  """
  @spec high_priority?(t()) :: boolean()
  def high_priority?(%__MODULE__{priority: priority}) when priority in [:high, :critical], do: true
  def high_priority?(_), do: false
  
  # Private extraction functions
  
  defp extract_type(%{"type" => type}) when is_binary(type), do: String.to_atom(type)
  defp extract_type(%{type: type}) when is_atom(type), do: type
  defp extract_type(%{"event_type" => type}) when is_binary(type), do: String.to_atom(type)
  defp extract_type(_), do: :unknown_event
  
  defp extract_payload(%{"payload" => payload}) when is_map(payload), do: payload
  defp extract_payload(%{payload: payload}) when is_map(payload), do: payload
  defp extract_payload(%{"data" => data}) when is_map(data), do: data
  defp extract_payload(%{data: data}) when is_map(data), do: data
  defp extract_payload(event) when is_map(event) do
    # If no explicit payload, use the entire event minus known fields
    event
    |> Map.drop(["type", "event_type", :type, "source_domain", :source_domain, 
                 "target_domain", :target_domain, "timestamp", :timestamp,
                 "correlation_id", :correlation_id, "hop_count", :hop_count,
                 "priority", :priority, "metadata", :metadata])
  end
  
  defp extract_source_domain(%{"source_domain" => domain}) when is_binary(domain), do: domain
  defp extract_source_domain(%{source_domain: domain}) when is_binary(domain), do: domain  
  defp extract_source_domain(%{"from_domain" => domain}) when is_binary(domain), do: domain
  defp extract_source_domain(%{from_domain: domain}) when is_binary(domain), do: domain
  defp extract_source_domain(%{"from" => domain}) when is_binary(domain), do: domain
  defp extract_source_domain(%{from: domain}) when is_binary(domain), do: domain
  defp extract_source_domain(_), do: "unknown"
  
  defp extract_target_domain(%{"target_domain" => domain}) when is_binary(domain), do: domain
  defp extract_target_domain(%{target_domain: domain}) when is_binary(domain), do: domain
  defp extract_target_domain(%{"to_domain" => domain}) when is_binary(domain), do: domain  
  defp extract_target_domain(%{to_domain: domain}) when is_binary(domain), do: domain
  defp extract_target_domain(%{"to" => domain}) when is_binary(domain), do: domain
  defp extract_target_domain(%{to: domain}) when is_binary(domain), do: domain
  defp extract_target_domain(_), do: "broadcast"
  
  defp extract_timestamp(%{"timestamp" => ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp extract_timestamp(%{timestamp: %DateTime{} = dt}), do: dt
  defp extract_timestamp(%{"timestamp" => %DateTime{} = dt}), do: dt
  defp extract_timestamp(_), do: DateTime.utc_now()
  
  defp extract_correlation_id(%{"correlation_id" => id}) when is_binary(id), do: id
  defp extract_correlation_id(%{correlation_id: id}) when is_binary(id), do: id
  defp extract_correlation_id(_), do: generate_correlation_id()
  
  defp extract_hop_count(%{"hop_count" => count}) when is_integer(count) and count >= 0, do: count
  defp extract_hop_count(%{hop_count: count}) when is_integer(count) and count >= 0, do: count
  defp extract_hop_count(_), do: 0
  
  defp extract_priority(%{"priority" => "low"}), do: :low
  defp extract_priority(%{"priority" => "normal"}), do: :normal  
  defp extract_priority(%{"priority" => "high"}), do: :high
  defp extract_priority(%{"priority" => "critical"}), do: :critical
  defp extract_priority(%{priority: priority}) when priority in [:low, :normal, :high, :critical], do: priority
  defp extract_priority(_), do: :normal
  
  defp extract_metadata(%{"metadata" => meta}) when is_map(meta), do: meta
  defp extract_metadata(%{metadata: meta}) when is_map(meta), do: meta
  defp extract_metadata(_), do: %{}
  
  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end