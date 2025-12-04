defmodule Thunderline.Thundervine.FieldChannelTest do
  @moduledoc """
  Tests for the FieldChannel behaviour and implementations.
  """
  use ExUnit.Case, async: false

  alias Thunderline.Thundervine.FieldChannel
  alias Thunderline.Thundervine.FieldChannels.{
    Gravity,
    Mood,
    Heat,
    Signal,
    Entropy,
    Intent,
    Reward
  }

  @ctx %{tick: 0}

  # Helper to safely initialize a channel (handles existing tables)
  defp safe_init(module) do
    table = module.table_name()
    buffer = :"#{table}_buffer"

    # Clear existing tables if they exist
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end

    if :ets.whereis(buffer) != :undefined do
      :ets.delete_all_objects(buffer)
    end

    module.init()
  end

  describe "FieldChannel module API" do
    test "channels/0 returns all 7 channels" do
      channels = FieldChannel.channels()

      assert length(channels) == 7
      assert :gravity in channels
      assert :mood in channels
      assert :heat in channels
      assert :signal in channels
      assert :entropy in channels
      assert :intent in channels
      assert :reward in channels
    end

    test "default_value/1 returns channel defaults" do
      assert FieldChannel.default_value(:gravity) == 0.0
      assert FieldChannel.default_value(:mood) == 0.5
      assert FieldChannel.default_value(:heat) == 0.0
      assert FieldChannel.default_value(:signal) == 0.0
      assert FieldChannel.default_value(:entropy) == 0.5
      assert FieldChannel.default_value(:intent) == :neutral
      assert FieldChannel.default_value(:reward) == 0.0
    end

    test "read/3 returns error for unknown channel" do
      assert {:error, {:unknown_channel, :fake}} =
        FieldChannel.read(:fake, %{x: 0, y: 0, z: 0}, @ctx)
    end

    test "write/4 returns error for unknown channel" do
      assert {:error, {:unknown_channel, :fake}} =
        FieldChannel.write(:fake, %{x: 0, y: 0, z: 0}, 1.0, @ctx)
    end
  end

  describe "Gravity channel" do
    setup do
      safe_init(Gravity)
      :ok
    end

    test "reads default value for unwritten coordinates" do
      assert {:ok, 0.0} = Gravity.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "default_value/0 is 0.0" do
      assert Gravity.default_value() == 0.0
    end

    test "combine_writes/1 sums values and clamps to [-10, 10]" do
      assert Gravity.combine_writes([1.0, 2.0, 3.0]) == 6.0
      assert Gravity.combine_writes([5.0, 6.0]) == 10.0  # clamped
      assert Gravity.combine_writes([-5.0, -6.0]) == -10.0  # clamped
    end
  end

  describe "Mood channel" do
    setup do
      safe_init(Mood)
      :ok
    end

    test "reads default value 0.5 for unwritten coordinates" do
      assert {:ok, 0.5} = Mood.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "default_value/0 is 0.5 (neutral)" do
      assert Mood.default_value() == 0.5
    end

    test "combine_writes/1 averages values and clamps to [0, 1]" do
      assert Mood.combine_writes([0.8, 0.6, 0.4]) == 0.6  # average
      assert Mood.combine_writes([1.5, 0.5]) == 1.0  # clamped
      assert Mood.combine_writes([-0.5, 0.5]) == 0.0  # clamped
    end

    test "decay_to_value moves toward neutral (0.5)" do
      # High mood decays toward 0.5
      high = Mood.apply_decay_to_value(0.9)
      assert high < 0.9
      assert high > 0.5

      # Low mood decays toward 0.5
      low = Mood.apply_decay_to_value(0.1)
      assert low > 0.1
      assert low < 0.5
    end
  end

  describe "Heat channel" do
    setup do
      safe_init(Heat)
      :ok
    end

    test "reads default value 0.0 for unwritten coordinates" do
      assert {:ok, 0.0} = Heat.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "uses Moore neighborhood (26 neighbors)" do
      offsets = Heat.neighbor_offsets()
      assert length(offsets) == 26

      # Should not include self
      refute {0, 0, 0} in offsets
    end

    test "combine_writes/1 sums values and clamps to [0, 5]" do
      assert Heat.combine_writes([1.0, 2.0, 3.0]) == 5.0  # clamped
      assert Heat.combine_writes([0.5, 0.5]) == 1.0
    end
  end

  describe "Signal channel" do
    setup do
      safe_init(Signal)
      :ok
    end

    test "reads default value 0.0 for unwritten coordinates" do
      assert {:ok, 0.0} = Signal.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "combine_writes/1 takes max strength (not sum)" do
      assert Signal.combine_writes([0.5, 0.8, 0.3]) == 0.8
      assert Signal.combine_writes([-0.9, 0.5]) == -0.9  # max by absolute value
    end

    test "decays quickly" do
      decayed = Signal.apply_decay_to_value(1.0)
      assert decayed == 0.70
    end
  end

  describe "Entropy channel" do
    setup do
      safe_init(Entropy)
      :ok
    end

    test "reads default value 0.5 for unwritten coordinates" do
      assert {:ok, 0.5} = Entropy.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "default_value/0 is 0.5 (moderate disorder)" do
      assert Entropy.default_value() == 0.5
    end

    test "entropy is always significant" do
      assert Entropy.significant?(0.0)
      assert Entropy.significant?(0.001)
      assert Entropy.significant?(1.0)
    end

    test "combine_writes/1 averages values" do
      assert Entropy.combine_writes([0.8, 0.6, 0.4]) == 0.6
    end
  end

  describe "Intent channel" do
    setup do
      safe_init(Intent)
      :ok
    end

    test "reads default value :neutral for unwritten coordinates" do
      assert {:ok, :neutral} = Intent.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "default_value/0 is :neutral" do
      assert Intent.default_value() == :neutral
    end

    test "neutral intent is not significant" do
      refute Intent.significant?(:neutral)
      assert Intent.significant?({1.0, 0.0, 0.0})
      assert Intent.significant?(:attract)
    end

    test "does not diffuse (neighbor_offsets is empty)" do
      assert Intent.neighbor_offsets() == []
    end

    test "combine_writes/1 averages vectors" do
      result = Intent.combine_writes([{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}])
      {x, y, z} = result

      assert_in_delta x, 0.5, 0.001
      assert_in_delta y, 0.5, 0.001
      assert_in_delta z, 0.0, 0.001
    end

    test "combine_writes/1 handles special intents" do
      assert Intent.combine_writes([:attract, :neutral]) == :attract
      assert Intent.combine_writes([:repel, :neutral]) == :repel
      assert Intent.combine_writes([:neutral, :neutral]) == :neutral
    end

    test "decay moves vectors toward neutral" do
      decayed = Intent.apply_decay_to_value({1.0, 0.0, 0.0})
      {x, _y, _z} = decayed

      assert x < 1.0
      assert x > 0.0
    end

    test "small vectors collapse to neutral" do
      decayed = Intent.apply_decay_to_value({0.005, 0.005, 0.005})
      assert decayed == :neutral
    end
  end

  describe "Reward channel" do
    setup do
      safe_init(Reward)
      :ok
    end

    test "reads default value 0.0 for unwritten coordinates" do
      assert {:ok, 0.0} = Reward.read(%{x: 100, y: 100, z: 100}, @ctx)
    end

    test "default_value/0 is 0.0 (neutral)" do
      assert Reward.default_value() == 0.0
    end

    test "combine_writes/1 uses exponentially weighted average" do
      # More recent (later in list) values weighted higher
      result = Reward.combine_writes([0.1, 0.9])

      # 0.9 is more recent, so result should be closer to 0.9
      assert result > 0.5
    end

    test "decays toward zero" do
      decayed = Reward.apply_decay_to_value(1.0)
      assert decayed == 0.90
    end
  end
end
