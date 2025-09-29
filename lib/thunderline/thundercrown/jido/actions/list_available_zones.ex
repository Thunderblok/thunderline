defmodule Thunderline.Thundercrown.Jido.Actions.ListAvailableZones do
  @moduledoc """
  Return a filtered list of active Thundergrid zones that still have agent capacity.

  This action powers governance-approved MCP tooling so downstream clients can
  inspect where new agents may be deployed before issuing orchestration commands.
  """

  use Jido.Action,
    name: "list_available_zones",
    description: "List active Thundergrid zones with remaining capacity",
    category: "thundergrid",
    tags: ["zones", "capacity", "thundergrid"],
    vsn: "1.0.0",
    schema: [
      aspect: [type: :string, required: false],
      limit: [type: :pos_integer, default: 10]
    ],
    output_schema: [
      zones: [type: {:list, :map}, required: true]
    ]

  import Ash.Query
  alias Thunderline.Thundergrid.Resources.Zone

  @max_limit 50

  @impl true
  def run(params, _context) do
    with {:ok, aspect} <- normalize_aspect(Map.get(params, :aspect)),
         limit <- clamp_limit(Map.get(params, :limit, 10)),
         {:ok, zones} <- fetch_zones(aspect, limit) do
      {:ok, %{zones: Enum.map(zones, &serialize_zone/1)}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_zones(aspect, limit) do
    query =
      Zone
      |> filter(is_active == true and agent_count < max_agents)
      |> sort(agent_count: :asc, entropy: :asc)
      |> maybe_filter_aspect(aspect)
      |> limit(limit)

    case Ash.read(query) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_filter_aspect(query, nil), do: query

  defp maybe_filter_aspect(query, aspect) do
    query
    |> filter(aspect == ^aspect)
  end

  defp normalize_aspect(nil), do: {:ok, nil}
  defp normalize_aspect(aspect) when is_atom(aspect), do: {:ok, aspect}

  defp normalize_aspect(aspect) when is_binary(aspect) do
    try do
      {:ok, String.to_existing_atom(aspect)}
    rescue
      ArgumentError -> {:error, "Unknown zone aspect: #{aspect}"}
    end
  end

  defp clamp_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(@max_limit)
  end

  defp serialize_zone(zone) do
    %{
      id: zone.id,
      coordinates: %{q: zone.q, r: zone.r},
      aspect: zone.aspect,
      entropy: decimal_to_float(zone.entropy),
      energy_level: decimal_to_float(zone.energy_level),
      agent_count: zone.agent_count,
      max_agents: zone.max_agents,
      is_active: zone.is_active,
      properties: zone.properties
    }
  end

  defp decimal_to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp decimal_to_float(value), do: value
end
