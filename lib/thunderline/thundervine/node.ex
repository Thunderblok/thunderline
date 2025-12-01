defmodule Thunderline.Thundervine.Node do
  @moduledoc """
  Task node wrapper in a behavior DAG.

  Nodes represent individual execution units that can be:
  - `:thunderpac` - A Thunderpac state machine
  - `:ml_model` - An ML model inference task
  - `:action` - A custom action handler
  - `:subgraph` - A nested Graph (composition)

  ## Creating Nodes

      # Thunderpac FSM node
      node = Node.new("decide", :thunderpac, %{fsm: MyFSM, initial_state: :idle})

      # ML model node
      node = Node.new("classify", :ml_model, %{model: "sentiment_classifier"})

      # Action handler node
      node = Node.new("notify", :action, %{handler: NotificationHandler})

      # Subgraph node (composition)
      node = Node.new("preprocess", :subgraph, %{graph: preprocessing_graph})

  ## Configuration

      node = Node.new("step", :action, %{handler: MyHandler},
        timeout_ms: 5000,
        retry_policy: {:max_attempts, 3}
      )
  """

  @enforce_keys [:id, :name, :type]
  defstruct [
    :id,
    :name,
    :type,
    :task_ref,
    config: %{},
    timeout_ms: 30_000,
    retry_policy: :no_retry,
    metadata: %{}
  ]

  @type node_type :: :thunderpac | :ml_model | :action | :subgraph
  @type retry_policy :: :no_retry | {:max_attempts, pos_integer()}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: node_type(),
          task_ref: term(),
          config: map(),
          timeout_ms: pos_integer(),
          retry_policy: retry_policy(),
          metadata: map()
        }

  @valid_types [:thunderpac, :ml_model, :action, :subgraph]

  @doc """
  Creates a new node with the given name and type.

  ## Parameters

  - `name` - Human-readable name for the node
  - `type` - One of `:thunderpac`, `:ml_model`, `:action`, `:subgraph`
  - `config` - Type-specific configuration map

  ## Options

  - `:id` - Custom ID (default: generated)
  - `:timeout_ms` - Execution timeout in milliseconds (default: 30000)
  - `:retry_policy` - `:no_retry` or `{:max_attempts, n}` (default: `:no_retry`)
  - `:task_ref` - Reference to task implementation
  - `:metadata` - Additional metadata

  ## Examples

      iex> node = Node.new("detect", :ml_model, %{model: "classifier"})
      iex> node.type
      :ml_model
  """
  @spec new(String.t(), node_type(), map(), keyword()) :: t()
  def new(name, type, config \\ %{}, opts \\ []) when type in @valid_types do
    %__MODULE__{
      id: opts[:id] || generate_id(name),
      name: name,
      type: type,
      task_ref: opts[:task_ref],
      config: config,
      timeout_ms: opts[:timeout_ms] || 30_000,
      retry_policy: opts[:retry_policy] || :no_retry,
      metadata: opts[:metadata] || %{}
    }
  end

  @doc """
  Creates a Thunderpac FSM node.
  """
  @spec thunderpac(String.t(), module() | atom(), keyword()) :: t()
  def thunderpac(name, fsm_module, opts \\ []) do
    config = %{
      fsm: fsm_module,
      initial_state: opts[:initial_state]
    }

    new(name, :thunderpac, config, opts)
  end

  @doc """
  Creates an ML model inference node.
  """
  @spec ml_model(String.t(), String.t(), keyword()) :: t()
  def ml_model(name, model_id, opts \\ []) do
    config = %{
      model: model_id,
      preprocessing: opts[:preprocessing],
      postprocessing: opts[:postprocessing]
    }

    new(name, :ml_model, config, opts)
  end

  @doc """
  Creates an action handler node.
  """
  @spec action(String.t(), module(), keyword()) :: t()
  def action(name, handler_module, opts \\ []) do
    config = %{
      handler: handler_module,
      args: opts[:args] || []
    }

    new(name, :action, config, opts)
  end

  @doc """
  Creates a subgraph node (nested graph composition).
  """
  @spec subgraph(String.t(), term(), keyword()) :: t()
  def subgraph(name, graph, opts \\ []) do
    config = %{
      graph: graph
    }

    new(name, :subgraph, config, opts)
  end

  @doc """
  Updates node configuration.
  """
  @spec update_config(t(), map()) :: t()
  def update_config(%__MODULE__{} = node, updates) do
    %{node | config: Map.merge(node.config, updates)}
  end

  @doc """
  Updates node metadata.
  """
  @spec update_metadata(t(), map()) :: t()
  def update_metadata(%__MODULE__{} = node, updates) do
    %{node | metadata: Map.merge(node.metadata, updates)}
  end

  @doc """
  Sets the timeout for node execution.
  """
  @spec with_timeout(t(), pos_integer()) :: t()
  def with_timeout(%__MODULE__{} = node, timeout_ms) when timeout_ms > 0 do
    %{node | timeout_ms: timeout_ms}
  end

  @doc """
  Sets the retry policy for node execution.
  """
  @spec with_retry(t(), retry_policy()) :: t()
  def with_retry(%__MODULE__{} = node, :no_retry), do: %{node | retry_policy: :no_retry}

  def with_retry(%__MODULE__{} = node, {:max_attempts, n}) when is_integer(n) and n > 0 do
    %{node | retry_policy: {:max_attempts, n}}
  end

  @doc """
  Checks if the node is a leaf type (no nested execution).
  """
  @spec leaf?(t()) :: boolean()
  def leaf?(%__MODULE__{type: :subgraph}), do: false
  def leaf?(%__MODULE__{}), do: true

  @doc """
  Serializes the node to a map for persistence.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = node) do
    %{
      id: node.id,
      name: node.name,
      type: node.type,
      task_ref: serialize_task_ref(node.task_ref),
      config: serialize_config(node.config),
      timeout_ms: node.timeout_ms,
      retry_policy: serialize_retry_policy(node.retry_policy),
      metadata: node.metadata
    }
  end

  @doc """
  Deserializes a node from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: map.id || map["id"],
      name: map.name || map["name"],
      type: parse_type(map.type || map["type"]),
      task_ref: deserialize_task_ref(map[:task_ref] || map["task_ref"]),
      config: map.config || map["config"] || %{},
      timeout_ms: map[:timeout_ms] || map["timeout_ms"] || 30_000,
      retry_policy: deserialize_retry_policy(map[:retry_policy] || map["retry_policy"]),
      metadata: map[:metadata] || map["metadata"] || %{}
    }
  end

  # Private helpers

  defp generate_id(name) do
    slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{slug}_#{suffix}"
  end

  defp serialize_task_ref(nil), do: nil
  defp serialize_task_ref(module) when is_atom(module), do: to_string(module)
  defp serialize_task_ref(other), do: inspect(other)

  defp deserialize_task_ref(nil), do: nil
  defp deserialize_task_ref("Elixir." <> _ = str), do: String.to_existing_atom(str)
  defp deserialize_task_ref(str) when is_binary(str), do: str
  defp deserialize_task_ref(other), do: other

  defp serialize_config(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when is_atom(v) -> {k, to_string(v)}
      {k, v} -> {k, v}
    end)
  end

  defp serialize_retry_policy(:no_retry), do: "no_retry"
  defp serialize_retry_policy({:max_attempts, n}), do: %{"max_attempts" => n}

  defp deserialize_retry_policy("no_retry"), do: :no_retry
  defp deserialize_retry_policy(:no_retry), do: :no_retry
  defp deserialize_retry_policy(nil), do: :no_retry
  defp deserialize_retry_policy(%{"max_attempts" => n}), do: {:max_attempts, n}
  defp deserialize_retry_policy(%{max_attempts: n}), do: {:max_attempts, n}

  defp parse_type(type) when is_atom(type), do: type
  defp parse_type(type) when is_binary(type), do: String.to_existing_atom(type)
end
