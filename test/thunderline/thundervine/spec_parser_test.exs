defmodule Thunderline.Thundervine.SpecParserTest do
  use ExUnit.Case, async: true
  alias Thunderline.Thundervine.SpecParser

  @spec_text ~S"""
  workflow Demo
    node fetch kind=task ref=Fetch.Messages
    node summarize kind=llm ref=Summarize.Thread after=fetch
    node ticket kind=action ref=Ticket.Create after=summarize
  """

  test "parses simple workflow" do
    assert {:ok, spec} = SpecParser.parse(@spec_text)
    assert spec.name == "Demo"
    assert length(spec.nodes) == 3
    [f, s, t] = spec.nodes
    assert f.after == []
    assert s.after == ["fetch"]
    assert t.after == ["summarize"]
  end

  test "unknown after reference error" do
    bad = "workflow W\n  node a kind=task\n  node b kind=task after=x"
    assert {:error, {:unknown_after, "x", _}} = SpecParser.parse(bad)
  end
end
