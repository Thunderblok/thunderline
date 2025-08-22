defmodule Thunderline.Thunderwatch.Supervisor do
  @moduledoc """
  Top-level supervisor for the internal Thunderwatch file observation service.

  Children:
  * `Thunderline.Thunderwatch.Manager` – manages watchers, ETS index & subscriptions.
  """
  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    enabled? = thunderwatch_enabled?()

    children = if enabled? do
      [Thunderline.Thunderwatch.Manager]
    else
      []
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp thunderwatch_enabled? do
    case Application.get_env(:thunderline, :thunderwatch, []) |> Keyword.get(:enabled, true) do
      false -> false
      _ -> System.get_env("DISABLE_THUNDERWATCH") not in ["1", "true", "TRUE"]
    end
  end
end
