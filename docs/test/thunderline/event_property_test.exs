defmodule Thunderline.EventPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Thunderline.Event

  property "event roundtrip to_map -> normalize" do
    check all(
            name <- string(:alphanumeric, min_length: 3),
            source <- member_of([:gate, :flow, :bolt, :link, :crown, :block, :bridge]),
            payload <- map_of(string(:alphanumeric, min_length: 1), term(), min_length: 1)
          ) do
      {:ok, ev} = Event.new(%{name: "system." <> name, source: source, payload: payload})
      map = Event.to_map(ev)
      assert {:ok, _} = Event.normalize(map)
    end
  end
end
