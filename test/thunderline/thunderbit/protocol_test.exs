defmodule Thunderline.Thunderbit.ProtocolTest do
  @moduledoc """
  Unit tests for the Thunderbit Protocol.

  Tests the 7 protocol verbs ensuring:
  - Context threading works correctly
  - Identity preservation in bind
  - Wiring validation in link
  - Proper error handling
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderbit.{Protocol, Context, Edge}

  describe "Context.new/1" do
    test "creates context with session ID" do
      ctx = Context.new()
      assert is_binary(ctx.session_id)
      assert String.length(ctx.session_id) > 0
    end

    test "creates context with pac_id" do
      ctx = Context.new(pac_id: "test-pac")
      assert ctx.pac_id == "test-pac"
    end

    test "creates context with zone" do
      ctx = Context.new(zone: :cortex)
      assert ctx.zone == :cortex
    end

    test "initializes empty bits_by_id" do
      ctx = Context.new()
      assert ctx.bits_by_id == %{}
    end

    test "initializes empty edges" do
      ctx = Context.new()
      assert ctx.edges == []
    end

    test "sets started_at timestamp" do
      ctx = Context.new()
      assert %DateTime{} = ctx.started_at
    end

    test "includes default maxims" do
      ctx = Context.new()
      assert "Primum non nocere" in ctx.active_maxims
    end
  end

  describe "Protocol.spawn_bit/3" do
    test "spawns sensory bit with ctx" do
      ctx = Context.new(pac_id: "test-pac")
      {:ok, bit, new_ctx} = Protocol.spawn_bit(:sensory, %{content: "hello world"}, ctx)

      assert is_binary(bit.id)
      assert bit.category == :sensory
      assert bit.role == :observer
      assert bit.content == "hello world"
      assert new_ctx.session_id == ctx.session_id
    end

    test "spawns cognitive bit with ctx" do
      ctx = Context.new(pac_id: "test-pac")
      {:ok, bit, new_ctx} = Protocol.spawn_bit(:cognitive, %{content: "think about this"}, ctx)

      assert bit.category == :cognitive
      assert bit.role == :transformer
      assert bit.content == "think about this"
      assert new_ctx.session_id == ctx.session_id
    end

    test "registers bit in context" do
      ctx = Context.new()
      {:ok, bit, new_ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      assert Map.has_key?(new_ctx.bits_by_id, bit.id)
      assert new_ctx.bits_by_id[bit.id] == bit
    end

    test "emits bit_spawned event" do
      ctx = Context.new()
      {:ok, bit, new_ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      events = Context.get_events(new_ctx)
      spawn_event = Enum.find(events, &(&1.type == :bit_spawned))

      assert spawn_event != nil
      assert spawn_event.payload.bit_id == bit.id
      assert spawn_event.payload.category == :sensory
    end

    test "assigns default energy and salience" do
      ctx = Context.new()
      {:ok, bit, _ctx} = Protocol.spawn_bit(:cognitive, %{content: "test"}, ctx)

      assert bit.energy == 0.5
      assert bit.salience == 0.5
    end

    test "respects provided energy and salience" do
      ctx = Context.new()
      {:ok, bit, _ctx} = Protocol.spawn_bit(:cognitive, %{content: "test", energy: 0.8, salience: 0.9}, ctx)

      assert bit.energy == 0.8
      assert bit.salience == 0.9
    end

    test "returns error for unknown category" do
      ctx = Context.new()
      result = Protocol.spawn_bit(:unknown_category, %{content: "test"}, ctx)

      assert {:error, :unknown_category} = result
    end

    test "spawns multiple bits with unique IDs" do
      ctx = Context.new()
      {:ok, bit1, ctx} = Protocol.spawn_bit(:sensory, %{content: "first"}, ctx)
      {:ok, bit2, ctx} = Protocol.spawn_bit(:cognitive, %{content: "second"}, ctx)

      assert bit1.id != bit2.id
      assert map_size(ctx.bits_by_id) == 2
    end
  end

  describe "Protocol.bind/3" do
    test "applies continuation to bit" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      {:ok, new_bit, _new_ctx} =
        Protocol.bind(
          bit,
          fn b, c -> {:ok, %{b | content: "modified"}, c} end,
          ctx
        )

      assert new_bit.content == "modified"
    end

    test "preserves bit identity" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)
      original_id = bit.id

      {:ok, new_bit, _ctx} =
        Protocol.bind(
          bit,
          fn b, c -> {:ok, %{b | id: "hacked-id", category: :motor, content: "changed"}, c} end,
          ctx
        )

      # Identity preserved even if continuation tries to change it
      assert new_bit.id == original_id
      assert new_bit.category == :sensory
      assert new_bit.content == "changed"
    end

    test "threads context through continuation" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      {:ok, _new_bit, new_ctx} =
        Protocol.bind(
          bit,
          fn b, c ->
            c = Context.log(c, :info, "bind", "test log")
            {:ok, b, c}
          end,
          ctx
        )

      log = Context.get_log(new_ctx)
      assert length(log) > 0
    end

    test "updates bit in context" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "original"}, ctx)

      {:ok, new_bit, new_ctx} =
        Protocol.bind(
          bit,
          fn b, c -> {:ok, %{b | content: "updated"}, c} end,
          ctx
        )

      stored_bit = Context.get_bit(new_ctx, new_bit.id)
      assert stored_bit.content == "updated"
    end

    test "handles error from continuation" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      result =
        Protocol.bind(
          bit,
          fn _b, _c -> {:error, :something_went_wrong} end,
          ctx
        )

      assert {:error, :something_went_wrong} = result
    end
  end

  describe "Protocol.chain/3" do
    test "chains multiple continuations" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "start"}, ctx)

      {:ok, new_bit, _ctx} =
        Protocol.chain(
          bit,
          [
            fn b, c -> {:ok, %{b | content: b.content <> "-one"}, c} end,
            fn b, c -> {:ok, %{b | content: b.content <> "-two"}, c} end,
            fn b, c -> {:ok, %{b | content: b.content <> "-three"}, c} end
          ],
          ctx
        )

      assert new_bit.content == "start-one-two-three"
    end

    test "halts on first error" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "start"}, ctx)

      result =
        Protocol.chain(
          bit,
          [
            fn b, c -> {:ok, %{b | content: b.content <> "-one"}, c} end,
            fn _b, _c -> {:error, :chain_broken} end,
            fn b, c -> {:ok, %{b | content: b.content <> "-three"}, c} end
          ],
          ctx
        )

      assert {:error, :chain_broken} = result
    end
  end

  describe "Protocol.link/4" do
    test "links two bits with :feeds relation" do
      ctx = Context.new()
      {:ok, sensory, ctx} = Protocol.spawn_bit(:sensory, %{content: "input"}, ctx)
      {:ok, cognitive, ctx} = Protocol.spawn_bit(:cognitive, %{content: "process"}, ctx)

      {:ok, edge, new_ctx} = Protocol.link(sensory, cognitive, :feeds, ctx)

      assert %Edge{} = edge
      assert edge.from_id == sensory.id
      assert edge.to_id == cognitive.id
      assert edge.relation == :feeds
      assert edge.strength == 1.0
    end

    test "registers edge in context" do
      ctx = Context.new()
      {:ok, sensory, ctx} = Protocol.spawn_bit(:sensory, %{content: "input"}, ctx)
      {:ok, cognitive, ctx} = Protocol.spawn_bit(:cognitive, %{content: "process"}, ctx)

      {:ok, edge, new_ctx} = Protocol.link(sensory, cognitive, :feeds, ctx)

      assert length(new_ctx.edges) == 1
      assert hd(new_ctx.edges) == edge
    end

    test "emits bits_linked event" do
      ctx = Context.new()
      {:ok, sensory, ctx} = Protocol.spawn_bit(:sensory, %{content: "input"}, ctx)
      {:ok, cognitive, ctx} = Protocol.spawn_bit(:cognitive, %{content: "process"}, ctx)

      {:ok, edge, new_ctx} = Protocol.link(sensory, cognitive, :feeds, ctx)

      events = Context.get_events(new_ctx)
      link_event = Enum.find(events, &(&1.type == :bits_linked))

      assert link_event != nil
      assert link_event.payload.from_id == sensory.id
      assert link_event.payload.to_id == cognitive.id
      assert link_event.payload.relation == :feeds
      assert link_event.payload.edge_id == edge.id
    end

    test "validates wiring rules" do
      ctx = Context.new()
      {:ok, motor, ctx} = Protocol.spawn_bit(:motor, %{content: "action"}, ctx)
      {:ok, sensory, ctx} = Protocol.spawn_bit(:sensory, %{content: "input"}, ctx)

      # motor -> sensory is not allowed by default wiring matrix
      result = Protocol.link(motor, sensory, :feeds, ctx)

      assert {:error, {:invalid_wiring, _, _}} = result
    end

    test "creates multiple edges" do
      ctx = Context.new()
      {:ok, sensory, ctx} = Protocol.spawn_bit(:sensory, %{content: "input"}, ctx)
      {:ok, cognitive1, ctx} = Protocol.spawn_bit(:cognitive, %{content: "process1"}, ctx)
      {:ok, cognitive2, ctx} = Protocol.spawn_bit(:cognitive, %{content: "process2"}, ctx)

      {:ok, _edge1, ctx} = Protocol.link(sensory, cognitive1, :feeds, ctx)
      {:ok, _edge2, ctx} = Protocol.link(sensory, cognitive2, :feeds, ctx)

      assert length(ctx.edges) == 2
    end
  end

  describe "Protocol.query/2" do
    test "queries existing field" do
      ctx = Context.new()
      {:ok, bit, _ctx} = Protocol.spawn_bit(:sensory, %{content: "test content"}, ctx)

      {:ok, content} = Protocol.query(bit, :content)
      assert content == "test content"
    end

    test "returns not_found for missing field" do
      ctx = Context.new()
      {:ok, bit, _ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      result = Protocol.query(bit, :nonexistent_field)
      assert result == :not_found
    end

    test "queries multiple fields" do
      ctx = Context.new()
      {:ok, bit, _ctx} = Protocol.spawn_bit(:sensory, %{content: "test", energy: 0.7}, ctx)

      {:ok, fields} = Protocol.query(bit, [:content, :energy])
      assert fields[:content] == "test"
      assert fields[:energy] == 0.7
    end
  end

  describe "Protocol.mutate/3" do
    test "mutates allowed fields" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "original"}, ctx)

      {:ok, new_bit, _ctx} = Protocol.mutate(bit, %{energy: 0.9, salience: 0.8}, ctx)

      assert new_bit.energy == 0.9
      assert new_bit.salience == 0.8
    end

    test "rejects mutation of protected fields" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      result = Protocol.mutate(bit, %{id: "hacked"}, ctx)
      assert {:error, :forbidden} = result
    end

    test "updates bit in context after mutate" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      {:ok, new_bit, new_ctx} = Protocol.mutate(bit, %{energy: 0.9}, ctx)

      stored = Context.get_bit(new_ctx, new_bit.id)
      assert stored.energy == 0.9
    end
  end

  describe "Protocol.retire/3" do
    test "removes bit from context" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      assert Map.has_key?(ctx.bits_by_id, bit.id)

      {:ok, new_ctx} = Protocol.retire(bit, :done, ctx)

      refute Map.has_key?(new_ctx.bits_by_id, bit.id)
    end

    test "emits bit_retired event" do
      ctx = Context.new()
      {:ok, bit, ctx} = Protocol.spawn_bit(:sensory, %{content: "test"}, ctx)

      {:ok, new_ctx} = Protocol.retire(bit, :done, ctx)

      events = Context.get_events(new_ctx)
      retire_event = Enum.find(events, &(&1.type == :bit_retired))

      assert retire_event != nil
      assert retire_event.payload.bit_id == bit.id
      assert retire_event.payload.reason == :done
    end
  end

  describe "Edge.new/4" do
    test "creates edge with valid relation" do
      {:ok, edge} = Edge.new("from-id", "to-id", :feeds)

      assert edge.from_id == "from-id"
      assert edge.to_id == "to-id"
      assert edge.relation == :feeds
    end

    test "assigns unique edge ID" do
      {:ok, edge1} = Edge.new("from", "to", :feeds)
      {:ok, edge2} = Edge.new("from", "to", :feeds)

      assert edge1.id != edge2.id
      assert String.starts_with?(edge1.id, "edge-")
    end

    test "accepts category options" do
      {:ok, edge} =
        Edge.new("from", "to", :feeds,
          from_category: :sensory,
          to_category: :cognitive
        )

      assert edge.from_category == :sensory
      assert edge.to_category == :cognitive
    end

    test "returns error for invalid relation" do
      result = Edge.new("from", "to", :invalid_relation)
      assert {:error, {:invalid_relation, :invalid_relation}} = result
    end

    test "all relation types are valid" do
      valid_relations = [
        :feeds,
        :inhibits,
        :modulates,
        :contains,
        :references,
        :stores_in,
        :retrieves,
        :constrains,
        :commands,
        :orchestrates,
        :consolidates,
        :contextualizes,
        :expresses,
        :filters
      ]

      for relation <- valid_relations do
        assert Edge.valid_relation?(relation), "Expected #{relation} to be valid"
      end
    end
  end

  describe "Context helpers" do
    test "register_bit adds bit to bits_by_id" do
      ctx = Context.new()
      bit = %{id: "test-id", content: "test"}

      new_ctx = Context.register_bit(ctx, bit)

      assert new_ctx.bits_by_id["test-id"] == bit
    end

    test "add_edge prepends to edges list" do
      ctx = Context.new()
      edge1 = %{id: "edge-1", from_id: "a", to_id: "b"}
      edge2 = %{id: "edge-2", from_id: "b", to_id: "c"}

      ctx = Context.add_edge(ctx, edge1)
      ctx = Context.add_edge(ctx, edge2)

      assert length(ctx.edges) == 2
      assert hd(ctx.edges).id == "edge-2"
    end

    test "emit_event appends to event_log" do
      ctx = Context.new()

      ctx = Context.emit_event(ctx, :test_event, %{foo: "bar"})

      events = Context.get_events(ctx)
      assert length(events) == 1
      assert hd(events).type == :test_event
      assert hd(events).payload.foo == "bar"
    end

    test "log appends to log" do
      ctx = Context.new()

      ctx = Context.log(ctx, :info, "test message", %{key: "value"})

      log = Context.get_log(ctx)
      assert length(log) == 1
      assert hd(log).level == :info
      assert hd(log).message == "test message"
    end

    test "edges_from filters by from_id" do
      ctx = Context.new()
      edge1 = %Edge{id: "e1", from_id: "a", to_id: "b", relation: :feeds, strength: 1.0}
      edge2 = %Edge{id: "e2", from_id: "a", to_id: "c", relation: :feeds, strength: 1.0}
      edge3 = %Edge{id: "e3", from_id: "b", to_id: "c", relation: :feeds, strength: 1.0}

      ctx = ctx |> Context.add_edge(edge1) |> Context.add_edge(edge2) |> Context.add_edge(edge3)

      edges_from_a = Context.edges_from(ctx, "a")
      assert length(edges_from_a) == 2
    end

    test "edges_to filters by to_id" do
      ctx = Context.new()
      edge1 = %Edge{id: "e1", from_id: "a", to_id: "c", relation: :feeds, strength: 1.0}
      edge2 = %Edge{id: "e2", from_id: "b", to_id: "c", relation: :feeds, strength: 1.0}
      edge3 = %Edge{id: "e3", from_id: "a", to_id: "b", relation: :feeds, strength: 1.0}

      ctx = ctx |> Context.add_edge(edge1) |> Context.add_edge(edge2) |> Context.add_edge(edge3)

      edges_to_c = Context.edges_to(ctx, "c")
      assert length(edges_to_c) == 2
    end
  end
end
