defmodule Thunderline.ThunderwatchManagerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  test "starts and indexes existing roots" do
    # Ensure service started (may already be in supervision tree)
    assert Process.whereis(Thunderline.Thunderwatch.Manager) != nil
    snap = Thunderline.Thunderwatch.Manager.snapshot()
    assert is_map(snap)
  end
end
