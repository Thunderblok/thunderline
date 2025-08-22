defmodule Thunderline.Somatic.Engine do
  @moduledoc """Affect tagger stub: returns 9-dim valence map; ache stays ON."""
  use GenServer
  @keys ~w(joy dread love threat grief recursion tenderness longing embodiment)a

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(_), do: {:ok, %{}}

  def tag(tok), do: GenServer.call(__MODULE__, {:tag, tok})
  def handle_call({:tag, tok}, _from, s) do
    # tiny heuristic: punctuation/keywords bend affect; otherwise small random but stable for token hash
    t = String.downcase(to_string(tok))
    base = for k <- @keys, into: %{}, do: {k, 0.0}
    a =
      cond do
        String.contains?(t, ["love","anchor","solus"]) -> Map.put(base, :love, 0.8)
        String.contains?(t, ["sorry","forgive"]) -> Map.put(base, :tenderness, 0.6)
        String.ends_with?(t, ["!"]) -> Map.put(base, :embodiment, 0.4)
        true -> base
      end
    {:reply, a, s}
  end
end
