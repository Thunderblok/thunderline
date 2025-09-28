defmodule ThunderlineWeb.CerebrosMetricsController do
  @moduledoc """
  JSON endpoint exposing the latest Cerebros NAS metrics snapshot gathered by
  `Thunderline.Thunderbolt.Cerebros.Metrics`.

  Returns HTTP 404 when the Cerebros integration is disabled so external
  automation can short-circuit in non-ML deployments.
  """

  use ThunderlineWeb, :controller

  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.Cerebros
  alias Thunderline.Thunderbolt.CerebrosBridge.Client, as: CerebrosBridge

  @doc """
  Fetch the latest Cerebros metrics snapshot.
  """
  def show(conn, _params) do
    if cerebros_enabled?() do
      snapshot = Cerebros.Metrics.snapshot()

      json(conn, %{status: "ok", data: snapshot})
    else
      conn
      |> put_status(:not_found)
      |> json(%{status: "disabled", error: "cerebros_disabled"})
    end
  end

  defp cerebros_enabled? do
    Feature.enabled?(:ml_nas, default: false) and CerebrosBridge.enabled?()
  end
end
