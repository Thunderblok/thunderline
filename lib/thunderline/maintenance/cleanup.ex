defmodule Thunderline.Maintenance.Cleanup do
  @moduledoc """
  Filesystem cleanup utilities for logs and artifacts.

  Provides functions used by Mix tasks to dry-run and execute deletions
  based on age and category. Paths are configurable via application env:

      config :thunderline, Thunderline.Maintenance.Cleanup,
        log_paths: ["log", "erl_crash.dump", "thunderline_chk.dets"],
        artifact_paths: [
          "cerebros/checkpoint",
          "cerebros/results",
          "tmp",
          "priv/static/uploads"
        ]

  """

  require Logger

  @type category :: :logs | :artifacts | :all

  @spec default_paths() :: %{logs: [binary()], artifacts: [binary()]}
  def default_paths do
    conf = Application.get_env(:thunderline, __MODULE__, [])

    %{
      logs: Keyword.get(conf, :log_paths, ["log", "erl_crash.dump", "thunderline_chk.dets"]),
      artifacts:
        Keyword.get(conf, :artifact_paths, [
          "cerebros/checkpoint",
          "cerebros/results",
          "tmp",
          "priv/static/uploads"
        ])
    }
  end

  @doc """
  Compute cutoff DateTime from a human duration like "30d", "12h", "15m".

  If nil or invalid, returns nil to indicate no age filtering.
  """
  @spec cutoff_from(String.t() | nil) :: DateTime.t() | nil
  def cutoff_from(nil), do: nil
  def cutoff_from(""), do: nil

  def cutoff_from(str) when is_binary(str) do
    with [_, num_s, unit] <- Regex.run(~r/^\s*(\d+)\s*([smhdw])\s*$/i, str),
         {num, ""} <- Integer.parse(num_s) do
      seconds =
        case String.downcase(unit) do
          "s" -> num
          "m" -> num * 60
          "h" -> num * 60 * 60
          "d" -> num * 60 * 60 * 24
          "w" -> num * 60 * 60 * 24 * 7
        end

      DateTime.utc_now() |> DateTime.add(-seconds, :second)
    else
      _ -> nil
    end
  end

  @doc """
  List candidate files for deletion for the given category, honoring cutoff.

  Returns a list of {path, size_bytes, mtime} tuples.
  """
  @spec list_candidates(category(), DateTime.t() | nil) :: [
          {binary(), non_neg_integer(), DateTime.t()}
        ]
  def list_candidates(category, cutoff) do
    paths = default_paths()

    scan_paths =
      case category do
        :logs -> paths.logs
        :artifacts -> paths.artifacts
        :all -> paths.logs ++ paths.artifacts
      end

    scan_paths
    |> Enum.flat_map(&expand/1)
    |> Enum.filter(&File.exists?/1)
    |> Enum.flat_map(&walk_files(&1, cutoff))
  end

  defp expand(path) do
    # Allow globs but default to relative project paths
    case Path.type(path) do
      :absolute -> Path.wildcard(path)
      :relative -> Path.wildcard(Path.expand(path, File.cwd!()))
    end
  end

  defp walk_files(path, cutoff) do
    cond do
      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.flat_map(&walk_files(Path.join(path, &1), cutoff))

      File.regular?(path) ->
        case File.stat(path) do
          {:ok, %File.Stat{mtime: mtime, size: size}} ->
            mdt = datetime_from_erl(mtime)

            if cutoff == nil or DateTime.compare(mdt, cutoff) == :lt do
              [{path, size, mdt}]
            else
              []
            end

          _ ->
            []
        end

      true ->
        []
    end
  end

  defp datetime_from_erl({{y, m, d}, {hh, mm, ss}}) do
    {:ok, dt} = DateTime.new(Date.new!(y, m, d), Time.new!(hh, mm, ss), "Etc/UTC")
    dt
  end

  @doc """
  Delete files, returning statistics. If dry_run? is true, does not delete.

  Returns: %{count: n, bytes: total, deleted: [paths], errors: [{path, reason}]}
  """
  @spec delete([{binary(), non_neg_integer(), DateTime.t()}], boolean()) ::
          %{
            count: non_neg_integer(),
            bytes: non_neg_integer(),
            deleted: [binary()],
            errors: list()
          }
  def delete(candidates, dry_run?) do
    Enum.reduce(candidates, %{count: 0, bytes: 0, deleted: [], errors: []}, fn {path, size, _},
                                                                               acc ->
      case do_delete(path, dry_run?) do
        :ok ->
          %{acc | count: acc.count + 1, bytes: acc.bytes + size, deleted: [path | acc.deleted]}

        {:error, reason} ->
          %{acc | errors: [{path, reason} | acc.errors]}
      end
    end)
  end

  defp do_delete(_path, true), do: :ok

  defp do_delete(path, false) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :eperm} -> File.rm_rf(path) |> normalize_rf()
      other -> other
    end
  end

  # File.rm_rf returns {:ok, files_deleted} on success, {:error, reason, file} on failure
  defp normalize_rf({:ok, _}), do: :ok
  defp normalize_rf({:error, reason, _file}), do: {:error, reason}
end
