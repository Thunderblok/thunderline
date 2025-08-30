defmodule Thunderline.FeatureTest do
  use ExUnit.Case, async: true

  test "enabled?/1 returns false when flag absent" do
    original = Application.get_env(:thunderline, :features, [])
    try do
      Application.put_env(:thunderline, :features, [])
      refute Thunderline.Feature.enabled?(:vim)
    after
      Application.put_env(:thunderline, :features, original)
    end
  end

  test "enabled?/1 returns true when flag present" do
    original = Application.get_env(:thunderline, :features, [])
    try do
      Application.put_env(:thunderline, :features, [:vim])
      assert Thunderline.Feature.enabled?(:vim)
    after
      Application.put_env(:thunderline, :features, original)
    end
  end
end
