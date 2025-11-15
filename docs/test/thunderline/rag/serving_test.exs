defmodule Thunderline.Thunderbolt.RAG.ServingTest do
  use ExUnit.Case, async: true

  describe "RAG.Serving" do
    test "starts with disabled state when feature flag is off" do
      # Feature flag is :rag_enabled => false in test.exs
      {:ok, pid} = Thunderline.Thunderbolt.RAG.Serving.start_link([])
      assert Process.alive?(pid)

      # Verify it returns disabled error
      assert {:error, :rag_disabled} = Thunderline.Thunderbolt.RAG.Serving.embed("test")
      assert {:error, :rag_disabled} = Thunderline.Thunderbolt.RAG.Serving.generate("test", [])
    end

    # Additional tests would require mocking or enabling RAG in test env
    # For MVP, we test that it gracefully handles disabled state
  end
end
