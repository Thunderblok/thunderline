defmodule Thunderline.VIM.RouterAdaptor do
  @moduledoc "Build a routing optimization problem; returns {:ok, problem} | {:error, reason}."

  @spec build_problem(map) :: {:ok, map} | {:error, term}
  def build_problem(%{candidates: cands, k: k}) when is_list(cands) and is_integer(k) and k > 0 do
    # TODO: map candidates -> unary costs (h) and pair overlaps -> couplings (j)
    {:ok, %{n: length(cands), k: k, h: %{}, j: %{}}}
  end

  def build_problem(_), do: {:error, :bad_args}
end
