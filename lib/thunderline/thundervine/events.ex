defmodule Thunderline.Thundervine.Events do
  @moduledoc """
  Thundervine event helpers: persist parsed rules & workflow specs into DAG resources
  and emit lineage commit events.

  This module centralizes DAG write patterns so ingestion & future agent planners
  share the same durability semantics.
  """
  require Logger
  alias Thunderline.Thunderblock.Resources.{DAGWorkflow, DAGNode, DAGEdge}

  # Ensure or start a workflow anchored on correlation id (one workflow per run id)
  def ensure_workflow(%{correlation_id: corr} = meta, root_name \\ "ca.session") do
    case Ash.get(DAGWorkflow, {:unique_correlation, %{correlation_id: corr}}) do
      {:ok, wf} -> {:ok, wf}
      {:error, _} ->
        DAGWorkflow
        |> Ash.Changeset.for_create(:start, %{
          source_domain: Map.get(meta, :source_domain, :bolt),
          root_event_name: root_name,
          correlation_id: corr,
          causation_id: Map.get(meta, :causation_id),
          metadata: Map.get(meta, :metadata, %{})
        })
        |> Ash.create()
    end
  end

  def rule_parsed(rule, meta) do
    meta = normalize_meta(meta)
    with {:ok, wf} <- ensure_workflow(meta, "ca.rule"),
         {:ok, node} <- create_node(wf, "evt.action.ca.rule_parsed", rule, meta),
         :ok <- maybe_edge(wf, node) do
      publish_dag_commit(wf, node, meta)
      {:ok, {wf, node}}
    end
  end

  def workflow_spec_parsed(%{name: name} = spec, meta) do
    meta = normalize_meta(meta)
    with {:ok, wf} <- ensure_workflow(meta, name),
         {:ok, node} <- create_node(wf, "workflow.spec", spec, meta),
         :ok <- maybe_edge(wf, node) do
      publish_dag_commit(wf, node, meta)
      {:ok, {wf, node}}
    end
  end

  defp create_node(wf, event_name, payload, meta) do
    DAGNode
    |> Ash.Changeset.for_create(:record_start, %{
      workflow_id: wf.id,
      event_name: event_name,
      correlation_id: meta.correlation_id,
      causation_id: Map.get(meta, :causation_id),
      payload: Map.take(payload |> Map.from_struct(), [:born, :survive, :rate_hz, :seed, :zone]) |> Enum.reject(&match?({_k, nil}, &1)) |> Map.new()
    })
    |> Ash.create()
  end

  # Create an edge from the previous node if one exists (serial lineage).
  defp maybe_edge(wf, node) do
    prev_id = get_prev_node_id(wf)
    _ = persist_last_node_id(wf, node.id)
    if prev_id && prev_id != node.id do
      DAGEdge
      |> Ash.Changeset.for_create(:create, %{
        workflow_id: wf.id,
        from_node_id: prev_id,
        to_node_id: node.id,
        edge_type: :causal
      })
      |> Ash.create()
      :ok
    else
      :ok
    end
  rescue
    e -> Logger.warning("edge_creation_failed=#{inspect(e)} wf=#{wf.id} node=#{node.id}"); :ok
  end

  # Simple in-memory ETS cache for latest node per workflow (avoids extra DB query)
  @edge_cache :vine_edge_cache
  defp ensure_cache do
    case :ets.whereis(@edge_cache) do
      :undefined -> :ets.new(@edge_cache, [:named_table, :public, :set, read_concurrency: true]); :ok
      _ -> :ok
    end
  end
  defp store_ephemeral(wf_id, node_id) do
    ensure_cache(); :ets.insert(@edge_cache, {wf_id, node_id}); :ok
  end

  defp persist_last_node_id(wf, node_id) do
    store_ephemeral(wf.id, node_id)
    meta = Map.get(wf, :metadata, %{})
    # Only write if changed to avoid churn
    if Map.get(meta, "last_node_id") != node_id do
      new_meta = Map.put(meta, "last_node_id", node_id)
      case Ash.Changeset.for_update(wf, :update_metadata, %{metadata: new_meta}) |> Ash.update() do
        {:ok, _} -> :ok
        {:error, err} -> Logger.warning("persist_last_node_id_failed=#{inspect(err)} wf=#{wf.id}")
      end
    end
    :ok
  end

  defp get_prev_node_id(wf) do
    ensure_cache()
    case :ets.lookup(@edge_cache, wf.id) do
      [{_kf, id}] -> id
      _ ->
        # fallback to workflow metadata (DB) if available
        case Ash.get(DAGWorkflow, wf.id) do
          {:ok, fresh} ->
            id = get_in(fresh.metadata, ["last_node_id"])
            if id, do: store_ephemeral(fresh.id, id)
            id
          _ -> nil
        end
    end
  end

  defp publish_dag_commit(wf, node, meta) do
    payload = %{workflow_id: wf.id, node_id: node.id, correlation_id: meta.correlation_id}
    case Thunderline.Event.new(name: "dag.commit", source: :flow, payload: payload) do
      {:ok, ev} -> _ = Thunderline.EventBus.emit(ev); :ok
      {:error, err} -> Logger.warning("Failed to build dag.commit event: #{inspect(err)}")
    end
  end

  defp normalize_meta(meta) when is_map(meta) do
    Map.merge(%{correlation_id: meta[:correlation_id] || gen_corr()}, meta)
  end
  defp normalize_meta(_), do: %{correlation_id: gen_corr()}

  defp gen_corr, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
