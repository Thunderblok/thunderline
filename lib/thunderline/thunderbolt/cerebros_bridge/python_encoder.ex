defmodule Thunderline.Thunderbolt.CerebrosBridge.PythonEncoder do
  @moduledoc """
  Custom Pythonx.Encoder implementations for Cerebros bridge contract structs.
  
  These encoders ensure proper marshalling of Elixir data structures to Python objects,
  handling type conversions, nested structures, and maintaining semantic meaning across
  the language boundary.
  
  ## Important Note
  
  These custom encoders are **only used when passing contract structs directly** to Python.
  For most use cases, we normalize structs to maps first and let PythonX's built-in
  encoding handle the conversion. See `normalize_for_python/1` in `PythonxInvoker`.
  
  ## When to Use Custom Encoders
  
  Implement custom `Pythonx.Encoder` when:
  - You need special Python object creation (e.g., datetime objects)
  - You want to preserve type information beyond basic JSON types
  - You need to transform data structure shape during encoding
  
  ## Usage
  
      # Automatic encoding via protocol when passing structs directly:
      contract = %Contracts.RunStartedV1{...}
      {result, _} = Pythonx.eval(python_code, %{"contract" => contract})
      
      # Or manually:
      python_obj = Pythonx.encode!(contract)
      
  For complete guide on PythonX data passing patterns, see:
  `documentation/pythonx_integration_guide.md`
  """

  alias Thunderline.Thunderbolt.CerebrosBridge.Contracts

  # Encode RunStartedV1 contract
  defimpl Pythonx.Encoder, for: Contracts.RunStartedV1 do
    def encode(contract, _encoder) do
      # Build Python dict with proper type handling
      {result, %{}} =
        Pythonx.eval(
          """
          from datetime import datetime
          
          # Convert timestamp if present
          timestamp_str = timestamp
          if timestamp_str:
              timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
          else:
              timestamp = None
          
          # Build the contract dict
          result = {
              'run_id': run_id,
              'dataset_id': dataset_id,
              'search_space': search_space or {},
              'objective': objective or 'accuracy',
              'pulse_id': pulse_id,
              'budget': budget or {},
              'parameters': parameters or {},
              'tau': tau,
              'correlation_id': correlation_id,
              'timestamp': timestamp,
              'extra': extra or {}
          }
          """,
          %{
            "run_id" => contract.run_id,
            "dataset_id" => contract.dataset_id,
            "search_space" => contract.search_space || %{},
            "objective" => contract.objective || "accuracy",
            "pulse_id" => contract.pulse_id,
            "budget" => contract.budget || %{},
            "parameters" => contract.parameters || %{},
            "tau" => contract.tau,
            "correlation_id" => contract.correlation_id || contract.run_id,
            "timestamp" => encode_datetime(contract.timestamp),
            "extra" => contract.extra || %{}
          }
        )

      result
    end

    defp encode_datetime(nil), do: nil
    defp encode_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
    defp encode_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  end

  # Encode TrialReportedV1 contract
  defimpl Pythonx.Encoder, for: Contracts.TrialReportedV1 do
    def encode(contract, _encoder) do
      {result, %{}} =
        Pythonx.eval(
          """
          result = {
              'trial_id': trial_id,
              'run_id': run_id,
              'pulse_id': pulse_id,
              'candidate_id': candidate_id,
              'status': status,
              'metrics': metrics or {},
              'parameters': parameters or {},
              'artifact_uri': artifact_uri,
              'duration_ms': duration_ms,
              'rank': rank,
              'warnings': warnings or [],
              'spectral_norm': spectral_norm,
              'mlflow_run_id': mlflow_run_id
          }
          """,
          %{
            "trial_id" => contract.trial_id,
            "run_id" => contract.run_id,
            "pulse_id" => contract.pulse_id,
            "candidate_id" => contract.candidate_id,
            "status" => to_string(contract.status),
            "metrics" => contract.metrics || %{},
            "parameters" => contract.parameters || %{},
            "artifact_uri" => contract.artifact_uri,
            "duration_ms" => contract.duration_ms,
            "rank" => contract.rank,
            "warnings" => contract.warnings || [],
            "spectral_norm" => contract.spectral_norm,
            "mlflow_run_id" => contract.mlflow_run_id
          }
        )

      result
    end
  end

  # Encode RunFinalizedV1 contract
  defimpl Pythonx.Encoder, for: Contracts.RunFinalizedV1 do
    def encode(contract, _encoder) do
      {result, %{}} =
        Pythonx.eval(
          """
          result = {
              'run_id': run_id,
              'pulse_id': pulse_id,
              'status': status,
              'metrics': metrics or {},
              'best_trial_id': best_trial_id,
              'duration_ms': duration_ms,
              'returncode': returncode,
              'artifact_refs': artifact_refs or [],
              'warnings': warnings or [],
              'stdout_excerpt': stdout_excerpt,
              'payload': payload or {}
          }
          """,
          %{
            "run_id" => contract.run_id,
            "pulse_id" => contract.pulse_id,
            "status" => to_string(contract.status),
            "metrics" => contract.metrics || %{},
            "best_trial_id" => contract.best_trial_id,
            "duration_ms" => contract.duration_ms,
            "returncode" => contract.returncode,
            "artifact_refs" => contract.artifact_refs || [],
            "warnings" => contract.warnings || [],
            "stdout_excerpt" => contract.stdout_excerpt,
            "payload" => contract.payload || %{}
          }
        )

      result
    end
  end

  @doc """
  Helper to encode any supported contract struct to Python.
  
  ## Examples
  
      iex> contract = %Contracts.RunStartedV1{run_id: "123", timestamp: DateTime.utc_now()}
      iex> python_obj = PythonEncoder.encode(contract)
      #Pythonx.Object<{'run_id': '123', ...}>
  """
  def encode(contract) do
    Pythonx.encode!(contract)
  end

  @doc """
  Helper to convert a map to a Python dict with proper type handling.
  
  This is useful for adhoc data structures that aren't contract structs.
  """
  def encode_map(map) when is_map(map) do
    {result, %{}} =
      Pythonx.eval(
        """
        result = data
        """,
        %{"data" => normalize_map(map)}
      )

    result
  end

  # Normalize map values for Python encoding
  defp normalize_map(map) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp normalize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp normalize_value(%_{} = struct), do: normalize_map(Map.from_struct(struct))
  defp normalize_value(map) when is_map(map), do: normalize_map(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(atom) when is_atom(atom) and not is_nil(atom), do: to_string(atom)
  defp normalize_value(value), do: value
end
