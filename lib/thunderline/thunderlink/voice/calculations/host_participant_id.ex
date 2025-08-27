defmodule Thunderline.Thunderlink.Voice.Calculations.HostParticipantId do
  @moduledoc """
  Host participant id calculation (Thunderlink). Mirrors deprecated Thundercom calculation.
  """
  @behaviour Ash.Resource.Calculation
  alias Thunderline.Thunderlink.Voice.{Participant, Room}

  @impl true
  def init(opts), do: {:ok, opts}
  @impl true
  def describe(opts), do: {:ok, Keyword.put(opts, :name, :host_participant_id)}
  @impl true
  def expression(_, _), do: nil
  @impl true
  def has_expression?, do: false
  @impl true
  def strict_loads?, do: false
  @impl true
  def calculate(rooms, _opts, _context) do
    Enum.map(rooms, fn %Room{participants: parts, created_by_id: creator} ->
      parts
      |> List.wrap()
      |> Enum.find(fn
        %Participant{role: :host, principal_id: pid} when pid == creator -> true
        _ -> false
      end)
      |> case do
        nil -> nil
        %Participant{id: id} -> id
      end
    end)
  end
  @impl true
  def load(_calc, _opts, _query), do: {:ok, [:participants]}
end
