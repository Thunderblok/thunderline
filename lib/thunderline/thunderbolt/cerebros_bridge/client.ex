defmodule Thunderline.Thunderbolt.CerebrosBridge.Client do
  @moduledoc "Facade: reach into Cerebros tree or RPC; guarded by flags."
  alias Thunderline.Feature
  @app :thunderline

  @spec enabled?() :: boolean
  def enabled?, do: Feature.enabled?(:cerebros_bridge) and get(:enabled, false)

  @spec version(Path.t()) :: {:ok, String.t()} | {:error, :version_unavailable}
  def version(repo_path \\ cfg(:repo_path)) do
    path = Path.join(repo_path, "VERSION")

    with true <- File.exists?(path),
         {:ok, v} <- File.read(path) do
      {:ok, String.trim(v)}
    else
      _ -> {:error, :version_unavailable}
    end
  end

  defp get(k, default), do: cfg(k) || default
  defp cfg(k), do: get_in(Application.get_env(@app, :cerebros_bridge, []), [k])
end
