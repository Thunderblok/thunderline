defmodule Thunderline.Stone do
  @moduledoc """
  Facade for Stone policy checks.
  """
  alias Thunderline.Stone.Proof

  @spec allow?(atom(), map()) :: :ok | {:error, :denied}
  def allow?(action, ev) do
    if Proof.allow?(action, ev) do
      Proof.issue({action, ev}, :allow, "policy_ok")
      :ok
    else
      Proof.issue({action, ev}, :deny, "policy_denied")
      {:error, :denied}
    end
  end
end
