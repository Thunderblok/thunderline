defmodule ThunderlineTest.TenancyPolicyTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Markets.RawTick
  alias Thunderline.Features.FeatureWindow
  alias Thunderline.MoE.{Expert, DecisionTrace}
  alias Thunderline.Export.TrainingSlice
  alias Thunderline.Lineage.Edge

  setup do
    actor_a = %{id: Ecto.UUID.generate(), tenant_id: Ecto.UUID.generate()}
    actor_b = %{id: Ecto.UUID.generate(), tenant_id: Ecto.UUID.generate()}
    {:ok, actor_a: actor_a, actor_b: actor_b}
  end

  describe "Tenancy Policy Tests" do
    test "same-tenant create & read succeeds" , %{actor_a: actor} do
      {:ok, tick} = RawTick.ingest(%{tenant_id: actor.tenant_id, symbol: "AAPL", ts: 1_000_000, payload: %{}, vendor_seq: 1}, actor: actor)
      assert tick.tenant_id == actor.tenant_id

      assert {:ok, [_]} = RawTick.read(actor: actor, filter: [id: tick.id])
    end

    test "cross-tenant read denied", %{actor_a: actor_a, actor_b: actor_b} do
      {:ok, tick} = RawTick.ingest(%{tenant_id: actor_a.tenant_id, symbol: "MSFT", ts: 2_000_000, payload: %{}}, actor: actor_a)
      assert {:error, %Ash.Error.Forbidden{}} = RawTick.read(actor: actor_b, filter: [id: tick.id])
    end

    test "expert tenancy enforced", %{actor_a: actor_a, actor_b: actor_b} do
      {:ok, expert} = Expert.register(%{tenant_id: actor_a.tenant_id, name: "exp", version: "v1", metrics: %{}}, actor: actor_a)
      assert {:error, %Ash.Error.Forbidden{}} = Expert.read(actor: actor_b, filter: [id: expert.id])
    end

    test "decision trace scoped to tenant", %{actor_a: actor} do
      {:ok, fw} = FeatureWindow.ingest_window(%{tenant_id: actor.tenant_id, kind: :market, key: "AAPL", window_start: DateTime.utc_now(), window_end: DateTime.utc_now(), features: %{}, label_spec: %{}, feature_schema_version: 1, provenance: %{}}, actor: actor)
      {:ok, trace} = DecisionTrace.record(%{tenant_id: actor.tenant_id, feature_window_id: fw.id, router_version: "r1", gate_scores: %{}, selected_experts: %{}, actions: %{}, risk_flags: %{}, hash: :crypto.strong_rand_bytes(16)}, actor: actor)
      assert trace.tenant_id == actor.tenant_id
    end

    test "feature window cross-tenant read forbidden", %{actor_a: actor_a, actor_b: actor_b} do
      {:ok, fw} = FeatureWindow.ingest_window(%{tenant_id: actor_a.tenant_id, kind: :market, key: "MSFT", window_start: DateTime.utc_now(), window_end: DateTime.utc_now(), features: %{}, label_spec: %{}, feature_schema_version: 1, provenance: %{}}, actor: actor_a)
      assert {:error, %Ash.Error.Forbidden{}} = FeatureWindow.read(actor: actor_b, filter: [id: fw.id])
    end

    test "lineage edge tenancy enforced", %{actor_a: actor_a, actor_b: actor_b} do
      # Create two artifacts (feature windows) for lineage demonstration
      {:ok, parent_fw} = FeatureWindow.ingest_window(%{tenant_id: actor_a.tenant_id, kind: :market, key: "AAPL", window_start: DateTime.utc_now(), window_end: DateTime.utc_now(), features: %{}, label_spec: %{}, feature_schema_version: 1, provenance: %{}}, actor: actor_a)
      {:ok, child_fw} = FeatureWindow.ingest_window(%{tenant_id: actor_a.tenant_id, kind: :market, key: "AAPL", window_start: DateTime.utc_now(), window_end: DateTime.utc_now(), features: %{}, label_spec: %{}, feature_schema_version: 1, provenance: %{}}, actor: actor_a)
      {:ok, edge} = Edge.connect(%{tenant_id: actor_a.tenant_id, from_id: parent_fw.id, to_id: child_fw.id, edge_type: "derives", day_bucket: Date.utc_today()}, actor: actor_a)
      assert edge.tenant_id == actor_a.tenant_id
      assert {:error, %Ash.Error.Forbidden{}} = Edge.read(actor: actor_b, filter: [id: edge.id])
    end

    test "export job isolated", %{actor_a: actor_a, actor_b: actor_b} do
      {:ok, job} = TrainingSlice.enqueue(%{tenant_id: actor_a.tenant_id, slice_spec: %{}}, actor: actor_a)
      assert {:error, %Ash.Error.Forbidden{}} = TrainingSlice.read(actor: actor_b, filter: [id: job.id])
    end
  end
end
