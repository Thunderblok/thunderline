defmodule Thunderline.Graphql.SchemaTest do
  use ExUnit.Case, async: true

  alias AshGraphql.Domain.Info

  test "thunderbolt domain exposes core agent operations" do
    queries = Info.queries(Thunderline.Thunderbolt.Domain)
    mutations = Info.mutations(Thunderline.Thunderbolt.Domain)

    assert Enum.any?(queries, &(&1.name == :core_agents))
    assert Enum.any?(queries, &(&1.name == :active_core_agents))
    assert Enum.any?(mutations, &(&1.name == :register_core_agent))
    assert Enum.any?(mutations, &(&1.name == :heartbeat_core_agent))
  end

  test "thundergrid domain exposes zone operations" do
    queries = Info.queries(Thunderline.Thundergrid.Domain)
    mutations = Info.mutations(Thunderline.Thundergrid.Domain)

    assert Enum.any?(queries, &(&1.name == :zones))
    assert Enum.any?(queries, &(&1.name == :available_zones))
    assert Enum.any?(queries, &(&1.name == :zone_by_coordinates))

    assert Enum.any?(mutations, &(&1.name == :spawn_zone))
    assert Enum.any?(mutations, &(&1.name == :adjust_zone_entropy))
    assert Enum.any?(mutations, &(&1.name == :activate_zone))
    assert Enum.any?(mutations, &(&1.name == :deactivate_zone))
  end
end
