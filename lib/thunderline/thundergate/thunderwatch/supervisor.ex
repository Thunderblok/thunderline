defmodule Thundergate.Thunderwatch.Supervisor do
  @moduledoc """
  Supervisor for Thunderwatch now housed under Thundergate.

  Deprecated old namespace: `Thunderline.Thunderwatch.Supervisor` (shim remains temporarily).
  """
  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = if enabled?(), do: [Thundergate.Thunderwatch.Manager], else: []
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp enabled? do
    case Application.get_env(:thunderline, :thunderwatch, []) |> Keyword.get(:enabled, true) do
      false -> false
      _ -> System.get_env("DISABLE_THUNDERWATCH") not in ["1", "true", "TRUE"]
    end
  end
end
