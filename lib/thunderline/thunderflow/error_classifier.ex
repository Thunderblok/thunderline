defmodule Thunderline.Thunderflow.ErrorClassifier do
  @moduledoc """
  Heuristic error classifier for unified error handling (HC-09).

  Classifies errors into structured `ErrorClass` structs to drive:
  - Broadway retry vs DLQ routing
  - Telemetry aggregation & SLO definition
  - User vs system error separation for UI messaging
  - Policy-based escalation (alerting for systemic faults)

  ## Classification Dimensions

  | Dimension | Values | Drives |
  |-----------|--------|--------|
  | Origin | `:user`, `:system`, `:external`, `:infrastructure` | Messaging & ownership |
  | Class | `:validation`, `:transient`, `:permanent`, `:timeout`, `:dependency`, `:security` | Retry / DLQ strategy |
  | Severity | `:info`, `:warn`, `:error`, `:critical` | Alert thresholds |
  | Visibility | `:user_safe`, `:internal_only` | Exposure filtering |

  ## Retry Matrix

  | Class | Max Attempts | Backoff |
  |-------|--------------|---------|
  | transient | 5 | 500 * 2^n |
  | timeout | 3 | 1000 * 2^n |
  | dependency | 7 | 1000 * 1.5^n |
  | permanent | 0 | none |
  | validation | 0 | none |
  | security | 0 | audit channel |
  """

  alias Thunderline.Thunderflow.ErrorClass

  @type context :: map()
  @type error_term :: term()

  @doc """
  Classify an error term into a structured ErrorClass.

  ## Context Keys (optional)

  - `:module` - Originating module for heuristics
  - `:operation` - Action name / semantic op
  - `:attempt` - Current retry attempt (0-based)
  - `:event` - Event being processed, if any
  - `:external_service` - Name of downstream dependency
  - `:elapsed_ms` - Duration of operation when failure occurred

  ## Examples

      iex> ErrorClassifier.classify({:error, changeset})
      %ErrorClass{origin: :user, class: :validation, ...}

      iex> ErrorClassifier.classify(:timeout, %{external_service: :smtp})
      %ErrorClass{origin: :external, class: :timeout, ...}
  """
  @spec classify(error_term(), context()) :: %ErrorClass{}
  def classify(term, ctx \\ %{})

  # === Ecto Validation Errors ===
  def classify({:error, %Ecto.Changeset{valid?: false} = cs}, ctx) do
    %ErrorClass{
      origin: :user,
      class: :validation,
      severity: :warn,
      visibility: :user_safe,
      raw: cs,
      context: ctx
    }
  end

  def classify(%Ecto.Changeset{valid?: false} = cs, ctx) do
    %ErrorClass{
      origin: :user,
      class: :validation,
      severity: :warn,
      visibility: :user_safe,
      raw: cs,
      context: ctx
    }
  end

  # === Timeout Errors ===
  def classify(:timeout, ctx) do
    %ErrorClass{
      origin: determine_origin(ctx),
      class: :timeout,
      severity: :error,
      visibility: :internal_only,
      context: ctx
    }
  end

  def classify({:error, :timeout}, ctx), do: classify(:timeout, ctx)

  def classify(%{__struct__: struct, reason: :timeout} = err, ctx)
      when struct in [Mint.TransportError, Finch.Error] do
    %ErrorClass{
      origin: :external,
      class: :timeout,
      severity: :error,
      visibility: :internal_only,
      raw: err,
      context: ctx
    }
  end

  # === Connection/Transport Errors (Transient) ===
  def classify(%{__struct__: struct, reason: reason} = err, ctx)
      when struct in [Mint.TransportError, Finch.Error] and
             reason in [:closed, :econnrefused, :econnreset, :ehostunreach] do
    %ErrorClass{
      origin: :external,
      class: :transient,
      severity: :error,
      visibility: :internal_only,
      raw: err,
      context: ctx
    }
  end

  # === Database Errors ===
  def classify(%DBConnection.ConnectionError{} = err, ctx) do
    %ErrorClass{
      origin: :infrastructure,
      class: :dependency,
      severity: :error,
      visibility: :internal_only,
      raw: err,
      context: ctx
    }
  end

  def classify(%Postgrex.Error{postgres: %{code: code}} = err, ctx)
      when code in [:serialization_failure, :deadlock_detected] do
    %ErrorClass{
      origin: :infrastructure,
      class: :transient,
      severity: :warn,
      visibility: :internal_only,
      raw: err,
      context: ctx
    }
  end

  def classify(%Postgrex.Error{} = err, ctx) do
    %ErrorClass{
      origin: :infrastructure,
      class: :permanent,
      severity: :error,
      visibility: :internal_only,
      raw: err,
      context: ctx
    }
  end

  # === Security/Auth Errors ===
  def classify({:error, :unauthorized}, ctx) do
    %ErrorClass{
      origin: :user,
      class: :security,
      severity: :warn,
      visibility: :user_safe,
      context: ctx
    }
  end

  def classify({:error, :forbidden}, ctx) do
    %ErrorClass{
      origin: :user,
      class: :security,
      severity: :warn,
      visibility: :user_safe,
      context: ctx
    }
  end

  def classify({:error, :unauthenticated}, ctx) do
    %ErrorClass{
      origin: :user,
      class: :security,
      severity: :warn,
      visibility: :user_safe,
      context: ctx
    }
  end

  # === Dependency Unavailable ===
  def classify({:bypass, :dependency_unavailable}, ctx) do
    %ErrorClass{
      origin: :infrastructure,
      class: :dependency,
      severity: :error,
      visibility: :internal_only,
      context: ctx
    }
  end

  def classify({:error, :dependency_unavailable}, ctx) do
    %ErrorClass{
      origin: :infrastructure,
      class: :dependency,
      severity: :error,
      visibility: :internal_only,
      context: ctx
    }
  end

  # === HTTP Status Code Errors ===
  def classify({:error, {:http_status, status}}, ctx) when status in 400..499 do
    %ErrorClass{
      origin: :user,
      class: :permanent,
      severity: :warn,
      visibility: :user_safe,
      raw: {:http_status, status},
      context: ctx
    }
  end

  def classify({:error, {:http_status, status}}, ctx) when status in 500..599 do
    %ErrorClass{
      origin: :external,
      class: :transient,
      severity: :error,
      visibility: :internal_only,
      raw: {:http_status, status},
      context: ctx
    }
  end

  # === RuntimeError with timeout in message ===
  def classify(%RuntimeError{message: msg} = err, ctx) when is_binary(msg) do
    cond do
      String.contains?(msg, "timeout") ->
        %ErrorClass{
          origin: :system,
          class: :timeout,
          severity: :error,
          visibility: :internal_only,
          raw: err,
          context: ctx
        }

      String.contains?(msg, ["connection", "connect"]) ->
        %ErrorClass{
          origin: :external,
          class: :transient,
          severity: :error,
          visibility: :internal_only,
          raw: err,
          context: ctx
        }

      true ->
        classify_unknown(err, ctx)
    end
  end

  # === Wrapped error tuples ===
  def classify({:error, reason}, ctx) when is_atom(reason) do
    %ErrorClass{
      origin: :system,
      class: :permanent,
      severity: :error,
      visibility: :internal_only,
      raw: reason,
      context: ctx
    }
  end

  # === Default fallback ===
  def classify(other, ctx), do: classify_unknown(other, ctx)

  # === Helper Functions ===

  defp classify_unknown(term, ctx) do
    %ErrorClass{
      origin: :unknown,
      class: :transient,
      severity: :error,
      visibility: :internal_only,
      raw: term,
      context: ctx
    }
  end

  defp determine_origin(ctx) do
    cond do
      Map.has_key?(ctx, :external_service) -> :external
      Map.has_key?(ctx, :module) -> :system
      true -> :system
    end
  end

  @doc """
  Return the retry policy for an ErrorClass.

  Returns `{max_attempts, base_backoff_ms, backoff_multiplier}` or `:no_retry`.
  """
  @spec retry_policy(%ErrorClass{}) :: {:retry, pos_integer(), pos_integer(), float()} | :no_retry
  def retry_policy(%ErrorClass{class: class}) do
    case class do
      :transient -> {:retry, 5, 500, 2.0}
      :timeout -> {:retry, 3, 1000, 2.0}
      :dependency -> {:retry, 7, 1000, 1.5}
      :validation -> :no_retry
      :permanent -> :no_retry
      :security -> :no_retry
      _ -> :no_retry
    end
  end

  @doc """
  Check if an ErrorClass should be sent to the DLQ after max retries.
  Security errors go to audit channel instead.
  """
  @spec should_dlq?(%ErrorClass{}) :: boolean()
  def should_dlq?(%ErrorClass{class: :security}), do: false
  def should_dlq?(%ErrorClass{class: class}) when class in [:transient, :timeout, :dependency], do: true
  def should_dlq?(%ErrorClass{}), do: false
end
