defmodule Thunderline.VIM.PersonaAdaptor do
  @moduledoc "Build a persona board optimization problem (Phase-1 stub)."

  @spec build_problem(map) :: {:ok, map} | {:error, term}
  def build_problem(%{board_size: n}) when is_integer(n) and n > 0 and n <= 512 do
    {:ok, %{n: n, h: %{}, j: %{}}}
  end

  def build_problem(_), do: {:error, :bad_args}
end
