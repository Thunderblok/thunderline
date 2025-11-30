defmodule Thunderline.Thunderpac.Changes.ComputeChecksum do
  @moduledoc """
  Ash change that computes checksum and size for PACState snapshots.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :state_data) do
      nil ->
        changeset

      state_data when is_map(state_data) ->
        json = Jason.encode!(state_data)
        size = byte_size(json)
        checksum = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)

        changeset
        |> Ash.Changeset.force_change_attribute(:size_bytes, size)
        |> Ash.Changeset.force_change_attribute(:checksum, checksum)

      _other ->
        changeset
    end
  end
end
