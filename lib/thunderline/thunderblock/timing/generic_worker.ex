defmodule Thunderline.Thunderblock.Timing.GenericWorker do
  @moduledoc """
  Generic Oban worker for scheduled tasks in Thunderline.

  This worker executes arbitrary MFA (module, function, args) tuples
  that are stored in the job args. Used by the Timing.Scheduler for
  dynamic task scheduling.
  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3

  require Logger

  @doc """
  Create a new job changeset for an MFA execution.

  ## Options
    - `:scheduled_at` - DateTime when to run (default: now)
    - `:priority` - Job priority 0-3 (default: 1)
  """
  def new(args, opts \\ []) do
    args
    |> Map.new()
    |> Oban.Job.new(Keyword.merge([worker: __MODULE__], opts))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{"module" => module_str, "function" => function_str, "args" => call_args} ->
        module = String.to_existing_atom(module_str)
        function = String.to_existing_atom(function_str)

        Logger.debug("[GenericWorker] Executing #{module}.#{function}/#{length(call_args)}")

        try do
          result = apply(module, function, call_args)
          {:ok, result}
        rescue
          error ->
            Logger.error("[GenericWorker] Execution failed: #{inspect(error)}")
            {:error, error}
        end

      %{"callback" => callback_type} ->
        # Handle special callback types
        handle_callback(callback_type, args)

      _ ->
        Logger.warning("[GenericWorker] Unknown job args format: #{inspect(args)}")
        {:error, :invalid_args}
    end
  end

  defp handle_callback("tick", args) do
    tick_number = Map.get(args, "tick", 0)
    Logger.debug("[GenericWorker] Processing tick #{tick_number}")
    {:ok, %{tick: tick_number, processed_at: DateTime.utc_now()}}
  end

  defp handle_callback("maintenance", _args) do
    Logger.debug("[GenericWorker] Running maintenance callback")
    {:ok, :maintenance_complete}
  end

  defp handle_callback(type, _args) do
    Logger.warning("[GenericWorker] Unknown callback type: #{type}")
    {:error, {:unknown_callback, type}}
  end
end
