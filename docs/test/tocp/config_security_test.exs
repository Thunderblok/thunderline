defmodule Thunderline.TOCP.ConfigSecurityTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderlink.Transport.Config
  alias Thunderline.Thunderlink.Transport.Security.Impl

  test "config normalization provides nested maps" do
    c = Config.get()
    assert is_map(c.gossip)
    assert c.reliable.window > 0
    assert c.security.sign_control in [true, false]
  end

  test "replay window marks duplicates" do
    now = System.system_time(:millisecond)
    refute Impl.replay_seen?("peerA", "m1", now)
    assert Impl.replay_seen?("peerA", "m1", now)
  end

  test "replay window treats stale as seen" do
    skew = Config.get().replay.skew_ms
    past = System.system_time(:millisecond) - (skew + 1000)
    assert Impl.replay_seen?("peerB", "m_old", past)
  end
end
