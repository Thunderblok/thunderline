defmodule Thunderline.Thunderflow.RetryPolicy do
  @moduledoc """
  Central retry policy definitions for Thunderflow Broadway pipelines.

  The budgets implemented here are enforced according to the reliability guidance in
  [`docs/EVENT_RETRY_STRATEGIES.md`](../../docs/EVENT_RETRY_STRATEGIES.md), ensuring that runtime
  behaviour matches the documented retry guarantees.
  """

  alias Broadway.Message
  alias Thunderline.Thunderflow.Support.Backoff

  @type strategy :: :none | :exponential

  @enforce_keys [:category, :max_attempts, :strategy]
  defstruct [:category, :max_attempts, :strategy]

  @type t :: %__MODULE__{
          category: atom(),
          max_attempts: pos_integer(),
          strategy: strategy()
        }

  @doc """
  Returns the retry policy struct for the given event, message or event name.
  """
  @spec for_event(Message.t() | map() | String.t() | atom() | nil) :: t()
  def for_event(%Message{data: data}), do: for_event(data)

  def for_event(%{"action" => action}) when is_binary(action), do: for_name(action)
  def for_event(%{"name" => name}) when is_binary(name), do: for_name(name)
  def for_event(%{action: action}) when is_binary(action), do: for_name(action)
  def for_event(%{name: name}) when is_binary(name), do: for_name(name)
  def for_event(name) when is_binary(name), do: for_name(name)
  def for_event(name) when is_atom(name), do: name |> Atom.to_string() |> for_name()
  def for_event(_), do: build_policy(:default)

  @doc """
  Returns the retry policy struct for a `Broadway.Message`.
  """
  @spec for_message(Message.t()) :: t()
  def for_message(%Message{} = message), do: for_event(message)

  @doc """
  Returns the `{max_attempts, strategy}` tuple for compatibility with legacy callers.
  """
  @spec budget(Message.t() | map() | String.t() | atom() | nil) :: {pos_integer(), strategy()}
  def budget(event) do
    policy = for_event(event)
    {policy.max_attempts, policy.strategy}
  end

  @doc """
  Calculates the delay in milliseconds for the given attempt according to the policy strategy.
  """
  @spec next_delay(t(), pos_integer()) :: non_neg_integer()
  def next_delay(%__MODULE__{strategy: :none}, _attempt), do: 0

  def next_delay(%__MODULE__{strategy: :exponential}, attempt) when attempt >= 1,
    do: Backoff.exp(attempt)

  @doc """
  Returns `true` when the attempt would exceed the retry budget.
  """
  @spec exhausted?(t(), pos_integer()) :: boolean()
  def exhausted?(%__MODULE__{max_attempts: max}, attempt) when attempt >= 1, do: attempt >= max

  @doc """
  Returns `true` when the attempt is still within the retry budget.
  """
  @spec retry_allowed?(t(), pos_integer()) :: boolean()
  def retry_allowed?(policy, attempt), do: not exhausted?(policy, attempt)

  @doc """
  Convenience accessor for the strategy of a policy.
  """
  @spec strategy(t() | Message.t() | map() | String.t() | atom() | nil) :: strategy()
  def strategy(%__MODULE__{strategy: strategy}), do: strategy
  def strategy(event), do: event |> for_event() |> Map.fetch!(:strategy)

  defp for_name(name) when is_binary(name) do
    cond do
      String.starts_with?(name, "ml.run.") -> build_policy(:ml_run)
      String.starts_with?(name, "ml.trial.") -> build_policy(:ml_trial)
      String.starts_with?(name, "ui.command.") -> build_policy(:ui_command)
      String.starts_with?(name, "ml.run") -> build_policy(:ml_run)
      String.starts_with?(name, "ml.trial") -> build_policy(:ml_trial)
      String.starts_with?(name, "ui.command") -> build_policy(:ui_command)
      true -> build_policy(:default)
    end
  end

  defp for_name(_), do: build_policy(:default)

  defp build_policy(:ml_run),
    do: %__MODULE__{category: :ml_run, max_attempts: 5, strategy: :exponential}

  defp build_policy(:ml_trial),
    do: %__MODULE__{category: :ml_trial, max_attempts: 3, strategy: :exponential}

  defp build_policy(:ui_command),
    do: %__MODULE__{category: :ui_command, max_attempts: 2, strategy: :none}

  defp build_policy(:default),
    do: %__MODULE__{category: :default, max_attempts: 3, strategy: :exponential}
end
