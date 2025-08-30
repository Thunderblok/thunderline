defmodule Thunderline.VIM.AuditLog do
  @moduledoc "Helpers for appending VIM audit rows (flag-guarded)."
  alias Thunderline.VIM.Audit
  @spec append(map) :: :ok | {:error, term}
  def append(row) when is_map(row) do
    if (Application.get_env(:thunderline, :vim, []) |> Keyword.get(:enabled, false)) do
      Memento.transaction(fn ->
        entry = struct(Audit, Map.merge(%{ts: System.system_time(:millisecond)}, row))
        Memento.write(entry)
      end)
      :ok
    else
      :ok
    end
  end
end
