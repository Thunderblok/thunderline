defmodule Thunderline.Thunderchief.Orchestrator do
  @moduledoc """
  Domain-agnostic orchestration hub that decides whether an incoming event should
  run synchronously via Reactor or through the simple processor, and which
  worker should handle any follow-up Oban jobs.

  The orchestration strategy is:

    * If `TL_ENABLE_REACTOR` is truthy **and** the realtime reactor module is
      available, dispatch events through Reactor.
    * Otherwise, fall back to `Thunderline.Thunderflow.Processor` for fast-path
      handling.
    * Callers can request an async hand-off by using `enqueue_domain_job/1`,
      which resolves the correct worker module per domain (defaults are backed
      by existing Thunderflow processors but can be overridden via config).

  Configuration (optional):

      config :thunderline, :thunderchief,
        domain_workers: %{
          "thunderbolt" => Thunderline.Thunderflow.Jobs.DomainProcessor
        }

  If no config is provided we fall back to a small set of built-in mappings.
  """

  require Logger

  alias Oban.Job
  alias Thunderline.Thunderflow.Processor

  @compile {:no_warn_undefined, Reactor}
  @compile {:no_warn_undefined, Thunderline.Reactors.RealtimeReactor}

  @default_domain_workers %{
    "thunderbolt" => Thunderline.Thunderflow.Jobs.DomainProcessor,
    "thundercore" => Thunderline.Thunderflow.Jobs.DomainProcessor,
    "thunderblock" => Thunderline.Thunderflow.Jobs.DomainProcessor
  }

  @doc """
  Process a single event, routing through Reactor when enabled.
  """
  @spec dispatch_event(map(), keyword()) :: {:ok, term()} | {:error, term()}
  def dispatch_event(event, opts \\ [])

  def dispatch_event(event, opts) when is_map(event) do
    case run_sync(event, opts) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:ok, other}
    end
  end

  def dispatch_event(other, _opts) do
    {:error, {:invalid_event, other}}
  end

  @doc """
  Resolve and build an Oban job for a downstream domain worker.

  Returns an Oban changeset suitable for `Oban.insert/1`, or `nil` when no
  worker could be resolved.
  """
  @spec enqueue_domain_job(map()) :: Job.t() | nil
  def enqueue_domain_job(%{} = job) do
    domain = job["domain"] || job[:domain]
    module = domain_worker(domain)

    cond do
      is_nil(domain) ->
        Logger.warning("Orchestrator enqueue_domain_job missing domain: #{inspect(job)}")
        nil

      is_nil(module) ->
        Logger.warning("No domain worker configured for #{inspect(domain)}; dropping job")
        nil

      not Code.ensure_loaded?(module) ->
        Logger.warning("Domain worker #{inspect(module)} not loaded; dropping job")
        nil

      not function_exported?(module, :new, 1) ->
        Logger.warning("Domain worker #{inspect(module)} missing new/1; dropping job")
        nil

      true ->
        module.new(stringify_domain(job, domain))
    end
  end

  def enqueue_domain_job(_), do: nil

  # -- internal helpers ----------------------------------------------------

  defp run_sync(event, opts) do
    if use_reactor?(opts) do
      run_with_reactor(event)
    else
      Processor.process_event(event)
    end
  end

  defp use_reactor?(opts) do
    case Keyword.get(opts, :reactor) do
      true -> reactor_enabled?()
      false -> false
      nil -> reactor_enabled?()
    end
  end

  defp run_with_reactor(event) do
    with true <- Code.ensure_loaded?(Reactor),
         {:module, _} <- Code.ensure_loaded(Thunderline.Reactors.RealtimeReactor) do
      Reactor.run(Thunderline.Reactors.RealtimeReactor, %{event: event})
    else
      _ ->
        Logger.debug("Reactor unavailable; falling back to simple processor")
        Processor.process_event(event)
    end
  end

  defp reactor_enabled? do
    case System.get_env("TL_ENABLE_REACTOR") do
      "true" -> true
      "1" -> true
      _ -> false
    end
  end

  defp domain_worker(nil), do: nil

  defp domain_worker(domain) when is_atom(domain) do
    domain |> Atom.to_string() |> domain_worker()
  end

  defp domain_worker(domain) when is_binary(domain) do
    config = Application.get_env(:thunderline, :thunderchief, [])
    worker_map = Keyword.get(config, :domain_workers, %{})

    worker_map[domain] ||
      worker_map[existing_atom(domain)] ||
      Map.get(@default_domain_workers, domain)
  end

  defp domain_worker(_), do: nil

  defp stringify_domain(job, domain) when is_binary(domain) do
    Map.put(job, "domain", domain)
  end

  defp stringify_domain(job, domain) when is_atom(domain) do
    Map.put(job, "domain", Atom.to_string(domain))
  end

  defp stringify_domain(job, _), do: job

  defp existing_atom(nil), do: nil

  defp existing_atom(domain) do
    String.to_existing_atom(domain)
  rescue
    ArgumentError -> nil
  end
end
