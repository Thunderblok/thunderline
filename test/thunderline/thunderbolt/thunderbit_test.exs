defmodule Thunderline.Thunderbolt.ThunderbitTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Thunderbit

  describe "new/2" do
    test "creates a new Thunderbit with required fields" do
      bit = Thunderbit.new({0, 0, 0})

      assert bit.coord == {0, 0, 0}
      assert is_binary(bit.id)
      assert bit.state == 0
      assert bit.rule_id == :demo
      assert bit.trust_score == 0.5
      assert bit.sigma_flow == 1.0
      assert bit.phi_phase == 0.0
      assert bit.lambda_sensitivity == 0.0
    end

    test "allows customizing initial values" do
      bit =
        Thunderbit.new({1, 2, 3},
          state: 42,
          rule_id: :diffusion,
          trust_score: 0.9,
          sigma_flow: 0.7
        )

      assert bit.coord == {1, 2, 3}
      assert bit.state == 42
      assert bit.rule_id == :diffusion
      assert bit.trust_score == 0.9
      assert bit.sigma_flow == 0.7
    end

    test "generates unique IDs" do
      bit1 = Thunderbit.new({0, 0, 0})
      bit2 = Thunderbit.new({0, 0, 0})

      refute bit1.id == bit2.id
    end

    test "sets timestamps" do
      bit = Thunderbit.new({0, 0, 0})

      assert %DateTime{} = bit.created_at
      assert %DateTime{} = bit.updated_at
      assert DateTime.compare(bit.created_at, bit.updated_at) == :eq
    end
  end

  describe "local decision predicates" do
    test "can_relay?/2 checks sigma_flow threshold" do
      high_flow = Thunderbit.new({0, 0, 0}, sigma_flow: 0.8)
      low_flow = Thunderbit.new({0, 0, 0}, sigma_flow: 0.3)

      assert Thunderbit.can_relay?(high_flow, 0.5)
      refute Thunderbit.can_relay?(low_flow, 0.5)
    end

    test "can_bridge?/2 checks trust_score threshold" do
      trusted = Thunderbit.new({0, 0, 0}, trust_score: 0.7)
      untrusted = Thunderbit.new({0, 0, 0}, trust_score: 0.1)

      assert Thunderbit.can_bridge?(trusted, 0.3)
      refute Thunderbit.can_bridge?(untrusted, 0.3)
    end

    test "chaotic?/2 checks lambda_sensitivity threshold" do
      chaotic = Thunderbit.new({0, 0, 0}, lambda_sensitivity: 0.9)
      stable = Thunderbit.new({0, 0, 0}, lambda_sensitivity: 0.3)

      assert Thunderbit.chaotic?(chaotic, 0.8)
      refute Thunderbit.chaotic?(stable, 0.8)
    end

    test "idle?/1 checks channel assignment" do
      idle_bit = Thunderbit.new({0, 0, 0})
      busy_bit = Thunderbit.new({0, 0, 0}, channel_id: Ecto.UUID.generate())

      assert Thunderbit.idle?(idle_bit)
      refute Thunderbit.idle?(busy_bit)
    end

    test "has_presence?/2 checks presence vector" do
      pac_id = "pac-123"
      with_presence = Thunderbit.new({0, 0, 0}, presence_vector: %{pac_id => 0.8})
      without_presence = Thunderbit.new({0, 0, 0})

      assert Thunderbit.has_presence?(with_presence, pac_id)
      refute Thunderbit.has_presence?(without_presence, pac_id)
    end
  end

  describe "state updates" do
    test "update_state/2 updates dynamics metrics" do
      bit = Thunderbit.new({0, 0, 0})

      updated =
        Thunderbit.update_state(bit,
          state: 1,
          phi_phase: 1.5,
          sigma_flow: 0.8,
          lambda_sensitivity: 0.2,
          tick: 100
        )

      assert updated.state == 1
      assert updated.phi_phase == 1.5
      assert updated.sigma_flow == 0.8
      assert updated.lambda_sensitivity == 0.2
      assert updated.last_tick == 100
    end

    test "update_state/2 increments tick if not specified" do
      bit = Thunderbit.new({0, 0, 0})
      assert bit.last_tick == 0

      updated = Thunderbit.update_state(bit, state: 1)
      assert updated.last_tick == 1
    end

    test "add_presence/3 adds PAC presence" do
      bit = Thunderbit.new({0, 0, 0})

      updated = Thunderbit.add_presence(bit, "pac-123", 0.9)

      assert updated.presence_vector["pac-123"] == 0.9
    end

    test "remove_presence/2 removes PAC presence" do
      bit = Thunderbit.new({0, 0, 0}, presence_vector: %{"pac-123" => 0.9, "pac-456" => 0.7})

      updated = Thunderbit.remove_presence(bit, "pac-123")

      refute Map.has_key?(updated.presence_vector, "pac-123")
      assert updated.presence_vector["pac-456"] == 0.7
    end

    test "decay_presence/2 decays all presence values" do
      bit = Thunderbit.new({0, 0, 0}, presence_vector: %{"pac-123" => 0.8, "pac-456" => 0.4})

      updated = Thunderbit.decay_presence(bit, 0.5)

      assert updated.presence_vector["pac-123"] == 0.4
      assert updated.presence_vector["pac-456"] == 0.2
    end

    test "decay_presence/2 removes presence below threshold" do
      # 0.019 * 0.5 = 0.0095 < 0.01 threshold, should be removed
      bit = Thunderbit.new({0, 0, 0}, presence_vector: %{"pac-123" => 0.019, "pac-456" => 0.5})

      updated = Thunderbit.decay_presence(bit, 0.5)

      refute Map.has_key?(updated.presence_vector, "pac-123")
      assert updated.presence_vector["pac-456"] == 0.25
    end
  end

  describe "channel management" do
    test "assign_channel/3 assigns channel" do
      bit = Thunderbit.new({0, 0, 0})
      channel_id = Ecto.UUID.generate()
      key_id = "key-123"

      updated = Thunderbit.assign_channel(bit, channel_id, key_id)

      assert updated.channel_id == channel_id
      assert updated.key_id == key_id
    end

    test "release_channel/1 clears channel" do
      channel_id = Ecto.UUID.generate()
      bit = Thunderbit.new({0, 0, 0}, channel_id: channel_id, key_id: "key-123")

      updated = Thunderbit.release_channel(bit)

      assert is_nil(updated.channel_id)
      assert is_nil(updated.key_id)
    end
  end

  describe "trust management" do
    test "update_trust/2 adjusts trust score" do
      bit = Thunderbit.new({0, 0, 0}, trust_score: 0.5)

      increased = Thunderbit.update_trust(bit, 0.3)
      assert increased.trust_score == 0.8

      decreased = Thunderbit.update_trust(bit, -0.3)
      assert decreased.trust_score == 0.2
    end

    test "update_trust/2 clamps to valid range" do
      bit = Thunderbit.new({0, 0, 0}, trust_score: 0.9)

      capped = Thunderbit.update_trust(bit, 0.5)
      assert capped.trust_score == 1.0

      floored = Thunderbit.update_trust(bit, -1.5)
      assert floored.trust_score == 0.0
    end
  end

  describe "to_delta/1" do
    test "converts Thunderbit to delta map for PubSub" do
      bit =
        Thunderbit.new({1, 2, 3},
          state: 42,
          sigma_flow: 0.8,
          trust_score: 0.7,
          phi_phase: 1.5,
          lambda_sensitivity: 0.2,
          channel_id: "chan-123"
        )

      delta = Thunderbit.to_delta(bit)

      assert delta.id == bit.id
      assert delta.x == 1
      assert delta.y == 2
      assert delta.z == 3
      assert delta.state == 42
      assert delta.flow == 0.8
      assert delta.trust == 0.7
      assert delta.phase == 1.5
      assert delta.lambda == 0.2
      assert delta.channel == "chan-123"
      assert is_integer(delta.energy)
      assert is_integer(delta.hex)
    end
  end
end
