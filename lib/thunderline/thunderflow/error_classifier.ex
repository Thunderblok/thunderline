defmodule Thunderline.Thunderflow.ErrorClassifier do
  @moduledoc "Heuristic error classifier (Phase-1 stub)."
  alias Thunderline.Thunderflow.ErrorClass

  @type context :: map
  @spec classify(term, context) :: %ErrorClass{}
  def classify(term, ctx \\ %{})

  def classify({:error, %Ecto.Changeset{} = cs}, ctx),
    do: %ErrorClass{
      origin: :ecto,
      class: :validation,
      severity: :warn,
      visibility: :internal,
      raw: cs,
      context: ctx
    }

  def classify(:timeout, ctx),
    do: %ErrorClass{
      origin: :system,
      class: :timeout,
      severity: :error,
      visibility: :internal,
      context: ctx
    }

  def classify(other, ctx),
    do: %ErrorClass{
      origin: :unknown,
      class: :exception,
      severity: :error,
      visibility: :internal,
      raw: other,
      context: ctx
    }
end
