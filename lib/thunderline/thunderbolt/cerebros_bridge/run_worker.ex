defmodule Thunderline.Thunderbolt.CerebrosBridge.RunWorker do
  @moduledoc """
  Oban worker responsible for orchestrating Cerebros NAS executions via the
  bridge Client. This is the single owner of the `start_run/record_trial/
  finalize_run` lifecycle so that all subprocess calls share common telemetry
  and persistence semantics.

  ## Expected job args

    * "run_id" - External run identifier (defaults to generated UUID)
    * "spec" - Map describing the NAS search spec (search space, priors, etc.)
    * "budget" - Optional budget constraints map
    * "parameters" - Optional parameter overrides map
    * "tau" - Optional exploration temperature
    * "pulse_id" - Optional pulse identifier
    * "correlation_id" - Optional correlation id for telemetry
    * "extra" - Optional bag of additional values stored with the run
    * "meta" - Metadata map propagated to telemetry/EventBus

  The external Python bridge script is expected to read payload JSON from STDIN
  and emit JSON describing trials and aggregate metrics. The worker tolerates
  partial payloads by falling back to defaults whenever possible.
  """
  use Oban.Worker, queue: :ml, max_attempts: 1

  alias Thunderline.Thunderbolt.CerebrosBridge.{Client, Contracts, Persistence}
  alias Thunderline.Thunderflow.ErrorClass

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when is_map(args) do
    if Client.enabled?() do
      do_perform(args)
    else
      {:discard, :bridge_disabled}
    end
  end

  def perform(_job), do: {:discard, :invalid_args}

  defp do_perform(args) do
    run_id = Map.get(args, "run_id") || default_run_id()
    meta = Map.get(args, "meta", %{}) |> normalize_string_keys()
    spec = Map.get(args, "spec", %{}) |> normalize_string_keys()
    budget = Map.get(args, "budget", %{}) |> normalize_string_keys()
    parameters = Map.get(args, "parameters", %{}) |> normalize_string_keys()
    tau = Map.get(args, "tau")
    pulse_id = Map.get(args, "pulse_id")
    correlation_id = Map.get(args, "correlation_id") || run_id
    extra = Map.get(args, "extra", %{}) |> normalize_string_keys()

    start_contract = %Contracts.RunStartedV1{
      run_id: run_id,
      pulse_id: pulse_id,
      budget: budget,
      parameters: parameters,
      tau: tau,
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      extra: extra
    }

    with {:ok, _run_record} <- Persistence.ensure_run_record(start_contract, spec),
         {:ok, start_resp} <- Client.start_run(start_contract, meta: meta),
         :ok <- Persistence.record_run_started(start_contract, start_resp, spec),
         :ok <- process_trials(run_id, start_resp, meta, spec),
         finalize_contract <- build_finalize_contract(run_id, start_contract, start_resp, spec),
         {:ok, finalize_resp} <- Client.finalize_run(finalize_contract, meta: meta),
         :ok <- Persistence.record_run_finalized(finalize_contract, finalize_resp, spec) do
      :ok
    else
      {:error, %ErrorClass{} = error} = err ->
        Persistence.record_run_failed(run_id, error, spec)
        err

      {:error, reason} = err ->
        error = unexpected_error(run_id, reason)
        Persistence.record_run_failed(run_id, error, spec)
        err
    end
  end

  defp process_trials(run_id, start_resp, meta, spec) do
    trials = extract_trials(start_resp)

    Enum.reduce_while(trials, :ok, fn trial_map, _acc ->
      contract = build_trial_contract(run_id, trial_map)

      case Client.record_trial(contract, meta: meta) do
        {:ok, trial_resp} ->
          :ok = Persistence.record_trial_reported(contract, trial_resp, spec)
          {:cont, :ok}

        {:error, %ErrorClass{} = error} ->
          Persistence.record_run_failed(run_id, error, spec)
          {:halt, {:error, error}}

        {:error, reason} ->
          error = unexpected_error(run_id, reason)
          Persistence.record_run_failed(run_id, error, spec)
          {:halt, {:error, error}}
      end
    end)
  end

  defp build_trial_contract(run_id, trial_map) do
    {warnings, rest} = Map.pop(trial_map, "warnings", [])

    %Contracts.TrialReportedV1{
      run_id: run_id,
      trial_id: fetch(trial_map, :trial_id, default_trial_id()),
      pulse_id: fetch(trial_map, :pulse_id),
      candidate_id: fetch(trial_map, :candidate_id),
      status: fetch_status(trial_map),
      metrics: fetch(rest, :metrics, %{}),
      parameters: fetch(rest, :parameters, %{}),
      artifact_uri: fetch(rest, :artifact_uri),
      duration_ms: fetch(rest, :duration_ms),
      rank: fetch(rest, :rank),
      warnings: normalize_warnings(warnings)
    }
  end

  defp build_finalize_contract(run_id, start_contract, start_resp, spec) do
    result = extract_result(start_resp)

    %Contracts.RunFinalizedV1{
      run_id: run_id,
      pulse_id: start_contract.pulse_id,
      status: fetch_status(result, :status, :succeeded),
      metrics: fetch(result, :metrics, %{}),
      best_trial_id: fetch(result, :best_trial_id),
      duration_ms: fetch(result, :duration_ms) || start_resp[:duration_ms],
      returncode: start_resp[:returncode],
      artifact_refs: fetch(result, :artifact_refs, []),
      warnings: fetch(result, :warnings, []),
      stdout_excerpt: start_resp[:stdout_excerpt],
      payload: %{result: result, spec: spec}
    }
  end

  defp extract_trials(start_resp) do
    start_resp
    |> extract_result()
    |> fetch(:trials, [])
    |> normalize_list_of_maps()
  end

  defp extract_result(resp) do
    cond do
      is_map(resp[:result]) -> resp[:result]
      is_map(resp["result"]) -> resp["result"]
      is_map(resp[:parsed]) -> resp[:parsed]
      is_map(resp["parsed"]) -> resp["parsed"]
      true -> %{}
    end
    |> normalize_string_keys()
  end

  defp fetch(map, key, default \\ nil) when is_map(map) do
    map
    |> do_fetch(key)
    |> case do
      nil -> default
      value -> value
    end
  end

  defp fetch(_map, _key, default), do: default

  defp do_fetch(map, key) when is_atom(key) do
    case Map.fetch(map, Atom.to_string(key)) do
      {:ok, value} -> value
      :error -> Map.get(map, key)
    end
  end

  defp do_fetch(map, key) when is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error ->
        case key_to_existing_atom(key) do
          nil -> nil
          atom_key -> Map.get(map, atom_key)
        end
    end
  end

  defp do_fetch(map, key) when is_integer(key) do
    Map.get(map, key)
  end

  defp do_fetch(_map, _key), do: nil

  defp fetch_status(map), do: fetch_status(map, :status, :succeeded)

  defp fetch_status(map, key, default) do
    map
    |> fetch(key, default)
    |> normalize_status(default)
  end

  defp normalize_status(value, _default) when value in [:succeeded, :failed, :cancelled, :timeout],
    do: value

  defp normalize_status(value, default) when is_atom(value), do: default

  defp normalize_status(value, default) when is_binary(value) do
    case String.downcase(value) do
      "succeeded" -> :succeeded
      "failed" -> :failed
      "cancelled" -> :cancelled
      "canceled" -> :cancelled
      "timeout" -> :timeout
      _ -> default
    end
  end

  defp normalize_status(_value, default), do: default

  defp normalize_warnings(list) when is_list(list),
    do: Enum.map(list, &to_string/1)

  defp normalize_warnings(nil), do: []
  defp normalize_warnings(other), do: [to_string(other)]

  defp normalize_list_of_maps(value) when is_list(value) do
    Enum.map(value, fn
      item when is_map(item) -> normalize_string_keys(item)
      other -> %{"value" => other}
    end)
  end

  defp normalize_list_of_maps(_), do: []

  defp normalize_string_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), value)
    end)
  end

  defp normalize_string_keys(other), do: other

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)

  defp key_to_existing_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      _ -> nil
    end
  end

  defp key_to_existing_atom(key) when is_atom(key), do: key
  defp key_to_existing_atom(_), do: nil

  defp default_run_id do
    if Code.ensure_loaded?(Thunderline.UUID) and
         function_exported?(Thunderline.UUID, :v7, 0) do
      Thunderline.UUID.v7()
    else
      Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    end
  end

  defp default_trial_id, do: default_run_id()

  defp unexpected_error(run_id, reason) do
    %ErrorClass{
      origin: :cerebros_bridge,
      class: :exception,
      severity: :error,
      visibility: :internal,
      context: %{run_id: run_id, reason: inspect(reason)}
    }
  end
end
