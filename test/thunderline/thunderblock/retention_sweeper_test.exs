defmodule Thunderline.Thunderblock.RetentionSweeperTest do
  use Thunderline.DataCase, async: false

  alias Ash
  alias Thunderline.Repo
  alias Thunderline.Thunderblock.Retention
  alias Thunderline.Thunderblock.Retention.Sweeper
  alias Thunderline.Thunderblock.Resources.RetentionPolicy

  @seed_key {:thunderline, :thunderblock_retention_defaults}
  @telemetry_event [:thunderline, :retention, :sweep]

  setup do
    Repo.query!("DELETE FROM thunderblock_retention_policies")
    :persistent_term.erase(@seed_key)

    on_exit(fn ->
      :telemetry.detach("retention-sweeper-test")
      Application.delete_env(:thunderline, Sweeper)
    end)

    :telemetry.attach(
      "retention-sweeper-test",
      @telemetry_event,
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    :ok
  end

  describe "sweep/2" do
    test "removes expired records respecting scoped precedence" do
      now = DateTime.utc_now()
      tenant_id = Ecto.UUID.generate()
      resource = :log_entry

      Application.put_env(:thunderline, Sweeper, dry_run: false, batch_size: 2)

      Retention.ensure_defaults!()

      {:ok, _global} =
        RetentionPolicy
        |> Ash.Changeset.for_create(:define, %{
          resource: resource,
          scope_type: :global,
          scope_id: nil,
          ttl_seconds: 7 * 86_400,
          action: :delete,
          grace_seconds: 0
        })
        |> Ash.create()

      {:ok, _scoped} =
        RetentionPolicy
        |> Ash.Changeset.for_create(:define, %{
          resource: resource,
          scope_type: :tenant,
          scope_id: tenant_id,
          ttl_seconds: 3 * 86_400,
          action: :delete,
          grace_seconds: 86_400
        })
        |> Ash.create()

      {:ok, store} =
        Agent.start_link(fn ->
          [
            %{id: "global_keep", scope: :global, inserted_at: DateTime.add(now, -2 * 86_400, :second)},
            %{id: "global_expire", scope: :global, inserted_at: DateTime.add(now, -12 * 86_400, :second)},
            %{id: "tenant_keep", scope: {:tenant, tenant_id}, inserted_at: DateTime.add(now, -3 * 86_400, :second)},
            %{id: "tenant_expire", scope: {:tenant, tenant_id}, inserted_at: DateTime.add(now, -6 * 86_400, :second)}
          ]
        end)

      on_exit(fn ->
        if Process.alive?(store) do
          Agent.stop(store)
        end
      end)

      loader = fn -> Agent.get(store, & &1) end

      delete = fn entries ->
        ids = MapSet.new(Enum.map(entries, & &1.id))

        Agent.update(store, fn current ->
          Enum.reject(current, &(MapSet.member?(ids, &1.id)))
        end)

        {:ok, length(entries)}
      end

      assert {:ok, result} =
               Sweeper.sweep(resource,
                 load: loader,
                 delete: delete,
                 now: now,
                 metadata: %{reason: :test_run}
               )

      remaining_ids = store |> Agent.get(& &1) |> Enum.map(& &1.id) |> Enum.sort()
      assert remaining_ids == ["global_keep", "tenant_keep"]

      assert result.expired == 2
      assert result.deleted == 2
      assert result.kept == 2
      refute result.dry_run?
      assert result.metadata.resource == resource
      assert result.metadata.batch_size == 2

      assert_receive {:telemetry_event, @telemetry_event, measurements, metadata}
      assert measurements.expired == 2
      assert measurements.deleted == 2
      assert measurements.kept == 2
      assert Map.get(metadata, :resource) == resource
      refute Map.get(metadata, :dry_run?)
    end
  end
end
