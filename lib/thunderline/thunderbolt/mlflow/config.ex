defmodule Thunderline.Thunderbolt.MLflow.Config do
  @moduledoc """
  Configuration management for MLflow integration.

  Centralizes MLflow-related settings from application config and environment variables.
  Provides feature flags to enable/disable MLflow integration.
  """

  @doc """
  Get the MLflow tracking URI.

  Priority:
  1. Application config: `config :thunderline, :mlflow_tracking_uri`
  2. Environment variable: `MLFLOW_TRACKING_URI`
  3. Default: `http://localhost:5000`

  ## Examples

      iex> Config.tracking_uri()
      "http://mlflow.example.com:5000"
  """
  def tracking_uri do
    Application.get_env(:thunderline, :mlflow_tracking_uri) ||
      System.get_env("MLFLOW_TRACKING_URI") ||
      "http://localhost:5000"
  end

  @doc """
  Check if MLflow integration is enabled.

  MLflow is considered enabled if:
  - Feature flag is explicitly enabled, OR
  - MLFLOW_TRACKING_URI is configured (not localhost or nil)

  Can be disabled by setting environment variable:
  - `MLFLOW_ENABLED=false`
  - `TL_DISABLE_MLFLOW=true`

  ## Examples

      iex> Config.enabled?()
      true
  """
  def enabled? do
    # Check explicit disable flags first
    cond do
      System.get_env("MLFLOW_ENABLED") == "false" ->
        false

      System.get_env("TL_DISABLE_MLFLOW") == "true" ->
        false

      # Check application config
      Application.get_env(:thunderline, :mlflow_enabled) == false ->
        false

      # If tracking URI is set to something other than localhost, consider it enabled
      tracking_uri() != "http://localhost:5000" ->
        true

      # Check if explicitly enabled via feature flag
      Application.get_env(:thunderline, :mlflow_enabled) == true ->
        true

      # Default: disabled if using localhost (dev environment)
      true ->
        false
    end
  end

  @doc """
  Get the default experiment name for Thunderline trials.

  Can be configured via:
  - Application config: `config :thunderline, :mlflow_default_experiment`
  - Environment variable: `MLFLOW_DEFAULT_EXPERIMENT`
  - Default: `"thunderline-trials"`

  ## Examples

      iex> Config.default_experiment_name()
      "thunderline-trials"
  """
  def default_experiment_name do
    Application.get_env(:thunderline, :mlflow_default_experiment) ||
      System.get_env("MLFLOW_DEFAULT_EXPERIMENT") ||
      "thunderline-trials"
  end

  @doc """
  Get the default artifact location for experiments.

  Can be configured via:
  - Application config: `config :thunderline, :mlflow_artifact_location`
  - Environment variable: `MLFLOW_ARTIFACT_LOCATION`
  - Default: `nil` (MLflow will use its default)

  ## Examples

      iex> Config.artifact_location()
      "s3://my-bucket/mlflow-artifacts"
  """
  def artifact_location do
    Application.get_env(:thunderline, :mlflow_artifact_location) ||
      System.get_env("MLFLOW_ARTIFACT_LOCATION")
  end

  @doc """
  Get the sync interval for background synchronization (in seconds).

  Can be configured via:
  - Application config: `config :thunderline, :mlflow_sync_interval`
  - Environment variable: `MLFLOW_SYNC_INTERVAL`
  - Default: `300` (5 minutes)

  ## Examples

      iex> Config.sync_interval()
      300
  """
  def sync_interval do
    case Application.get_env(:thunderline, :mlflow_sync_interval) ||
           System.get_env("MLFLOW_SYNC_INTERVAL") do
      nil -> 300
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @doc """
  Get the request timeout for MLflow API calls (in milliseconds).

  Can be configured via:
  - Application config: `config :thunderline, :mlflow_request_timeout`
  - Environment variable: `MLFLOW_REQUEST_TIMEOUT`
  - Default: `30_000` (30 seconds)

  ## Examples

      iex> Config.request_timeout()
      30000
  """
  def request_timeout do
    case Application.get_env(:thunderline, :mlflow_request_timeout) ||
           System.get_env("MLFLOW_REQUEST_TIMEOUT") do
      nil -> 30_000
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @doc """
  Check if automatic syncing should occur when trials complete.

  When enabled, trials will automatically sync to MLflow on completion.
  When disabled, syncing must be triggered manually.

  Can be configured via:
  - Application config: `config :thunderline, :mlflow_auto_sync`
  - Environment variable: `MLFLOW_AUTO_SYNC`
  - Default: `true`

  ## Examples

      iex> Config.auto_sync?()
      true
  """
  def auto_sync? do
    case Application.get_env(:thunderline, :mlflow_auto_sync) ||
           System.get_env("MLFLOW_AUTO_SYNC") do
      false -> false
      "false" -> false
      nil -> true
      _ -> true
    end
  end

  @doc """
  Check if MLflow integration should fail silently on errors.

  When true, MLflow errors won't break trial completion.
  When false, MLflow errors will be logged but trials will still complete.

  Can be configured via:
  - Application config: `config :thunderline, :mlflow_fail_silently`
  - Environment variable: `MLFLOW_FAIL_SILENTLY`
  - Default: `true` (don't break trials on MLflow errors)

  ## Examples

      iex> Config.fail_silently?()
      true
  """
  def fail_silently? do
    case Application.get_env(:thunderline, :mlflow_fail_silently) ||
           System.get_env("MLFLOW_FAIL_SILENTLY") do
      false -> false
      "false" -> false
      nil -> true
      _ -> true
    end
  end

  @doc """
  Get all MLflow configuration as a map for debugging/inspection.

  ## Examples

      iex> Config.all()
      %{
        tracking_uri: "http://localhost:5000",
        enabled: false,
        default_experiment: "thunderline-trials",
        ...
      }
  """
  def all do
    %{
      tracking_uri: tracking_uri(),
      enabled: enabled?(),
      default_experiment: default_experiment_name(),
      artifact_location: artifact_location(),
      sync_interval: sync_interval(),
      request_timeout: request_timeout(),
      auto_sync: auto_sync?(),
      fail_silently: fail_silently?()
    }
  end
end
