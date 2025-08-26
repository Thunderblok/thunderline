defmodule Thunderline.FeatureHelperTest do
  use ExUnit.Case, async: true

  test "override is process-local" do
    refute Thunderline.Feature.enabled?(:ml_nas)

    Thunderline.Feature.override(:ml_nas, true)
    assert Thunderline.Feature.enabled?(:ml_nas)

    parent = self()
    ref = make_ref()

    spawn(fn ->
      send(parent, {ref, Thunderline.Feature.enabled?(:ml_nas)})
    end)

    assert_receive {^ref, false}, 200

    Thunderline.Feature.clear_override(:ml_nas)
    refute Thunderline.Feature.enabled?(:ml_nas)
  end
end
