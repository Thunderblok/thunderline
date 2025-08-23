defmodule Thunderline.Thundercom.Calculations.HostParticipantId do
  @moduledoc """
  Manual Ash calculation module to derive the host participant id.
  """
  @behaviour Ash.Resource.Calculation
  alias Thunderline.Thundercom.Resources.{VoiceParticipant, VoiceRoom}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def expression(_opts), do: nil

  @impl true
  def calculate(rooms, _opts, _context) do
    Enum.map(rooms, fn %VoiceRoom{participants: parts, created_by_id: creator} ->
      parts
      |> List.wrap()
      |> Enum.find(fn
        %VoiceParticipant{role: :host, principal_id: pid} when pid == creator -> true
        _ -> false
      end)
      |> case do
        nil -> nil
        %VoiceParticipant{id: id} -> id
      end
    end)
  end

  @impl true
  def load(_opts, _query) do
    {:ok, [:participants]}
  end
end
