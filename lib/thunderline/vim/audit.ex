defmodule Thunderline.VIM.Audit do
  @moduledoc "Memento table for VIM solve audit logs."
  use Memento.Table,
    attributes: [:id, :ts, :component, :seed, :energy_i, :energy_f, :improve_pct, :applied?],
    type: :ordered_set,
    autoincrement: true
end
