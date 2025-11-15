defmodule Thunderline.Thundercom.VoiceRoomPipelineTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thundercom.Resources.VoiceRoom

  setup do
    # Start the Voice Registry and Supervisor if not already running.
    # In test, the application disables these behind feature flags/minimal boot.
    _ =
      case Process.whereis(Thunderline.Thunderlink.Voice.Registry) do
        nil ->
          start_supervised!(
            {Registry, keys: :unique, name: Thunderline.Thunderlink.Voice.Registry}
          )

        _pid ->
          :ok
      end

    _ =
      case Process.whereis(Thunderline.Thunderlink.Voice.Supervisor) do
        nil -> start_supervised!(Thunderline.Thunderlink.Voice.Supervisor)
        _pid -> :ok
      end

    :ok
  end

  test "pipeline process is started on room creation" do
    actor = %{id: Ecto.UUID.generate()}

    {:ok, room} =
      VoiceRoom.create_room(
        %{
          title: "SpinUpTest",
          created_by_id: actor.id,
          community_id: Ecto.UUID.generate(),
          metadata: %{}
        },
        actor: actor
      )

    # Registry lookup should succeed immediately
    assert [{pid, _}] = Registry.lookup(Thunderline.Thunderlink.Voice.Registry, room.id)
    assert Process.alive?(pid)

    # The dynamic supervisor should report at least one child (not a strict guarantee but indicative)
    children = DynamicSupervisor.which_children(Thunderline.Thunderlink.Voice.Supervisor)
    assert Enum.any?(children, fn {_, cpid, _, _} -> cpid == pid end)
  end
end
