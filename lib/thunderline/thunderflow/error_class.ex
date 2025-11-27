defmodule Thunderline.Thunderflow.ErrorClass do
  @moduledoc """
  Structured error classification wrapper (HC-09).

  ## Fields

  - `:origin` - Source of error: `:user`, `:system`, `:external`, `:infrastructure`, `:unknown`
  - `:class` - Error category: `:validation`, `:transient`, `:permanent`, `:timeout`, `:dependency`, `:security`
  - `:severity` - Alert level: `:info`, `:warn`, `:error`, `:critical`
  - `:visibility` - Exposure: `:user_safe`, `:internal_only`
  - `:raw` - Original error term for debugging
  - `:context` - Additional context map (module, operation, attempt, etc.)
  """

  @type origin :: :user | :system | :external | :infrastructure | :unknown
  @type error_class :: :validation | :transient | :permanent | :timeout | :dependency | :security
  @type severity :: :info | :warn | :error | :critical
  @type visibility :: :user_safe | :internal_only

  @type t :: %__MODULE__{
          origin: origin(),
          class: error_class(),
          severity: severity() | nil,
          visibility: visibility() | nil,
          raw: term(),
          context: map()
        }

  @enforce_keys [:origin, :class]
  defstruct [:origin, :class, :severity, :visibility, :raw, context: %{}]

  @doc """
  Returns true if this error class indicates the error is safe to show to users.
  """
  @spec user_safe?(t()) :: boolean()
  def user_safe?(%__MODULE__{visibility: :user_safe}), do: true
  def user_safe?(%__MODULE__{}), do: false

  @doc """
  Returns true if this error class indicates a retryable error.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{class: class}) when class in [:transient, :timeout, :dependency], do: true
  def retryable?(%__MODULE__{}), do: false

  @doc """
  Convert to a map suitable for telemetry metadata.
  """
  @spec to_telemetry_meta(t()) :: map()
  def to_telemetry_meta(%__MODULE__{} = e) do
    %{
      origin: e.origin,
      class: e.class,
      severity: e.severity,
      visibility: e.visibility
    }
  end
end
