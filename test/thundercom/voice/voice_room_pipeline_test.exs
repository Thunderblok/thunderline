defmodule Thunderline.Thundercom.VoiceRoomPipelineTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercom.Resources.VoiceRoom

  test "pipeline process is started on room creation" do
    actor = %{id: Ecto.UUID.generate()}
    {:ok, room} = VoiceRoom.create_room(%{title: "SpinUpTest", created_by_id: actor.id, community_id: Ecto.UUID.generate(), metadata: %{}}, actor: actor)

    # Registry lookup should succeed immediately
    assert [{pid, _}] = Registry.lookup(Thunderline.Thundercom.Voice.Registry, room.id)
    assert Process.alive?(pid)

    # The dynamic supervisor should report at least one child (not a strict guarantee but indicative)
    children = DynamicSupervisor.which_children(Thunderline.Thundercom.Voice.Supervisor)
    assert Enum.any?(children, fn {_, cpid, _, _} -> cpid == pid end)
  end
end
