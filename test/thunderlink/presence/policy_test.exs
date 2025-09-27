defmodule Thunderline.Thunderlink.Presence.PolicyDelegationTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thundergate.ActorContext
  alias Thunderline.Thundergate.Policies.Presence

  test "delegates decisions to thundergate policy" do
    actor = %ActorContext{
      actor_id: "actor",
      tenant: "tenant",
      scopes: ["link:channel:demo:join"],
      exp: 0,
      correlation_id: "corr",
      sig: nil
    }

    assert {:allow, :scope_match} =
             Thunderline.Thunderlink.Presence.Policy.decide(:join, {:channel, "demo"}, actor)
  end

  test "delegation preserves deny semantics" do
    actor = %ActorContext{
      actor_id: "actor",
      tenant: "tenant",
      scopes: [],
      exp: 0,
      correlation_id: "corr",
      sig: nil
    }

    assert {:deny, :no_rule} = Presence.decide(:join, {:channel, "demo"}, actor)

    assert {:deny, :no_rule} =
             Thunderline.Thunderlink.Presence.Policy.decide(:join, {:channel, "demo"}, actor)
  end
end
