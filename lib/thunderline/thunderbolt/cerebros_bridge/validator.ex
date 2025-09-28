defmodule Thunderline.Thunderbolt.CerebrosBridge.Validator do
  @moduledoc """
  Performs environment checks for the Cerebros bridge prior to enabling the
  `:ml_nas` feature flag. Used by `mix thunderline.ml.validate`.

  Each check returns a map containing:

    * `:name` – atom identifier
    * `:status` – `:ok | :warning | :error`
    * `:message` – human friendly description
    * `:metadata` – additional context used by the mix task formatter

  The validator aggregates the individual results into `:ok`, `:warning`, or
  `:error` status.
  """

  import Bitwise, only: [band: 2]

  alias Thunderline.Feature
  alias Thunderline.Thunderbolt.CerebrosBridge.Client

  @type check_status :: :ok | :warning | :error

  @type check_result :: %{
          required(:name) => atom(),
          required(:status) => check_status(),
          required(:message) => String.t(),
          optional(:metadata) => map()
        }

  @type validation_result :: %{
          required(:status) => check_status(),
          required(:checks) => [check_result()]
        }

  @doc """
  Run validation checks.

  Options:

    * `:require_enabled?` – if true, mark the `config.enabled?` check as error when
      disabled (default: `false`, which emits a warning instead).
  """
  @spec validate(keyword()) :: validation_result()
  def validate(opts \\ []) do
    require_enabled? = Keyword.get(opts, :require_enabled?, false)
    config = Client.config()

    checks =
      [
        feature_flag_check(),
        config_enabled_check(config, require_enabled?),
        repo_path_check(config.repo_path),
        script_path_check(config.script_path),
        python_check(config.python_executable),
        working_dir_check(config.working_dir),
        version_file_check(config.repo_path),
        cache_capacity_check(config.cache)
      ]
      |> Enum.reject(&is_nil/1)

    status =
      cond do
        Enum.any?(checks, &(&1.status == :error)) -> :error
        Enum.any?(checks, &(&1.status == :warning)) -> :warning
        true -> :ok
      end

    %{status: status, checks: checks}
  end

  defp feature_flag_check do
    enabled? = Feature.enabled?(:ml_nas, default: false)

    %{
      name: :feature_flag,
      status: if(enabled?, do: :ok, else: :error),
      message:
        if(enabled?,
          do: "Feature flag :ml_nas is enabled",
          else: "Feature flag :ml_nas is disabled"
        ),
      metadata: %{
        remediation: "Add :ml_nas to config :thunderline, :features or enable at runtime"
      }
    }
  end

  defp config_enabled_check(%{enabled?: enabled?}, require_enabled?) do
    case {enabled?, require_enabled?} do
      {true, _} ->
        %{
          name: :config_enabled,
          status: :ok,
          message: "Cerebros bridge configuration enabled"
        }

      {false, true} ->
        %{
          name: :config_enabled,
          status: :error,
          message: "Cerebros bridge config disabled (set enabled: true)",
          metadata: %{remediation: "Update config :thunderline, :cerebros_bridge -> enabled: true"}
        }

      {false, false} ->
        %{
          name: :config_enabled,
          status: :warning,
          message: "Cerebros bridge config disabled",
          metadata: %{remediation: "Set enabled: true when ready to activate"}
        }
    end
  end

  defp repo_path_check(nil) do
    %{
      name: :repo_path,
      status: :error,
      message: "Cerebros repo_path is nil",
      metadata: %{remediation: "Configure :repo_path under :cerebros_bridge"}
    }
  end

  defp repo_path_check(path) do
    if File.dir?(path) do
      %{
        name: :repo_path,
        status: :ok,
        message: "repo_path exists",
        metadata: %{path: path}
      }
    else
      %{
        name: :repo_path,
        status: :error,
        message: "repo_path not found",
        metadata: %{path: path, remediation: "Clone Cerebros repo at the configured path"}
      }
    end
  end

  defp script_path_check(nil) do
    %{
      name: :script_path,
      status: :error,
      message: "script_path is nil",
      metadata: %{remediation: "Set the Python entrypoint in :cerebros_bridge"}
    }
  end

  defp script_path_check(path) do
    cond do
      File.regular?(path) ->
        %{
          name: :script_path,
          status: :ok,
          message: "script_path exists",
          metadata: %{path: path}
        }

      File.exists?(path) ->
        %{
          name: :script_path,
          status: :warning,
          message: "script_path exists but is not a regular file",
          metadata: %{path: path, remediation: "Ensure script is a regular file"}
        }

      true ->
        %{
          name: :script_path,
          status: :error,
          message: "script_path not found",
          metadata: %{path: path, remediation: "Point to Cerebros bridge Python script"}
        }
    end
  end

  defp python_check(nil) do
    %{
      name: :python,
      status: :error,
      message: "python_executable not configured",
      metadata: %{remediation: "Set python_executable in :cerebros_bridge"}
    }
  end

  defp python_check(exec) when is_binary(exec) do
    resolved = System.find_executable(exec)

    cond do
      executable_file?(exec) ->
        %{
          name: :python,
          status: :ok,
          message: "python executable found",
          metadata: %{path: exec}
        }

      resolved && executable_file?(resolved) ->
        %{
          name: :python,
          status: :ok,
          message: "python executable discovered in PATH",
          metadata: %{command: exec, path: resolved}
        }

      true ->
        %{
          name: :python,
          status: :error,
          message: "python executable not found",
          metadata: %{
            command: exec,
            remediation: "Ensure python executable is installed and reachable"
          }
        }
    end
  end

  defp python_check(exec) do
    cond do
      executable_in_path?(exec) ->
        %{
          name: :python,
          status: :ok,
          message: "python executable discovered in PATH",
          metadata: %{command: exec}
        }

      true ->
        %{
          name: :python,
          status: :error,
          message: "python executable not found",
          metadata: %{
            command: exec,
            remediation: "Ensure python executable is installed and reachable"
          }
        }
    end
  end

  defp working_dir_check(nil), do: nil

  defp working_dir_check(dir) do
    if File.dir?(dir) do
      %{
        name: :working_dir,
        status: :ok,
        message: "working_dir exists",
        metadata: %{path: dir}
      }
    else
      %{
        name: :working_dir,
        status: :warning,
        message: "working_dir missing",
        metadata: %{path: dir, remediation: "Create working directory or adjust config"}
      }
    end
  end

  defp version_file_check(nil), do: nil

  defp version_file_check(repo_path) do
    case Client.version(repo_path) do
      {:ok, version} ->
        %{
          name: :version,
          status: :ok,
          message: "VERSION file detected (#{version})",
          metadata: %{version: version}
        }

      {:error, :version_unavailable} ->
        %{
          name: :version,
          status: :warning,
          message: "VERSION file not found",
          metadata: %{remediation: "Ensure repo contains VERSION file"}
        }
    end
  end

  defp cache_capacity_check(%{enabled?: enabled?, max_entries: max_entries}) do
    cond do
      enabled? and (is_nil(max_entries) or max_entries >= 1) ->
        %{
          name: :cache_capacity,
          status: :ok,
          message: "Cache configuration valid",
          metadata: %{max_entries: max_entries}
        }

      enabled? and max_entries in [0, -1] ->
        %{
          name: :cache_capacity,
          status: :warning,
          message: "Cache max_entries is zero",
          metadata: %{remediation: "Increase cache max_entries or disable cache"}
        }

      true ->
        %{
          name: :cache_capacity,
          status: :ok,
          message: "Cache disabled"
        }
    end
  end

  defp cache_capacity_check(_), do: nil

  defp executable_in_path?(command) when is_binary(command) do
    case System.find_executable(command) do
      nil -> false
      _ -> true
    end
  end

  defp executable_in_path?(_), do: false

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> band(mode, 0o111) > 0
      _ -> false
    end
  end
end
