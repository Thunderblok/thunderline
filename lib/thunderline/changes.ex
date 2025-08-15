defmodule Thunderline.Changes.PruneWorkingMemory do
  @moduledoc """
  Prunes expired entries from working memory based on TTL
  """
  use Ash.Resource.Change

  def change(changeset, opts, _ctx) do
    field = opts[:field] || :working_memory
    ttl_field = opts[:ttl_ms_field] || :memory_ttl_ms
    now = System.system_time(:millisecond)

    Ash.Changeset.after_action(changeset, fn rec, _ ->
      ttl = Map.get(rec, ttl_field, 300_000)

      pruned =
        rec
        |> Map.get(field, %{})
        |> Enum.reject(fn
          {_k, %{"t" => t}} -> now - t > ttl
          _ -> false
        end)
        |> Map.new()

      {:ok, Map.put(rec, field, pruned)}
    end)
  end
end

defmodule Thunderline.Changes.RunNodeLogic do
  @moduledoc """
  Executes node-specific logic through engine dispatch
  """
  use Ash.Resource.Change

  def change(cs, opts, _ctx) do
    fun = opts[:dispatch]

    Ash.Changeset.after_action(cs, fn rec, ctx ->
      result = fun.(rec, ctx.arguments[:context])
      {:ok, Map.put(rec, :tick_result, result)}
    end)
  end
end

defmodule Thunderline.Changes.ApplyTickResult do
  @moduledoc """
  Applies tick execution results to node state and working memory
  """
  use Ash.Resource.Change

  def change(cs, opts, _ctx) do
    status_field = opts[:status_field] || :status
    wm_field = opts[:wm_field] || :working_memory
    now = System.system_time(:millisecond)

    Ash.Changeset.after_action(cs, fn rec, _ ->
      %{status: st, scratch: scratch} = Map.get(rec, :tick_result, %{status: :idle, scratch: %{}})

      stamped =
        scratch
        |> Enum.map(fn {k, v} -> {k, %{"v" => v, "t" => now}} end)
        |> Map.new()

      rec =
        rec
        |> Map.put(status_field, st)
        |> Map.update!(wm_field, &Map.merge(&1, stamped))

      {:ok, rec}
    end)
  end
end

defmodule Thunderline.Changes.PutInMap do
  @moduledoc """
  Puts a value at a nested path in a map field (for blackboard operations)
  """
  use Ash.Resource.Change

  def change(cs, opts, _ctx) do
    field = opts[:field]

    Ash.Changeset.after_action(cs, fn rec, ctx ->
      path = String.split(ctx.arguments[:path], ".")
      val = ctx.arguments[:value]
      new_map = put_in(rec |> Map.get(field, %{}), path, val)
      {:ok, Map.put(rec, field, new_map)}
    end)
  end
end

defmodule Thunderline.Changes.DeleteInMap do
  @moduledoc """
  Deletes a value at a nested path in a map field (for blackboard operations)
  """
  use Ash.Resource.Change

  def change(cs, opts, _ctx) do
    field = opts[:field]

    Ash.Changeset.after_action(cs, fn rec, ctx ->
      path = String.split(ctx.arguments[:path], ".")
      {_, new_map} = pop_in(rec |> Map.get(field, %{}), path)
      {:ok, Map.put(rec, field, new_map)}
    end)
  end
end
