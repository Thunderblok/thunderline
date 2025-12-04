defmodule Thunderline.Thunderbolt.CerebrosBridge.Translator do
  @moduledoc """
  Encodes high-level Cerebros bridge contracts into executable subprocess commands
  and decodes raw invocation results back into structured maps suitable for the
  ThunderBolt domain.

  The translator is deliberately conservative: it always funnels payload data as
  JSON via STDIN and annotates the environment with the selected operation so
  downstream scripts can route behaviour even if they ignore CLI arguments.
  """

  alias Thunderline.Thunderbolt.CerebrosBridge.Contracts
  alias __MODULE__.Overrides

  @type encoded_call :: %{
          required(:command) => String.t(),
          required(:args) => [String.t()],
          required(:env) => map(),
          optional(:working_dir) => Path.t() | nil,
          optional(:input) => iodata() | nil,
          optional(:timeout_ms) => pos_integer(),
          optional(:cache_key) => term(),
          optional(:meta) => map(),
          optional(:expect_json?) => boolean(),
          optional(:parser) => (binary() -> {:ok, map()} | {:error, term()}),
          optional(:payload) => map()
        }

  @type decoded_result :: %{
          returncode: integer(),
          stdout: binary(),
          stderr: binary(),
          stdout_excerpt: binary() | nil,
          stderr_excerpt: binary() | nil,
          attempts: pos_integer(),
          duration_ms: non_neg_integer(),
          result: map() | list() | binary() | nil,
          raw: map()
        }

  @doc """
  Encode a Cerebros bridge contract into command execution parameters.
  """
  @spec encode(atom(), term(), map(), keyword()) :: encoded_call
  def encode(op, payload, config, opts \\ [])

  def encode(:start_run, %Contracts.RunStartedV1{} = contract, config, opts) do
    # Build spec and opts for cerebros_service.run_nas
    spec = %{
      "dataset_id" => contract.dataset_id,
      "search_space" => contract.search_space || %{},
      "objective" => contract.objective || "accuracy"
    }

    run_opts = %{
      "run_id" => contract.run_id,
      "budget" => contract.budget || %{},
      "parameters" => contract.parameters || %{}
    }

    # Generate Python script that calls cerebros_service
    python_script = generate_cerebros_script(spec, run_opts)

    # Write to temp file
    script_path = write_temp_script(python_script, contract.run_id)

    build_call(:start_run, %{spec: spec, opts: run_opts}, config, opts,
      command: python_executable(config),
      script_path: script_path,
      args: [],
      base_args: [],
      env: %{
        "CEREBROS_BRIDGE_OP" => "start_run",
        "CEREBROS_BRIDGE_RUN_ID" => contract.run_id,
        "CEREBROS_BRIDGE_CORRELATION" => contract.correlation_id || contract.run_id
      },
      meta: %{
        run_id: contract.run_id,
        correlation_id: contract.correlation_id || contract.run_id,
        pulse_id: contract.pulse_id
      },
      cache_key: {:start_run, contract.run_id, contract.pulse_id},
      # 5 minutes for NAS
      timeout_ms: opts[:timeout_ms] || 300_000
    )
  end

  def encode(:record_trial, %Contracts.TrialReportedV1{} = contract, config, opts) do
    payload = contract_to_map(contract)

    build_call(:record_trial, payload, config, opts,
      env: %{
        "CEREBROS_BRIDGE_OP" => "record_trial",
        "CEREBROS_BRIDGE_RUN_ID" => contract.run_id,
        "CEREBROS_BRIDGE_TRIAL_ID" => contract.trial_id
      },
      meta: %{
        run_id: contract.run_id,
        trial_id: contract.trial_id,
        status: contract.status
      },
      cache_key: {:record_trial, contract.run_id, contract.trial_id, contract.status}
    )
  end

  def encode(:finalize_run, %Contracts.RunFinalizedV1{} = contract, config, opts) do
    payload = contract_to_map(contract)

    build_call(:finalize_run, payload, config, opts,
      env: %{
        "CEREBROS_BRIDGE_OP" => "finalize_run",
        "CEREBROS_BRIDGE_RUN_ID" => contract.run_id,
        "CEREBROS_BRIDGE_STATUS" => Atom.to_string(contract.status)
      },
      meta: %{
        run_id: contract.run_id,
        status: contract.status,
        pulse_id: contract.pulse_id
      },
      cache_key: {:finalize_run, contract.run_id, contract.status}
    )
  end

  def encode(op, payload, config, opts) when is_atom(op) do
    payload_map = normalize_value(payload) || %{}

    build_call(op, payload_map, config, opts,
      env: %{"CEREBROS_BRIDGE_OP" => Atom.to_string(op)},
      meta: %{op: op}
    )
  end

  @doc """
  Decode a raw invocation response produced by the invoker into a friendly map.
  """
  @spec decode(atom(), term(), map(), map(), keyword()) :: decoded_result
  def decode(_op, _payload, raw, _config, _opts \\ []) do
    base =
      raw
      |> Map.take([
        :returncode,
        :stdout,
        :stderr,
        :stdout_excerpt,
        :stderr_excerpt,
        :attempts,
        :duration_ms
      ])
      |> Enum.into(%{})

    result =
      cond do
        is_map(raw[:parsed]) -> raw[:parsed]
        is_list(raw[:parsed]) -> raw[:parsed]
        true -> parse_json(raw[:stdout])
      end

    Map.merge(base, %{
      result: result,
      raw: raw
    })
  end

  # -- helpers ----------------------------------------------------------------

  defp build_call(op, payload, config, opts, overrides) do
    script_path =
      Overrides.get(overrides, :script_path) ||
        Keyword.get(opts, :script_path) ||
        Map.get(config, :script_path)

    command =
      Overrides.get(overrides, :command) ||
        Keyword.get(opts, :command) ||
        Map.get(config, :python_executable) ||
        "python3"

    additional_args =
      overrides
      |> Overrides.get(:args, [])
      |> Kernel.++(Keyword.get(opts, :args, []))

    base_args = Keyword.get(opts, :base_args, ["--bridge-op", Atom.to_string(op)])

    # Build args based on whether script_path exists
    args =
      if script_path do
        [script_path | base_args ++ additional_args]
      else
        base_args ++ additional_args
      end

    merged_env =
      config
      |> Map.get(:env, %{})
      |> Map.merge(Keyword.get(opts, :env, %{}))
      |> Map.merge(Overrides.get(overrides, :env, %{}))

    meta =
      %{
        op: op
      }
      |> Map.merge(Keyword.get(opts, :meta, %{}))
      |> Map.merge(Overrides.get(overrides, :meta, %{}))

    cache_key =
      Overrides.get(overrides, :cache_key) ||
        Keyword.get(opts, :cache_key)

    timeout_ms =
      Overrides.get(overrides, :timeout_ms) ||
        Keyword.get(opts, :timeout_ms)

    expect_json? =
      Keyword.get(opts, :expect_json?, true)

    parser =
      Keyword.get(opts, :parser)

    payload_json =
      Jason.encode!(%{
        op: Atom.to_string(op),
        payload: payload
      })

    %{
      command: command,
      args: Enum.map(args, &to_string/1),
      env: merged_env |> Map.put_new("CEREBROS_BRIDGE_PAYLOAD", payload_json),
      working_dir:
        Keyword.get(opts, :working_dir) || Map.get(config, :working_dir) ||
          Map.get(config, :repo_path),
      input: Keyword.get(opts, :input) || payload_json,
      timeout_ms: timeout_ms,
      cache_key: cache_key,
      meta: meta,
      expect_json?: expect_json?,
      parser: parser,
      payload: payload
    }
  end

  defp contract_to_map(struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
    |> Enum.into(%{})
  end

  defp normalize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp normalize_value(%_struct{} = value), do: contract_to_map(value)

  defp normalize_value(%{} = value),
    do: Enum.into(value, %{}, fn {k, v} -> {k, normalize_value(v)} end)

  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value

  defp parse_json(nil), do: nil

  defp parse_json(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, decoded} -> decoded
      _ -> nil
    end
  end

  # -- cerebros_service helpers -----------------------------------------------

  defp python_executable(config) do
    Map.get(config, :python_executable) ||
      System.get_env("CEREBROS_PYTHON") ||
      Path.expand(".venv/bin/python")
  end

  defp generate_cerebros_script(spec, opts) do
    # Get absolute path to cerebros service directory
    cerebros_path = Path.join(File.cwd!(), "python/cerebros")
    cerebros_core_path = Path.join(File.cwd!(), "python/cerebros/core")
    cerebros_service_path = Path.join(File.cwd!(), "python/cerebros/service")

    """
    import sys
    import json
    sys.path.insert(0, '#{cerebros_path}')
    sys.path.insert(0, '#{cerebros_core_path}')
    sys.path.insert(0, '#{cerebros_service_path}')
    import cerebros_service

    spec = #{Jason.encode!(spec)}
    opts = #{Jason.encode!(opts)}

    result = cerebros_service.run_nas(spec, opts)
    print(json.dumps(result))
    """
  end

  defp write_temp_script(script_content, run_id) do
    temp_dir = Path.join(System.tmp_dir!(), "cerebros_scripts")
    File.mkdir_p!(temp_dir)

    script_path =
      Path.join(
        temp_dir,
        "cerebros_#{run_id}_#{:os.system_time(:millisecond)}.py"
      )

    File.write!(script_path, script_content)
    script_path
  end

  defmodule Overrides do
    @moduledoc false

    def get(overrides, key, default \\ %{}) do
      case Keyword.fetch(overrides, key) do
        {:ok, value} -> value
        :error -> default
      end
    end

    def get!(overrides, key) do
      case Keyword.fetch(overrides, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end
  end
end
