defmodule Thunderline.Automata.BlackboardTest do
  use ExUnit.Case, async: false

  alias Thunderline.Automata.Blackboard

  @moduletag :automata

  test "basic put/get and snapshot operations" do
    # Ensure started
    assert Process.whereis(Blackboard)

    # Missing key
    assert :error == Blackboard.fetch(:missing_key)
    assert :default == Blackboard.get(:missing_key, :default)

    # Put global key
    :ok = Blackboard.put(:foo, 42)
    # fetch should see it (cast processed quickly; add small sleep if flaky)
    Process.sleep(5)
    assert {:ok, 42} = Blackboard.fetch(:foo)
    assert 42 == Blackboard.get(:foo)
    assert :foo in Blackboard.keys()
    snap = Blackboard.snapshot()
    assert Map.get(snap, :foo) == 42

    # Node scope key
    :ok = Blackboard.put(:node_metric, :ok, scope: :node)
    Process.sleep(5)
    assert {:ok, :ok} = Blackboard.fetch(:node_metric, scope: :node)
    refute :node_metric in Blackboard.keys() # different scope
    assert :node_metric in Blackboard.keys(scope: :node)
  end
end
