defmodule Thunderflow.EventConstructorTest do
  use ExUnit.Case, async: true

  alias Thunderline.Event

  test "happy path: builds a valid event with causality defaults" do
    data = %{foo: "bar"}
    {:ok, ev} = Event.new(type: :foo_created, source: :flow, payload: data)

    assert %Event{} = ev
    assert ev.type == :foo_created
    assert ev.source == :flow
    assert is_binary(ev.id) and byte_size(ev.id) > 0
    assert ev.payload == data
    assert ev.at
    assert ev.correlation_id
    # root event => causation nil
    assert ev.causation_id in [nil, ev.meta[:causation_id]]
    assert ev.meta[:reliability] in [:persistent, :transient]
  end

  test "validation: rejects missing type/name" do
    assert {:error, errs} = Event.new(%{payload: %{}})
    assert {:missing, :name} in errs
  end

  test "validation: rejects non-map payload" do
    assert {:error, errs} = Event.new(%{type: :bad, source: :flow, payload: :not_a_map})
    assert {:invalid, :payload} in errs
  end

  test "category enforcement: forbidden category for domain" do
    # :block domain not allowed to emit ai.intent.*
    assert {:error, errs} = Event.new(%{name: "ai.intent.email.compose", source: :block, payload: %{}})
    assert Enum.any?(errs, fn e -> match?({:forbidden_category, _}, e) end)
  end
end
