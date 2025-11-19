defmodule Thunderline.Event do
  @moduledoc """
  Canonical event struct & constructor aligned with `EVENT_TAXONOMY.md`.

  Backwards compatibility: legacy fields (`type`, `source_domain`, `target_domain`, `timestamp`)
  retained for existing pipelines while the new taxonomy envelope (`id`, `at`, `name`, `source`,
  `actor`, `taxonomy_version`, `event_version`, `meta`, `causation_id`) is phased in.

  Smart constructor `new/1` produces a normalized %Thunderline.Event{} enforcing basic
  taxonomy rules (name format, allowed category per source domain, correlation / causation threading).

  Minimum required input keys (map or keyword):
    * :name (string) OR :type (atom)  (if only :type given, name inferred as "system.unknown.<type>")
    * :payload (map)
    * :source (atom domain) OR legacy :source_domain (string)

  Optional keys:
    * :actor  - map with :id and :type
    * :correlation_id
    * :causation_id
    * :event_version (default 1)
    * :taxonomy_version (default 1)
    * :priority (legacy priority still honored)
    * :meta (map)

  NOTE: UUID v7 not yet supplied by dependencies; v4 used as interim (TODO: replace when lib available).
  """

  @type priority :: :low | :normal | :high | :critical

  @type t :: %__MODULE__{
          # Legacy pipeline fields
          type: atom() | nil,
          source_domain: String.t() | nil,
          target_domain: String.t(),
          timestamp: DateTime.t(),
          correlation_id: String.t(),
          hop_count: non_neg_integer(),
          priority: priority(),
          metadata: map(),
          # Taxonomy envelope fields
          id: String.t(),
          at: DateTime.t(),
          name: String.t(),
          source: atom(),
          actor: map() | nil,
          causation_id: String.t() | nil,
          taxonomy_version: pos_integer(),
          event_version: pos_integer(),
          meta: map(),
          payload: map()
        }

  @enforce_keys [:payload, :name, :source]
  defstruct [
    # taxonomy envelope
    :id,
    :at,
    :name,
    :source,
    :actor,
    :causation_id,
    :taxonomy_version,
    :event_version,
    :meta,
    # legacy
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
  Smart constructor for taxonomy events.

  Example:
      iex> Thunderline.Event.new(name: "system.email.sent", source: :link, payload: %{message_id: "m1"})
      {:ok, %Thunderline.Event{...}}
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, [term()]}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(%{} = attrs) do
    errors = []
    name = attrs[:name] || infer_name_from_type(attrs[:type])
    payload = attrs[:payload]
    source = attrs[:source] || infer_source(attrs[:source_domain])
    actor = attrs[:actor]
    correlation_id = attrs[:correlation_id] || gen_corr()
    causation_id = attrs[:causation_id]
    taxonomy_version = attrs[:taxonomy_version] || 1
    event_version = attrs[:event_version] || 1
    priority = attrs[:priority] || :normal
    # If name is nil we still build meta with default reliability; validator will add error
    meta = Map.merge(%{reliability: infer_reliability(name)}, Map.get(attrs, :meta, %{}))

    errors =
      errors
      |> maybe_error(name == nil, {:missing, :name})
      |> maybe_error(!is_map(payload), {:invalid, :payload})
      |> maybe_error(!is_atom(source), {:invalid, :source})
      |> maybe_error(!valid_name?(name), {:invalid_format, name})
      |> maybe_error(!category_allowed?(source, name), {:forbidden_category, {source, name}})

    if errors == [] do
      now = DateTime.utc_now()

      event = %__MODULE__{
        id: gen_uuid(),
        at: now,
        name: name,
        source: source,
        actor: actor,
        causation_id: causation_id,
        taxonomy_version: taxonomy_version,
        event_version: event_version,
        meta: meta,
        # legacy compatibility
        type: attrs[:type] || name_to_type(name),
        payload: payload,
        source_domain: attrs[:source_domain] || Atom.to_string(source),
        target_domain: attrs[:target_domain] || "broadcast",
        timestamp: now,
        correlation_id: correlation_id,
        hop_count: attrs[:hop_count] || 0,
        priority: priority,
        metadata: Map.get(attrs, :metadata, %{})
      }

      {:ok, event}
    else
      {:error, errors}
    end
  end

  @doc "Raise version of new/1"
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ev} -> ev
      {:error, errs} -> raise ArgumentError, "Invalid event attrs: #{inspect(errs)}"
    end
  end

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
      type = extract_type(event)
      payload = extract_payload(event)
      source_domain = extract_source_domain(event)
      target_domain = extract_target_domain(event)
      timestamp = extract_timestamp(event)
      correlation_id = extract_correlation_id(event)
      hop_count = extract_hop_count(event)
      priority = extract_priority(event)
      metadata = extract_metadata(event)

      # Taxonomy fields (best-effort inference for legacy events)
      name = Map.get(event, :name) || Map.get(event, "name") || infer_name_from_type(type)
      source = Map.get(event, :source) || Map.get(event, "source") || infer_source(source_domain)
      now = DateTime.utc_now()

      normalized = %__MODULE__{
        # taxonomy envelope
        id: gen_uuid(),
        at: now,
        name: name,
        source: source,
        actor: Map.get(event, :actor) || Map.get(event, "actor"),
        causation_id: Map.get(event, :causation_id) || Map.get(event, "causation_id"),
        taxonomy_version:
          Map.get(event, :taxonomy_version) || Map.get(event, "taxonomy_version") || 1,
        event_version: Map.get(event, :event_version) || Map.get(event, "event_version") || 1,
        meta: Map.get(event, :meta) || Map.get(event, "meta") || %{},
        # legacy & common
        type: type,
        payload: payload,
        source_domain: source_domain,
        target_domain: target_domain,
        timestamp: timestamp || now,
        correlation_id: correlation_id,
        hop_count: hop_count,
        priority: priority,
        metadata: metadata
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
      "id" => event.id,
      "at" => DateTime.to_iso8601(event.at),
      "name" => event.name,
      "source" => to_string(event.source),
      "actor" => event.actor,
      "taxonomy_version" => event.taxonomy_version,
      "event_version" => event.event_version,
      "payload" => event.payload,
      "meta" => event.meta,
      # legacy for transition
      "type" => event.type && to_string(event.type),
      "source_domain" => event.source_domain,
      "target_domain" => event.target_domain,
      "timestamp" => DateTime.to_iso8601(event.timestamp),
      "correlation_id" => event.correlation_id,
      "causation_id" => event.causation_id,
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
  def high_priority?(%__MODULE__{priority: priority}) when priority in [:high, :critical],
    do: true

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
    |> Map.drop([
      "type",
      "event_type",
      :type,
      "source_domain",
      :source_domain,
      "target_domain",
      :target_domain,
      "timestamp",
      :timestamp,
      "correlation_id",
      :correlation_id,
      "hop_count",
      :hop_count,
      "priority",
      :priority,
      "metadata",
      :metadata
    ])
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

  defp extract_priority(%{priority: priority}) when priority in [:low, :normal, :high, :critical],
    do: priority

  defp extract_priority(_), do: :normal

  defp extract_metadata(%{"metadata" => meta}) when is_map(meta), do: meta
  defp extract_metadata(%{metadata: meta}) when is_map(meta), do: meta
  defp extract_metadata(_), do: %{}

  defp generate_correlation_id do
    # UUID v7 provides sortable time component aiding ingestion ordering & tracing cohesion.
    Thunderline.UUID.v7()
  end

  # Smart constructor helpers
  defp maybe_error(list, true, err), do: [err | list]
  defp maybe_error(list, false, _), do: list

  defp infer_source(nil), do: :unknown
  defp infer_source(str) when is_binary(str), do: String.to_atom(str)

  defp valid_name?(name) when is_binary(name) do
    String.split(name, ".") |> length() >= 2
  end

  defp valid_name?(_), do: false

  @allowed_categories_by_domain %{
    gate: ["ui.command", "system", "presence"],
    flow: ["flow.reactor", "system", "ai"],
    bolt: ["ml.run", "ml.trial", "system", "ai"],
    link: ["ui.command", "system", "ai"],
    crown: ["ai.intent", "system", "ai"],
    thunderlink: ["cluster.node", "cluster.link", "system"],
    # Block domain intentionally cannot emit ai.intent.* directly
    block: ["system"],
    bridge: ["system", "ui.command", "ai"],
    unknown: ["system", "ai"],
    # Custom evt.* experimental namespaces (tight, explicit allow-list)
    bolt_evt: ["evt.action.ca"]
  }

  defp category_allowed?(source, name) when is_atom(source) and is_binary(name) do
    prefix =
      name
      |> String.split(".")
      |> case do
        [a, b | _] -> a <> "." <> b
        [a] -> a
        _ -> ""
      end

    # Support experimental evt.* taxonomy: treat source :bolt plus evt.* as allowed via bolt_evt mapping
    allowed =
      case {source, String.starts_with?(name, "evt.")} do
        {:bolt, true} ->
          Map.get(@allowed_categories_by_domain, :bolt_evt, []) ++
            Map.get(@allowed_categories_by_domain, source, ["system"])

        _ ->
          Map.get(@allowed_categories_by_domain, source, ["system"])
      end

    # Allow prefix match and exact single category tokens (e.g. "system")
    Enum.any?(allowed, fn cat ->
      cat == prefix or String.starts_with?(prefix, cat) or String.starts_with?(name, cat)
    end)
  end

  defp category_allowed?(_, _), do: true

  defp infer_reliability(nil), do: :transient

  defp infer_reliability(name) when is_binary(name) do
    cond do
      String.starts_with?(name, "system.") -> :persistent
      String.starts_with?(name, "ml.run.") -> :persistent
      true -> :transient
    end
  end

  defp infer_name_from_type(nil), do: nil
  defp infer_name_from_type(type) when is_atom(type), do: "system.unknown." <> to_string(type)

  defp name_to_type(name) when is_binary(name) do
    name
    |> String.split(".")
    |> List.last()
    |> String.to_atom()
  rescue
    _ -> :unknown_event
  end

  defp gen_uuid, do: Thunderline.UUID.v7()
  defp gen_corr, do: Thunderline.UUID.v7()
end
