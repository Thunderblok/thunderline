defmodule Thunderline.Support.ErrorKinds do
  @moduledoc """
  Centralized error classification for consistent retry and telemetry behavior.
  
  Classifies errors into categories to help determine retry strategy:
  - `:transient` - Temporary failures that should be retried (network, timeouts)
  - `:permanent` - Permanent failures that should not be retried (validation, constraints)
  - `:unknown` - Unclassified errors (default to retry with caution)
  
  ## Usage
  
      case Thunderline.Support.ErrorKinds.classify(error) do
        {:transient, tag} -> {:error, tag}  # Oban will retry
        {:permanent, tag} -> {:discard, tag}  # Oban will discard
        {:unknown, tag} -> {:error, tag}  # Oban will retry with caution
      end
      
  ## Adding New Error Types
  
  Add new patterns to `classify/1` based on your application's error patterns.
  Prioritize precision to avoid unnecessary retries or premature discarding.
  """
  
  @type kind :: :transient | :permanent | :unknown
  @type tag :: atom()
  
  @doc """
  Classify an error into transient, permanent, or unknown categories.
  
  Returns a tuple of `{kind, tag}` for consistent error handling.
  """
  @spec classify(term()) :: {kind(), tag()}
  
  # Database connection errors (transient)
  def classify(%Postgrex.Error{postgres: %{code: :connection_failure}}), 
    do: {:transient, :db_connection_failure}
  def classify(%Postgrex.Error{postgres: %{code: :cannot_connect_now}}), 
    do: {:transient, :db_cannot_connect}
  def classify(%DBConnection.ConnectionError{}), 
    do: {:transient, :db_connection_error}
  def classify(%DBConnection.OwnershipError{}), 
    do: {:transient, :db_ownership_error}
    
  # Network and HTTP errors (transient)
  def classify(%Mint.TransportError{reason: :timeout}), 
    do: {:transient, :http_timeout}
  def classify(%Mint.TransportError{}), 
    do: {:transient, :network_transport}
  def classify(%HTTPoison.Error{reason: :timeout}), 
    do: {:transient, :http_timeout}
  def classify(%HTTPoison.Error{reason: :connect_timeout}), 
    do: {:transient, :http_connect_timeout}
  def classify(%HTTPoison.Error{reason: :checkout_timeout}), 
    do: {:transient, :http_checkout_timeout}
    
  # JSON and data format errors (permanent)
  def classify(%Jason.DecodeError{}), 
    do: {:permanent, :invalid_json}
  def classify(%Jason.EncodeError{}), 
    do: {:permanent, :json_encode_error}
    
  # Database constraint errors (permanent)
  def classify(%Ecto.ConstraintError{type: :unique}), 
    do: {:permanent, :unique_constraint}
  def classify(%Ecto.ConstraintError{type: :foreign_key}), 
    do: {:permanent, :foreign_key_constraint}
  def classify(%Ecto.ConstraintError{}), 
    do: {:permanent, :constraint_violation}
  def classify(%Ecto.InvalidChangesetError{}), 
    do: {:permanent, :invalid_changeset}
    
  # Validation errors (permanent)
  def classify(%Ash.Error.Invalid{}), 
    do: {:permanent, :ash_validation_error}
  def classify(%ArgumentError{}), 
    do: {:permanent, :invalid_arguments}
    
  # Application-specific errors
  def classify({:error, :timeout}), 
    do: {:transient, :timeout}
  def classify({:error, :circuit_open}), 
    do: {:transient, :circuit_breaker_open}
  def classify({:error, :emit_failed}), 
    do: {:transient, :event_emit_failed}
  def classify({:error, :invalid_event}), 
    do: {:permanent, :invalid_event_format}
  def classify({:error, :missing_fields}), 
    do: {:permanent, :required_fields_missing}
  def classify({:error, :unknown_domain}), 
    do: {:permanent, :unknown_target_domain}
  def classify({:error, :missing_event}), 
    do: {:permanent, :missing_event_argument}
    
  # System errors (transient)
  def classify(:timeout), 
    do: {:transient, :erlang_timeout}
  def classify({:timeout, _}), 
    do: {:transient, :gen_timeout}
  def classify({:noproc, _}), 
    do: {:transient, :process_not_found}
  def classify({:shutdown, _}), 
    do: {:transient, :process_shutdown}
    
  # Broadway/GenStage errors (transient) 
  def classify(%Broadway.NoProducersAvailable{}), 
    do: {:transient, :no_producers_available}
    
  # Catch-all for unclassified errors
  def classify({:error, reason}) when is_atom(reason), 
    do: {:unknown, reason}
  def classify({:error, reason}) when is_binary(reason), 
    do: {:unknown, :string_error}
  def classify(error) when is_exception(error), 
    do: {:unknown, error.__struct__ |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()}
  def classify(_error), 
    do: {:unknown, :unclassified}
    
  @doc """
  Check if an error kind should be retried.
  """
  @spec should_retry?(kind()) :: boolean()
  def should_retry?(:transient), do: true
  def should_retry?(:permanent), do: false  
  def should_retry?(:unknown), do: true  # Err on the side of retrying
  
  @doc """
  Get a human-readable description of an error kind.
  """
  @spec describe(kind()) :: String.t()
  def describe(:transient), do: "Temporary failure - will retry"
  def describe(:permanent), do: "Permanent failure - will not retry" 
  def describe(:unknown), do: "Unknown error type - will retry with caution"
  
  @doc """
  Get statistics about error classification for monitoring.
  """
  def classification_stats do
    %{
      transient_patterns: count_patterns(:transient),
      permanent_patterns: count_patterns(:permanent),
      unknown_fallback: 1
    }
  end
  
  # Count how many classification patterns exist for each kind
  defp count_patterns(kind) do
    __MODULE__.__info__(:functions)
    |> Enum.filter(fn {name, arity} -> name == :classify and arity == 1 end)
    |> length()
    # This is a rough approximation - in practice you'd need to analyze the AST
  end
end