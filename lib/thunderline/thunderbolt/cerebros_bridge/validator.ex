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

  @type spec_validation_result :: %{
          status: check_status(),
          errors: [String.t()],
          warnings: [String.t()],
          spec: map() | nil,
          json: String.t() | nil
        }

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

  @doc """
  Provide a default NAS specification template for operators.
  """
  @spec default_spec() :: map()
  def default_spec do
    %{
      "dataset" => "cifar10",
      "model" => "resnet18",
      "search_space_version" => 1,
      "requested_trials" => 4,
      "max_params" => 2_000_000,
      "budget" => %{"trials" => 4, "max_duration_min" => 45},
      "parameters" => %{
        "learning_rate" => %{"type" => "float", "min" => 0.0001, "max" => 0.1, "default" => 0.01},
        "momentum" => %{"type" => "choice", "values" => [0.8, 0.9, 0.95]},
        "weight_decay" => %{"type" => "float", "min" => 0.0, "max" => 0.001, "default" => 0.0001},
        "depth" => %{"type" => "choice", "values" => [18, 34]},
        "width_multiplier" => %{"type" => "float", "min" => 0.5, "max" => 2.0, "default" => 1.0}
      },
      "pulse" => %{"tau" => 0.25},
      "metadata" => %{"notes" => "Generated from CerebrosLive"}
    }
  end

  @doc """
  Validate an operator-provided NAS spec JSON or map.

  Returns a map with :status, :errors, :warnings, :spec (normalized) and :json (pretty string).
  """
  @spec validate_spec(map() | binary()) :: spec_validation_result()
  def validate_spec(spec) when is_binary(spec) do
    case Jason.decode(spec) do
      {:ok, decoded} ->
        result = validate_spec(decoded)
        Map.put(result, :json, pretty_json(decoded))

      {:error, %Jason.DecodeError{} = error} ->
        message = Exception.message(error)

        %{
          status: :error,
          errors: ["invalid_json: #{message}"],
          warnings: [],
          spec: nil,
          json: spec
        }
    end
  end

  def validate_spec(%{} = spec) do
    normalized = normalize_spec(spec)

    errors =
      []
      |> maybe_spec_error(missing_string?(normalized, "dataset"), "dataset must be a non-empty string")
      |> maybe_spec_error(missing_string?(normalized, "model"), "model must be a non-empty string")
      |> maybe_spec_error(invalid_integer?(normalized, "requested_trials", min: 1), "requested_trials must be >= 1 when present")
      |> maybe_spec_error(invalid_integer?(normalized, "search_space_version", min: 1), "search_space_version must be >= 1 when present")
      |> maybe_spec_error(invalid_max_params?(normalized), "max_params must be a positive integer")
      |> maybe_spec_error(invalid_map?(normalized, "parameters"), "parameters must be a map of hyperparameters")
      |> maybe_spec_error(invalid_budget?(normalized), "budget must be a map with positive numeric limits")

    warnings =
      []
      |> maybe_spec_warning(Map.get(normalized, "requested_trials", 0) == 0, "requested_trials is 0; run will finish immediately unless overrides supplied")
      |> maybe_spec_warning(Map.get(normalized, "parameters") in [%{}, nil], "parameters map is empty; Cerebros will use defaults")

    status =
      cond do
        errors != [] -> :error
        warnings != [] -> :warning
        true -> :ok
      end

    %{
      status: status,
      errors: errors,
      warnings: warnings,
      spec: normalized,
      json: pretty_json(normalized)
    }
  end

  def validate_spec(_other) do
    %{
      status: :error,
      errors: ["spec must be a JSON object"],
      warnings: [],
      spec: nil,
      json: nil
    }
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

  defp pretty_json(%{} = map) do
    Jason.encode!(map, pretty: true)
  rescue
    _ -> Jason.encode!(map)
  end

  defp pretty_json(value), do: to_string(value)

  defp normalize_spec(spec) do
    spec
    |> deep_stringify_keys()
    |> Map.update("budget", %{}, &deep_stringify_keys/1)
    |> Map.update("parameters", %{}, &deep_stringify_keys/1)
    |> Map.update("metadata", %{}, &deep_stringify_keys/1)
  end

  defp deep_stringify_keys(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, normalize_key(k), deep_stringify_keys(v))
    end)
  end

  defp deep_stringify_keys(list) when is_list(list), do: Enum.map(list, &deep_stringify_keys/1)
  defp deep_stringify_keys(other), do: other

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)

  defp missing_string?(map, key) do
    value = Map.get(map, key)
    not (is_binary(value) and String.trim(value) != "")
  end

  defp invalid_integer?(map, key, opts) do
    min = Keyword.get(opts, :min, 0)

    case Map.get(map, key) do
      nil -> false
      value when is_integer(value) and value >= min -> false
      value when is_integer(value) -> true
      _ -> true
    end
  end

  defp invalid_max_params?(map) do
    case Map.get(map, "max_params") do
      nil -> false
      value when is_integer(value) and value > 0 -> false
      value when is_float(value) and value > 0 -> false
      _ -> true
    end
  end

  defp invalid_map?(map, key) do
    case Map.get(map, key) do
      nil -> false
      value when is_map(value) -> false
      _ -> true
    end
  end

  defp invalid_budget?(map) do
    case Map.get(map, "budget") do
      nil -> false
      budget when is_map(budget) ->
        Enum.any?(budget, fn {_k, v} -> not valid_budget_value?(v) end)

      _ -> true
    end
  end

  defp valid_budget_value?(v) when is_integer(v) and v >= 0, do: true
  defp valid_budget_value?(v) when is_float(v) and v >= 0.0, do: true
  defp valid_budget_value?(v) when is_binary(v) do
    case Integer.parse(v) do
      {val, _} when val >= 0 -> true
      _ -> false
    end
  end

  defp valid_budget_value?(_), do: false

  defp maybe_spec_error(list, true, message), do: [message | list]
  defp maybe_spec_error(list, false, _message), do: list

  defp maybe_spec_warning(list, true, message), do: [message | list]
  defp maybe_spec_warning(list, false, _message), do: list
end
