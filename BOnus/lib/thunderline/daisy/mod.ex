defmodule Thunderline.Daisy do
  @moduledoc """Aggregator helpers for Daisy swarms."""
  alias Thunderline.Daisy.{Identity, Affect, Novelty, Ponder}

  def preview_all_swarms do
    {inj_i, del_i} = Thunderline.Daisy.Base.preview(Identity)
    {inj_a, del_a} = Thunderline.Daisy.Base.preview(Affect)
    {inj_n, del_n} = Thunderline.Daisy.Base.preview(Novelty)
    {inj_p, del_p} = Thunderline.Daisy.Base.preview(Ponder)
    inj = Enum.max_by([inj_i, inj_a, inj_n, inj_p], &(&1 && &1.score || -1.0), fn -> nil end)
    del = Enum.min_by([del_i, del_a, del_n, del_p], &(&1 && &1.score ||  1.0), fn -> nil end)
    {inj, del}
  end

  def commit_all_swarms(inj, del) do
    for m <- [Identity, Affect, Novelty, Ponder] do
      Thunderline.Daisy.Base.commit(m, inj, del)
    end
    :ok
  end

  def snapshot_all_swarms do
    %{
      identity: Thunderline.Daisy.Base.snapshot(Identity),
      affect:   Thunderline.Daisy.Base.snapshot(Affect),
      novelty:  Thunderline.Daisy.Base.snapshot(Novelty),
      ponder:   Thunderline.Daisy.Base.snapshot(Ponder)
    }
  end

  def restore_all_swarms(%{identity: i, affect: a, novelty: n, ponder: p}) do
    Thunderline.Daisy.Base.restore(Identity, i)
    Thunderline.Daisy.Base.restore(Affect, a)
    Thunderline.Daisy.Base.restore(Novelty, n)
    Thunderline.Daisy.Base.restore(Ponder, p)
    :ok
  end
end
