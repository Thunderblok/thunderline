defmodule Thunderline.Thunderwall.DecayProcessorTest do
  @moduledoc """
  Tests for the DecayProcessor.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderwall.DecayProcessor

  describe "should_decay?/2" do
    test "returns true when TTL exceeded" do
      old_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert DecayProcessor.should_decay?(old_time, 3000)
    end

    test "returns false when TTL not exceeded" do
      recent_time = DateTime.add(DateTime.utc_now(), -100, :second)
      refute DecayProcessor.should_decay?(recent_time, 3600)
    end

    test "returns true at exact TTL boundary" do
      exact_time = DateTime.add(DateTime.utc_now(), -100, :second)
      assert DecayProcessor.should_decay?(exact_time, 100)
    end
  end
end
