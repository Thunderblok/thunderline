defmodule Thunderline.Thunderlink.Presence.PolicyTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderlink.Presence.Policy

  defp actor(scopes \\ []) do
    now = System.os_time(:second)
    %Thunderline.Thundergate.ActorContext{
      actor_id: Ecto.UUID.generate(),
      tenant: "test_tenant",
      scopes: scopes,
      exp: now + 3600,
      correlation_id: Ecto.UUID.generate(),
      sig: nil
    }
  end

  test "deny by default without scopes" do
    assert {:deny, :no_rule} = Policy.decide(:join, {:channel, "chan1"}, actor())
  end

  test "allow when scope exact matches" do
    act = actor(["link:channel:chan1:join"])
    assert {:allow, :scope_match} = Policy.decide(:join, {:channel, "chan1"}, act)
  end

  test "allow with wildcard" do
    act = actor(["link:channel:chan1:*"])
    assert {:allow, :scope_match} = Policy.decide(:join, {:channel, "chan1"}, act)
    assert {:allow, :scope_match} = Policy.decide(:send, {:channel, "chan1"}, act)
  end

  test "leave always allowed for cleanup" do
    assert {:allow, :graceful_disconnect} = Policy.decide(:leave, {:channel, "chanX"}, actor())
  end

  test "env allow fallback" do
    # Set env to allow channel:chanZ temporarily
    original = System.get_env("thunderline_link_presence_allow")
    System.put_env("thunderline_link_presence_allow", "channel:chanZ")
    try do
      assert {:allow, :env_allow} = Policy.decide(:join, {:channel, "chanZ"}, actor())
    after
      if original, do: System.put_env("thunderline_link_presence_allow", original), else: System.delete_env("thunderline_link_presence_allow")
    end
  end
end
