defmodule Thunderline.FeatureHelperTest do
  use ExUnit.Case, async: true

  test "override is process-local" do
    Thunderline.Feature.clear_override(:ml_nas)
    initial = Thunderline.Feature.enabled?(:ml_nas)
    on_exit(fn -> Thunderline.Feature.clear_override(:ml_nas) end)

    toggled = not initial

    Thunderline.Feature.override(:ml_nas, toggled)
    assert Thunderline.Feature.enabled?(:ml_nas) == toggled

    parent = self()
    ref = make_ref()

    spawn(fn ->
      send(parent, {ref, Thunderline.Feature.enabled?(:ml_nas)})
    end)

    assert_receive {^ref, initial}, 200

    Thunderline.Feature.clear_override(:ml_nas)
    assert Thunderline.Feature.enabled?(:ml_nas) == initial
  end
end
