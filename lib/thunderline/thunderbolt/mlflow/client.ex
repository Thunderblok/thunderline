defmodule Thunderline.Thunderbolt.MLflow.Client do
  @moduledoc """
  HTTP client for MLflow REST API.
  
  Provides functions to interact with MLflow tracking server for:
  - Creating and managing experiments
  - Creating and updating runs
  - Logging metrics, parameters, and tags
  - Retrieving run and experiment metadata
  
  Uses Req for HTTP requests with automatic JSON encoding/decoding.
  """

  require Logger

  @type mlflow_error :: {:error, :network_error | :invalid_response | :not_found | atom()}

  @doc """
  Get the MLflow tracking URI from configuration or environment.
  """
  def tracking_uri do
    Application.get_env(:thunderline, :mlflow_tracking_uri) ||
      System.get_env("MLFLOW_TRACKING_URI") ||
      "http://localhost:5000"
  end

  @doc """
  Create a new experiment in MLflow.
  
  ## Parameters
  - name: Experiment name (required)
  - artifact_location: S3/local path for artifacts (optional)
  - tags: Map of experiment tags (optional)
  
  ## Returns
  - {:ok, %{experiment_id: string}}
  - {:error, reason}
  """
  def create_experiment(name, opts \\ []) do
    body = %{
      name: name,
      artifact_location: opts[:artifact_location],
      tags: format_tags(opts[:tags])
    }

    post("/api/2.0/mlflow/experiments/create", body)
    |> case do
      {:ok, %{status: 200, body: %{"experiment_id" => exp_id}}} ->
        {:ok, %{experiment_id: exp_id}}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MLflow create_experiment failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get experiment by ID.
  
  ## Returns
  - {:ok, experiment_map}
  - {:error, :not_found | reason}
  """
  def get_experiment(experiment_id) do
    get("/api/2.0/mlflow/experiments/get", experiment_id: experiment_id)
    |> case do
      {:ok, %{status: 200, body: %{"experiment" => exp}}} ->
        {:ok, normalize_experiment(exp)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MLflow get_experiment failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a new run within an experiment.
  
  ## Parameters
  - experiment_id: MLflow experiment ID
  - opts: Keyword list with :run_name, :start_time, :tags
  
  ## Returns
  - {:ok, %{run_id: string, run_uuid: string}}
  - {:error, reason}
  """
  def create_run(experiment_id, opts \\ []) do
    body = %{
      experiment_id: experiment_id,
      run_name: opts[:run_name],
      start_time: opts[:start_time] || unix_millis(),
      tags: format_tags(opts[:tags])
    }

    post("/api/2.0/mlflow/runs/create", body)
    |> case do
      {:ok, %{status: 200, body: %{"run" => run}}} ->
        {:ok, %{run_id: run["info"]["run_id"], run_uuid: run["info"]["run_uuid"]}}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MLflow create_run failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get run by ID.
  
  ## Returns
  - {:ok, run_map}
  - {:error, :not_found | reason}
  """
  def get_run(run_id) do
    get("/api/2.0/mlflow/runs/get", run_id: run_id)
    |> case do
      {:ok, %{status: 200, body: %{"run" => run}}} ->
        {:ok, normalize_run(run)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MLflow get_run failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update run status.
  
  ## Parameters
  - run_id: MLflow run ID
  - status: One of "RUNNING", "SCHEDULED", "FINISHED", "FAILED", "KILLED"
  - end_time: Unix timestamp in milliseconds (optional)
  """
  def update_run(run_id, status, opts \\ []) do
    body = %{
      run_id: run_id,
      status: String.upcase(to_string(status)),
      end_time: opts[:end_time]
    }

    post("/api/2.0/mlflow/runs/update", body)
    |> case do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MLflow update_run failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Log a single metric value for a run.
  
  ## Parameters
  - run_id: MLflow run ID
  - key: Metric name
  - value: Metric value (numeric)
  - timestamp: Unix timestamp in milliseconds (optional)
  - step: Training step/epoch number (optional, defaults to 0)
  """
  def log_metric(run_id, key, value, opts \\ []) do
    body = %{
      run_id: run_id,
      key: key,
      value: value,
      timestamp: opts[:timestamp] || unix_millis(),
      step: opts[:step] || 0
    }

    post("/api/2.0/mlflow/runs/log-metric", body)
    |> handle_log_response("log_metric")
  end

  @doc """
  Log multiple metrics for a run in batch.
  
  ## Parameters
  - run_id: MLflow run ID
  - metrics: Map of %{key => value} or list of maps with :key, :value, :timestamp, :step
  """
  def log_batch_metrics(run_id, metrics) when is_map(metrics) do
    metrics_list =
      Enum.map(metrics, fn {key, value} ->
        %{
          key: to_string(key),
          value: value,
          timestamp: unix_millis(),
          step: 0
        }
      end)

    log_batch(run_id, metrics: metrics_list)
  end

  def log_batch_metrics(run_id, metrics) when is_list(metrics) do
    log_batch(run_id, metrics: metrics)
  end

  @doc """
  Log a single parameter for a run.
  
  ## Parameters
  - run_id: MLflow run ID
  - key: Parameter name
  - value: Parameter value (will be converted to string)
  """
  def log_param(run_id, key, value) do
    body = %{
      run_id: run_id,
      key: key,
      value: to_string(value)
    }

    post("/api/2.0/mlflow/runs/log-parameter", body)
    |> handle_log_response("log_param")
  end

  @doc """
  Log multiple parameters for a run in batch.
  
  ## Parameters
  - run_id: MLflow run ID
  - params: Map of %{key => value}
  """
  def log_batch_params(run_id, params) when is_map(params) do
    params_list =
      Enum.map(params, fn {key, value} ->
        %{key: to_string(key), value: to_string(value)}
      end)

    log_batch(run_id, params: params_list)
  end

  @doc """
  Set a tag on a run.
  
  ## Parameters
  - run_id: MLflow run ID
  - key: Tag key
  - value: Tag value
  """
  def set_tag(run_id, key, value) do
    body = %{
      run_id: run_id,
      key: key,
      value: to_string(value)
    }

    post("/api/2.0/mlflow/runs/set-tag", body)
    |> handle_log_response("set_tag")
  end

  @doc """
  Log metrics, parameters, and tags in a single batch request.
  
  ## Parameters
  - run_id: MLflow run ID
  - opts: Keyword list with :metrics, :params, :tags (all lists of maps)
  """
  def log_batch(run_id, opts \\ []) do
    body = %{
      run_id: run_id,
      metrics: opts[:metrics] || [],
      params: opts[:params] || [],
      tags: opts[:tags] || []
    }

    post("/api/2.0/mlflow/runs/log-batch", body)
    |> handle_log_response("log_batch")
  end

  # -- HTTP helpers --

  defp get(path, params \\ []) do
    url = tracking_uri() <> path

    Req.get(url, params: params, receive_timeout: 30_000)
    |> case do
      {:ok, response} -> {:ok, response}
      {:error, %Req.TransportError{reason: reason}} -> {:error, {:network_error, reason}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      Logger.error("MLflow GET #{path} exception: #{inspect(error)}")
      {:error, :request_exception}
  end

  defp post(path, body) do
    url = tracking_uri() <> path

    Req.post(url, json: body, receive_timeout: 30_000)
    |> case do
      {:ok, response} -> {:ok, response}
      {:error, %Req.TransportError{reason: reason}} -> {:error, {:network_error, reason}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      Logger.error("MLflow POST #{path} exception: #{inspect(error)}")
      {:error, :request_exception}
  end

  defp handle_log_response(result, operation) do
    case result do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MLflow #{operation} failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Data formatting --

  defp format_tags(nil), do: []

  defp format_tags(tags) when is_map(tags) do
    Enum.map(tags, fn {key, value} ->
      %{key: to_string(key), value: to_string(value)}
    end)
  end

  defp format_tags(tags) when is_list(tags), do: tags

  defp normalize_experiment(exp) do
    %{
      experiment_id: exp["experiment_id"],
      name: exp["name"],
      artifact_location: exp["artifact_location"],
      lifecycle_stage: String.downcase(exp["lifecycle_stage"]) |> String.to_atom(),
      tags: parse_tags(exp["tags"])
    }
  end

  defp normalize_run(run) do
    info = run["info"]
    data = run["data"] || %{}

    %{
      run_id: info["run_id"] || info["run_uuid"],
      experiment_id: info["experiment_id"],
      run_name: info["run_name"],
      status: String.downcase(info["status"]) |> String.to_atom(),
      start_time: info["start_time"],
      end_time: info["end_time"],
      lifecycle_stage: String.downcase(info["lifecycle_stage"]) |> String.to_atom(),
      artifact_uri: info["artifact_uri"],
      params: parse_params(data["params"]),
      metrics: parse_metrics(data["metrics"]),
      tags: parse_tags(data["tags"])
    }
  end

  defp parse_tags(nil), do: %{}

  defp parse_tags(tags) when is_list(tags) do
    Enum.into(tags, %{}, fn tag -> {tag["key"], tag["value"]} end)
  end

  defp parse_tags(tags) when is_map(tags), do: tags

  defp parse_params(nil), do: %{}

  defp parse_params(params) when is_list(params) do
    Enum.into(params, %{}, fn param -> {param["key"], param["value"]} end)
  end

  defp parse_params(params) when is_map(params), do: params

  defp parse_metrics(nil), do: %{}

  defp parse_metrics(metrics) when is_list(metrics) do
    Enum.into(metrics, %{}, fn metric -> {metric["key"], metric["value"]} end)
  end

  defp parse_metrics(metrics) when is_map(metrics), do: metrics

  defp unix_millis do
    System.system_time(:millisecond)
  end
end
