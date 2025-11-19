defmodule Thunderline.Thunderprism.MLTap do
  @moduledoc """
  Asynchronous ML logging tap for the Thunderprism DAG scratchpad.

  MLTap provides non-blocking writes to PrismNode and PrismEdge resources,
  allowing the ML inference pipeline to continue without waiting for database I/O.

  ## Design Philosophy

  - **Never block the inference path** - All writes happen asynchronously
  - **Fire-and-forget with monitoring** - Emit telemetry but don't crash on failure
  - **Graceful degradation** - If logging fails, the ML pipeline continues

  ## Usage

      # In ModelSelectionConsumer after successful model selection
      selection_data = %{
        pac_id: "ml_controller_1",
        iteration: 42,
        chosen_model: :model_a,
        model_probabilities: %{model_a: 0.65, model_b: 0.35},
        model_distances: %{model_a: 0.023, model_b: 0.045},
        timestamp: DateTime.utc_now()
      }

      MLTap.log_node(selection_data)

  ## Telemetry Events

  - `[:thunderline, :thunderprism, :mltap, :log_start]` - Log initiated
  - `[:thunderline, :thunderprism, :mltap, :log_success]` - Log completed
  - `[:thunderline, :thunderprism, :mltap, :log_error]` - Log failed

  ## Error Handling

  Errors are logged but do not propagate to the caller. This ensures
  the ML pipeline remains resilient to logging failures.
  """

  alias Thunderline.Thunderprism.Domain
  require Logger

  @doc """
  Asynchronously log a model selection as a PrismNode.

  ## Parameters

  - `attrs` - Map containing:
    - `:pac_id` (required) - Identifier for the PAC/controller
    - `:iteration` (required) - Iteration number
    - `:chosen_model` (required) - Model that was selected
    - `:model_probabilities` - Map of model probabilities
    - `:model_distances` - Map of model distances
    - `:timestamp` - When the selection occurred
    - `:meta` - Additional metadata

  ## Returns

  Returns a Task struct immediately. The actual database write happens
  asynchronously in a separate process.

  ## Examples

      MLTap.log_node(%{
        pac_id: "controller_1",
        iteration: 10,
        chosen_model: :model_a,
        model_probabilities: %{model_a: 0.7, model_b: 0.3},
        timestamp: DateTime.utc_now()
      })
  """
  @spec log_node(map()) :: Task.t()
  def log_node(attrs) when is_map(attrs) do
    Task.async(fn ->
      start_time = System.monotonic_time(:microsecond)

      :telemetry.execute(
        [:thunderline, :thunderprism, :mltap, :log_start],
        %{timestamp: start_time},
        %{type: :node, pac_id: attrs[:pac_id]}
      )

      try do
        # Ensure timestamp exists
        attrs_with_timestamp =
          Map.put_new_lazy(attrs, :timestamp, fn -> DateTime.utc_now() end)

        # Create PrismNode via Ash domain (! version returns node directly or raises)
        node = Domain.create_prism_node!(
          attrs_with_timestamp.pac_id,
          attrs_with_timestamp.iteration,
          attrs_with_timestamp.chosen_model,
          attrs_with_timestamp.model_probabilities || %{},
          attrs_with_timestamp.model_distances || %{},
          Map.get(attrs_with_timestamp, :meta, %{}),
          attrs_with_timestamp.timestamp
        )

        duration = System.monotonic_time(:microsecond) - start_time

        :telemetry.execute(
          [:thunderline, :thunderprism, :mltap, :log_success],
          %{duration_us: duration},
          %{type: :node, node_id: node.id, pac_id: attrs[:pac_id]}
        )

        {:ok, node}
      rescue
        exception ->
          duration = System.monotonic_time(:microsecond) - start_time

          :telemetry.execute(
            [:thunderline, :thunderprism, :mltap, :log_error],
            %{duration_us: duration},
            %{type: :node, error: Exception.message(exception), pac_id: attrs[:pac_id]}
          )

          Logger.error("MLTap node creation exception",
            exception: Exception.format(:error, exception, __STACKTRACE__),
            pac_id: attrs[:pac_id]
          )

          {:error, exception}
      end
    end)
  end

  @doc """
  Asynchronously log an edge connection between two PrismNodes.

  ## Parameters

  - `attrs` - Map containing:
    - `:from_id` (required) - Source node UUID
    - `:to_id` (required) - Target node UUID
    - `:relation_type` - Type of relationship (default: "sequential")
    - `:meta` - Additional metadata

  ## Returns

  Returns a Task struct immediately.

  ## Examples

      MLTap.log_edge(%{
        from_id: node1.id,
        to_id: node2.id,
        relation_type: "sequential"
      })
  """
  @spec log_edge(map()) :: Task.t()
  def log_edge(attrs) when is_map(attrs) do
    Task.async(fn ->
      start_time = System.monotonic_time(:microsecond)

      :telemetry.execute(
        [:thunderline, :thunderprism, :mltap, :log_start],
        %{timestamp: start_time},
        %{type: :edge, from_id: attrs[:from_id], to_id: attrs[:to_id]}
      )

      try do
        # Set defaults
        relation_type = Map.get(attrs, :relation_type, "sequential")
        meta = Map.get(attrs, :meta, %{})

        # Create PrismEdge via Ash domain (! version returns edge directly or raises)
        edge = Domain.create_prism_edge!(
          attrs.from_id,
          attrs.to_id,
          relation_type,
          meta
        )

        duration = System.monotonic_time(:microsecond) - start_time

        :telemetry.execute(
          [:thunderline, :thunderprism, :mltap, :log_success],
          %{duration_us: duration},
          %{type: :edge, edge_id: edge.id}
        )

        {:ok, edge}
      rescue
        exception ->
          duration = System.monotonic_time(:microsecond) - start_time

          :telemetry.execute(
            [:thunderline, :thunderprism, :mltap, :log_error],
            %{duration_us: duration},
            %{type: :edge, error: Exception.message(exception)}
          )

          Logger.error("MLTap edge creation exception",
            exception: Exception.format(:error, exception, __STACKTRACE__)
          )

          {:error, exception}
      end
    end)
  end

  @doc """
  Log both a node and optionally create an edge from a previous node.

  This is a convenience function for the common pattern of logging a new
  decision and linking it to the previous one in a sequence.

  ## Parameters

  - `node_attrs` - Attributes for the new PrismNode
  - `prev_node_id` - Optional UUID of the previous node to link from

  ## Returns

  `{:ok, task}` - A single task that resolves to:
    - `{:ok, node}` if prev_node_id is nil
    - `{:ok, {node, edge}}` if prev_node_id is provided

  ## Examples

      # First node in sequence
      {:ok, task} = MLTap.log_with_edge(node_attrs, nil)
      {:ok, node} = Task.await(task, 5000)

      # Subsequent nodes with edge
      {:ok, task} = MLTap.log_with_edge(node_attrs, prev_node.id)
      {:ok, {node, edge}} = Task.await(task, 5000)
  """
  @spec log_with_edge(map(), String.t() | nil) :: {:ok, Task.t()}
  def log_with_edge(node_attrs, prev_node_id \\ nil) do
    task =
      Task.async(fn ->
        # First create the node
        case Task.await(log_node(node_attrs), :infinity) do
          {:ok, node} ->
            if prev_node_id do
              # Create edge linking to previous node
              edge_attrs = %{
                from_id: prev_node_id,
                to_id: node.id,
                relation_type: "sequential"
              }

              case Task.await(log_edge(edge_attrs), :infinity) do
                {:ok, edge} -> {:ok, {node, edge}}
                {:error, error} -> {:error, {:edge_creation_failed, error}}
              end
            else
              {:ok, node}
            end

          {:error, error} ->
            {:error, {:node_creation_failed, error}}
        end
      end)

    {:ok, task}
  end
end
