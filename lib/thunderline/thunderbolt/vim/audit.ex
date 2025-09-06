defmodule Thunderline.Thunderbolt.VIM.Audit do
  @moduledoc "Memento table for VIM solve audit logs (Thunderbolt namespace)."
  use Memento.Table,
    attributes: [:id, :ts, :component, :seed, :energy_i, :energy_f, :improve_pct, :applied?],
    type: :ordered_set,
    autoincrement: true
end
