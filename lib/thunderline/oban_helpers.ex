defmodule Thunderline.ObanHelpers do
  @moduledoc """
  Helper functions for safely queueing Oban jobs.

  Addresses the `inserted_at` NULL constraint issue where Oban's schema
  uses a regular `field :inserted_at` instead of the `timestamps()` macro,
  causing Ecto to send NULL which overrides the database default.

  ## Usage

  **Recommended**: Use `enqueue/3` for single jobs:
  ```elixir
  ObanHelpers.enqueue(MyWorker, %{args: "here"})
  ObanHelpers.enqueue(MyWorker, %{args: "here"}, queue: :ml, priority: 1)
  ```

  **Alternative**: When calling worker's `new/2` directly, pipe to `insert_job/1`:
  ```elixir
  MyWorker.new(%{args: "here"})
  |> ObanHelpers.insert_job()
  ```

  **Batch**: Use `enqueue_many/1` for multiple jobs:
  ```elixir
  jobs = [
    {Worker1, %{id: 1}},
    {Worker2, %{id: 2}, [priority: 3]}
  ]
  ObanHelpers.enqueue_many(jobs)
  ```
  """

  @doc """
  Insert an Oban job changeset, ensuring timestamps are set correctly.

  Useful when you've already called `Worker.new/2` and want to insert safely.

  ## Examples

      Thunderline.Thunderflow.Jobs.DemoJob.new(%{foo: "bar"})
      |> Thunderline.ObanHelpers.insert_job()

      # Or in a pipeline
      SyncWorker.new(%{action: "sync"})
      |> ObanHelpers.insert_job()
  """
  def insert_job(changeset) do
    changeset
    |> maybe_set_inserted_at()
    |> Oban.insert()
  end

  @doc """
  Enqueue an Oban job, ensuring timestamps are set correctly.

  ## Examples

      # Queue a job immediately
      Thunderline.ObanHelpers.enqueue(Thunderline.Thunderflow.Jobs.DemoJob, %{foo: "bar"})

      # Queue a job with options
      Thunderline.ObanHelpers.enqueue(Thunderline.Thunderflow.Jobs.DemoJob, %{}, queue: :ml, priority: 1)

      # Schedule a job for later
      Thunderline.ObanHelpers.enqueue(Thunderline.Thunderflow.Jobs.DemoJob, %{}, schedule_in: {5, :minutes})
  """
  def enqueue(worker, args, opts \\ []) when is_atom(worker) and is_map(args) and is_list(opts) do
    worker
    |> apply(:new, [args, opts])
    |> maybe_set_inserted_at()
    |> Oban.insert()
  end

  @doc """
  Enqueue multiple jobs in a single transaction.

  ## Examples

      jobs = [
        {Thunderline.Thunderflow.Jobs.DemoJob, %{id: 1}},
        {Thunderline.Thunderbolt.Workers.CerebrosTrainer, %{model: "gpt"}},
      ]

      Thunderline.ObanHelpers.enqueue_many(jobs)
  """
  def enqueue_many(jobs) when is_list(jobs) do
    changesets =
      Enum.map(jobs, fn
        {worker, args} -> prepare_job(worker, args, [])
        {worker, args, opts} -> prepare_job(worker, args, opts)
      end)

    Oban.insert_all(changesets)
  end

  # Private helpers

  defp prepare_job(worker, args, opts) do
    worker
    |> apply(:new, [args, opts])
    |> maybe_set_inserted_at()
  end

  defp maybe_set_inserted_at(changeset) do
    # If inserted_at is nil in the changeset, explicitly set it to now()
    # This prevents Ecto from sending NULL which overrides the database default
    case Ecto.Changeset.get_change(changeset, :inserted_at) do
      nil ->
        Ecto.Changeset.put_change(changeset, :inserted_at, DateTime.utc_now())

      _timestamp ->
        changeset
    end
  end
end
