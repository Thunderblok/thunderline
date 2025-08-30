defmodule Thunderline.ErrorClassifierTest do
  use ExUnit.Case, async: true
  alias Thunderline.ErrorClassifier

  test "classify ecto changeset" do
    cs = %Ecto.Changeset{valid?: false, changes: %{}} |> Map.put(:action, :insert)
    ec = ErrorClassifier.classify({:error, cs})
    assert ec.class == :validation
  end

  test "classify timeout" do
    ec = ErrorClassifier.classify(:timeout)
    assert ec.class == :timeout
  end

  test "classify fallback" do
    ec = ErrorClassifier.classify({:other, :thing})
    assert ec.class == :exception
  end
end
