defmodule Thunderline.Thunderblock.Jobs.RetentionSweepWorkerTest do
  use Thunderline.DataCase, async: false

  alias Ash
  alias Thunderline.Repo
  alias Thunderline.Thunderblock.Jobs.RetentionSweepWorker
  alias Thunderline.Thunderblock.Resources.RetentionPolicy
  alias Thunderline.Thunderblock.Retention.Sweeper

  setup do
    Repo.query!(
      "DELETE FROM thunderblock_retention_policies WHERE resource = 'retention_worker_test'"
    )

    on_exit(fn ->
      Application.delete_env(:thunderline, Sweeper)
    end)

    :ok
  end

  test "runs sweeper for configured target and applies deleter" do
    resource = :retention_worker_test
    now = DateTime.utc_now()

    {:ok, _policy} =
      RetentionPolicy
      |> Ash.Changeset.for_create(:define, %{
        resource: resource,
        scope_type: :global,
        scope_id: nil,
        ttl_seconds: 3_600,
        action: :delete,
        grace_seconds: 0
      })
      |> Ash.create()

    {:ok, store} =
      Agent.start_link(fn ->
        [
          %{id: "expire-me", scope: :global, inserted_at: DateTime.add(now, -9_000, :second)},
          %{id: "keep-me", scope: :global, inserted_at: now}
        ]
      end)

    on_exit(fn ->
      if Process.alive?(store) do
        Agent.stop(store)
      end
    end)

    loader = fn -> Agent.get(store, & &1) end

    deleter = fn entries ->
      ids = MapSet.new(Enum.map(entries, & &1.id))

      Agent.update(store, fn current ->
        Enum.reject(current, &MapSet.member?(ids, &1.id))
      end)

      {:ok, Enum.count(entries)}
    end

    Application.put_env(:thunderline, Sweeper,
      dry_run: false,
      batch_size: 10,
      targets: [
        %{resource: resource, loader: loader, deleter: deleter}
      ]
    )

    job = %Oban.Job{args: %{"resource" => Atom.to_string(resource)}}

    assert {:ok, result} = RetentionSweepWorker.perform(job)
    assert result.deleted == 1
    assert result.expired == 1
    refute result.dry_run?

    remaining = Agent.get(store, & &1)
    assert [%{id: "keep-me"}] = remaining
  end

  test "skips execution when resource not configured" do
    Application.put_env(:thunderline, Sweeper,
      targets: [],
      dry_run: true
    )

    job = %Oban.Job{args: %{"resource" => "unknown"}}

    assert {:discard, :no_target} = RetentionSweepWorker.perform(job)
  end
end
