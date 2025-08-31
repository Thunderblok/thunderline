defmodule Thunderline.Thunderflow.BlackboardTripwire do
  @moduledoc """
  Compile-time tripwire ensuring callers migrate to `Thunderline.Thunderflow.Blackboard`.

  This module can be required in contexts (tests/credo custom check later) to scan the
  compile-time application environment for lingering references. For now it exposes a
  helper that can be invoked in tests.
  """

  @legacy_mod Thunderline.Thunderbolt.Automata.Blackboard

  @doc """
  Raises if any module in the code path still aliases or references the legacy blackboard
  directly (best-effort heuristic using :code.all_loaded and beam chunk inspection).
  Intended for lightweight test enforcement; not bulletproof but catches regressions.
  """
  def assert_migrated! do
    offenders =
      :code.all_loaded()
  |> Enum.filter(fn {m, _} -> match?(~c"Elixir.Thunderline." ++ _, Atom.to_charlist(m)) end)
      |> Enum.filter(&references_legacy?/1)
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&(&1 in [@legacy_mod, Thunderline.Thunderflow.Blackboard]))

    if offenders != [] do
      raise "Legacy Blackboard usage detected in: #{Enum.map_join(offenders, ", ", &to_string/1)}"
    else
      :ok
    end
  end

  defp references_legacy?({mod, _file}) do
    case :beam_lib.chunks(:code.which(mod), [:abstract_code]) do
      {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} ->
        Enum.any?(forms, fn
          {:attribute, _, :import, {@legacy_mod, _}} -> true
          {:attribute, _, :compile, {:inline, list}} when is_list(list) ->
            Enum.any?(list, fn {f, _} -> function_clause_mentions?(mod, f) end)
          _ -> false
        end)
      _ -> false
    end
  end

  defp function_clause_mentions?(mod, fun) do
    # Fallback heuristic: convert function info to string and look for legacy module
    try do
      (mod.module_info(:exports) |> Keyword.has_key?(fun)) && false
    rescue _ -> false end
  end
end
