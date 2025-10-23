defmodule Thunderline.RAG.CollectionTest do
  use ExUnit.Case, async: true

  alias Thunderline.RAG.Collection

  describe "Ash resource configuration" do
    test "defines ingest action" do
      actions = Ash.Resource.Info.actions(Collection)
      assert Enum.any?(actions, fn action -> action.name == :ingest end)
    end

    test "defines ask action" do
      actions = Ash.Resource.Info.actions(Collection)
      assert Enum.any?(actions, fn action -> action.name == :ask end)
    end

    test "has required attributes" do
      attrs = Ash.Resource.Info.attributes(Collection)
      attr_names = Enum.map(attrs, & &1.name)

      assert :text in attr_names
      assert :metadata in attr_names
      assert :query in attr_names
      assert :response in attr_names
      assert :sources in attr_names
      assert :status in attr_names
    end
  end

  describe "ingest action" do
    test "returns error when RAG is disabled" do
      # Since RAG is disabled in test env, actions will fail gracefully
      result =
        Collection
        |> Ash.Changeset.for_create(:ingest, %{
          text: "Test document",
          metadata: %{source: "test"}
        })
        |> Ash.create()

      # Should error due to underlying RAG being disabled
      assert {:error, _error} = result
    end
  end

  describe "ask action" do
    test "returns error when RAG is disabled" do
      # Query will fail when RAG is disabled
      result =
        Collection
        |> Ash.Query.for_read(:ask, %{query: "Test query"})
        |> Ash.read()

      # Should error due to underlying RAG being disabled
      assert {:error, _error} = result
    end
  end
end
