defmodule Thunderline.Thundercrown.Daisy do
  @moduledoc "Thundercrown aggregation helpers for Daisy swarms (canonical namespace)."
  alias Thunderline.Thundercrown.Daisy.{Identity, Affect, Novelty, Ponder}
  alias Thunderline.Thundercrown.Daisy.Base, as: Base

  def preview_all_swarms do
    {inj_i, del_i} = Base.preview(Identity)
    {inj_a, del_a} = Base.preview(Affect)
    {inj_n, del_n} = Base.preview(Novelty)
    {inj_p, del_p} = Base.preview(Ponder)
    inj = Enum.max_by([inj_i, inj_a, inj_n, inj_p], &(&1 && &1.score || -1.0), fn -> nil end)
    del = Enum.min_by([del_i, del_a, del_n, del_p], &(&1 && &1.score ||  1.0), fn -> nil end)
    {inj, del}
  end

  def commit_all_swarms(inj, del) do
    for m <- [Identity, Affect, Novelty, Ponder], do: Base.commit(m, inj, del)
    :ok
  end

  def snapshot_all_swarms do
    %{
      identity: Base.snapshot(Identity),
      affect:   Base.snapshot(Affect),
      novelty:  Base.snapshot(Novelty),
      ponder:   Base.snapshot(Ponder)
    }
  end

  def restore_all_swarms(%{identity: i, affect: a, novelty: n, ponder: p}) do
    Base.restore(Identity, i)
    Base.restore(Affect, a)
    Base.restore(Novelty, n)
    Base.restore(Ponder, p)
    :ok
  end
end
