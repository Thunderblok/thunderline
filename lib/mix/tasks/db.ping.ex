defmodule Mix.Tasks.Db.Ping do
  @shortdoc "Ping database connectivity & report repo config"
  @moduledoc """
  Attempts a quick Repo.start + SELECT 1; reports success/failure and effective config.

  Usage:
      mix db.ping
  """
  use Mix.Task

  def run(_args) do
    Mix.Task.run("app.config")
    cfg = Application.get_env(:thunderline, Thunderline.Repo)
    IO.puts("[db.ping] Repo config: host=#{cfg[:hostname]} port=#{cfg[:port]} db=#{cfg[:database]} user=#{cfg[:username]}")
    ensure_deps()
    case start_repo() do
      :ok ->
        case Ecto.Adapters.SQL.query(Thunderline.Repo, "SELECT 1", []) do
          {:ok, _} -> IO.puts("[db.ping] ✅ connectivity OK")
          {:error, err} -> IO.puts("[db.ping] ❌ query failed: #{inspect(err)}")
        end
      {:error, err} -> IO.puts("[db.ping] ❌ failed to start repo: #{inspect(err)}")
    end
  end

  defp ensure_deps, do: Enum.each([:logger, :crypto, :ssl, :postgrex, :ecto_sql], &Application.ensure_all_started/1)
  defp start_repo do
    case Thunderline.Repo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
      other -> other
    end
  end
end
