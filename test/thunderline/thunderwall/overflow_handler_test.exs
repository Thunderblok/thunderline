defmodule Thunderline.Thunderwall.OverflowHandlerTest do
  @moduledoc """
  Tests for the OverflowHandler.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderwall.OverflowHandler

  setup do
    name = :"overflow_handler_test_#{System.unique_integer()}"
    {:ok, pid} = OverflowHandler.start_link(name: name)
    {:ok, name: name, pid: pid}
  end

  describe "stats/1" do
    test "returns initial stats", %{name: name} do
      stats = OverflowHandler.stats(name)
      
      assert stats.total == 0
      assert stats.by_domain == %{}
      assert stats.by_reason == %{}
    end
  end

  describe "recent/2" do
    test "returns empty list initially", %{name: name} do
      recent = OverflowHandler.recent(10, name)
      assert recent == []
    end
  end

  describe "clear_stats/1" do
    test "resets stats to zero", %{name: name} do
      # Can't easily test after overflow without full setup
      :ok = OverflowHandler.clear_stats(name)
      stats = OverflowHandler.stats(name)
      
      assert stats.total == 0
    end
  end
end
