defmodule Thunderline.Thundergrid.Prism.MLTap do
  @moduledoc """
  Asynchronous ML logging tap for the Prism DAG scratchpad.

  Consolidated from Thunderprism.MLTap into Thundergrid.Prism.

  MLTap provides non-blocking writes to PrismNode and PrismEdge resources,
  allowing the ML inference pipeline to continue without waiting for database I/O.

  ## Design Philosophy

  - **Never block the inference path** — All writes happen asynchronously
  - **Fire-and-forget with monitoring** — Emit telemetry but don't crash on failure
  - **Graceful degradation** — If logging fails, the ML pipeline continues

  ## Telemetry Events

  - `[:thundergrid, :prism, :mltap, :log_start]` — Log initiated
  - `[:thundergrid, :prism, :mltap, :log_success]` — Log completed
  - `[:thundergrid, :prism, :mltap, :log_error]` — Log failed
  """

  alias Thunderline.Thundergrid.Prism.{PrismNode, PrismEdge}
  require Logger

  @doc """
  Asynchronously log a model selection as a PrismNode.

  ## Parameters

  - `attrs` - Map containing:
    - `:pac_id` (required) — Identifier for the PAC/controller
    - `:iteration` (required) — Iteration number
    - `:chosen_model` (required) — Model that was selected
    - `:model_probabilities` — Map of model probabilities
    - `:model_distances` — Map of model distances
    - `:timestamp` — When the selection occurred
    - `:meta` — Additional metadata

  ## Returns

  Returns a Task struct immediately. The actual database write happens
  asynchronously in a separate process.
  """
  @spec log_node(map()) :: Task.t()
  def log_node(attrs) when is_map(attrs) do
    Task.async(fn ->
      start_time = System.monotonic_time(:microsecond)

      :telemetry.execute(
        [:thundergrid, :prism, :mltap, :log_start],
        %{timestamp: start_time},
        %{type: :node, pac_id: attrs[:pac_id]}
      )

      try do
        attrs_with_defaults =
          attrs
          |> Map.put_new_lazy(:timestamp, fn -> DateTime.utc_now() end)
          |> Map.put_new(:model_probabilities, %{})
          |> Map.put_new(:model_distances, %{})
          |> Map.put_new(:meta, %{})
          |> Map.update(:chosen_model, "", &to_string/1)

        case Ash.create(PrismNode, attrs_with_defaults, action: :create) do
          {:ok, node} ->
            duration = System.monotonic_time(:microsecond) - start_time

            :telemetry.execute(
              [:thundergrid, :prism, :mltap, :log_success],
              %{duration_us: duration},
              %{type: :node, node_id: node.id, pac_id: attrs[:pac_id]}
            )

            {:ok, node}

          {:error, error} ->
            duration = System.monotonic_time(:microsecond) - start_time

            :telemetry.execute(
              [:thundergrid, :prism, :mltap, :log_error],
              %{duration_us: duration},
              %{type: :node, error: inspect(error), pac_id: attrs[:pac_id]}
            )

            Logger.warning("[MLTap] node creation failed: #{inspect(error)}")
            {:error, error}
        end
      rescue
        exception ->
          duration = System.monotonic_time(:microsecond) - start_time

          :telemetry.execute(
            [:thundergrid, :prism, :mltap, :log_error],
            %{duration_us: duration},
            %{type: :node, error: Exception.message(exception), pac_id: attrs[:pac_id]}
          )

          Logger.error("[MLTap] node creation exception: #{Exception.message(exception)}")
          {:error, exception}
      end
    end)
  end

  @doc """
  Asynchronously log an edge connection between two PrismNodes.

  ## Parameters

  - `attrs` - Map containing:
    - `:from_id` (required) — Source node UUID
    - `:to_id` (required) — Target node UUID
    - `:relation_type` — Type of relationship (default: "sequential")
    - `:meta` — Additional metadata
  """
  @spec log_edge(map()) :: Task.t()
  def log_edge(attrs) when is_map(attrs) do
    Task.async(fn ->
      start_time = System.monotonic_time(:microsecond)

      :telemetry.execute(
        [:thundergrid, :prism, :mltap, :log_start],
        %{timestamp: start_time},
        %{type: :edge, from_id: attrs[:from_id], to_id: attrs[:to_id]}
      )

      try do
        attrs_with_defaults =
          attrs
          |> Map.put_new(:relation_type, "sequential")
          |> Map.put_new(:meta, %{})

        case Ash.create(PrismEdge, attrs_with_defaults, action: :create) do
          {:ok, edge} ->
            duration = System.monotonic_time(:microsecond) - start_time

            :telemetry.execute(
              [:thundergrid, :prism, :mltap, :log_success],
              %{duration_us: duration},
              %{type: :edge, edge_id: edge.id}
            )

            {:ok, edge}

          {:error, error} ->
            duration = System.monotonic_time(:microsecond) - start_time

            :telemetry.execute(
              [:thundergrid, :prism, :mltap, :log_error],
              %{duration_us: duration},
              %{type: :edge, error: inspect(error)}
            )

            Logger.warning("[MLTap] edge creation failed: #{inspect(error)}")
            {:error, error}
        end
      rescue
        exception ->
          duration = System.monotonic_time(:microsecond) - start_time

          :telemetry.execute(
            [:thundergrid, :prism, :mltap, :log_error],
            %{duration_us: duration},
            %{type: :edge, error: Exception.message(exception)}
          )

          Logger.error("[MLTap] edge creation exception: #{Exception.message(exception)}")
          {:error, exception}
      end
    end)
  end

  @doc """
  Log both a node and optionally create an edge from a previous node.
  """
  @spec log_with_edge(map(), String.t() | nil) :: {:ok, Task.t()}
  def log_with_edge(node_attrs, prev_node_id \\ nil) do
    task =
      Task.async(fn ->
        case Task.await(log_node(node_attrs), :infinity) do
          {:ok, node} ->
            if prev_node_id do
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
