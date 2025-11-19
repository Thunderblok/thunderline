defmodule Thunderline.Thunderflow.Probing.Providers.Mock do
  @moduledoc "Deterministic mock provider for local/dev probe runs."
  @behaviour Thunderline.Thunderflow.Probing.Provider

  @words ~w(alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu)

  @impl true
  def generate(prompt, _spec) do
    seed = :erlang.phash2(prompt <> inspect(System.monotonic_time()))
    :rand.seed(:exsss, {seed, seed, seed})
    size = Enum.random(20..40)
    text = Enum.map_join(1..size, " ", fn _ -> Enum.random(@words) end)
    {:ok, text}
  end
end
