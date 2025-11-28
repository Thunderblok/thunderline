defmodule Thunderline.Thundercrown.Orchestrator do
  @moduledoc """
  👑 Thundercrown Orchestrator - Domain-agnostic orchestration hub

  Consolidated from: Thunderline.Thunderchief.Orchestrator

  Routes events/jobs to domain-specific workers via Oban queues. This module
  provides the centralized coordination layer for cross-domain operations.

  ## Configuration

  Domain workers can be configured in `config/config.exs`:

      config :thunderline, :thundercrown,
        domain_workers: %{
          "thunderbolt" => Thunderline.Thunderflow.Jobs.DomainProcessor,
          "thundercore" => Thunderline.Thunderflow.Jobs.DomainProcessor,
          "thunderblock" => Thunderline.Thunderflow.Jobs.DomainProcessor
        }

  ## Usage

      # Dispatch an event to a domain worker
      Thundercrown.Orchestrator.dispatch_event(event, "thunderbolt")

      # Enqueue a domain job
      Thundercrown.Orchestrator.enqueue_domain_job(%{
        "domain" => "thunderbolt",
        "event" => %{...}
      })

  ## Reactor Integration

  When `TL_ENABLE_REACTOR=true`, the orchestrator can coordinate with Reactor
  sagas for complex multi-step workflows requiring compensation logic.
  """

  require Logger

  alias Thunderline.Thunderflow.Jobs.DomainProcessor

  @default_domain_workers %{
    "thunderbolt" => DomainProcessor,
    "thundercore" => DomainProcessor,
    "thunderblock" => DomainProcessor,
    "thundercrown" => DomainProcessor,
    "thunderflow" => DomainProcessor,
    "thundergate" => DomainProcessor,
    "thundergrid" => DomainProcessor,
    "thunderlink" => DomainProcessor,
    "thundervine" => DomainProcessor,
    "thunderprism" => DomainProcessor,
    "thunderwall" => DomainProcessor,
    "thunderpac" => DomainProcessor
  }

  @doc """
  Dispatch an event to the appropriate domain worker.

  Returns `{:ok, job}` on success or `{:error, reason}` on failure.
  """
  @spec dispatch_event(map(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def dispatch_event(event, domain) when is_binary(domain) do
    worker = get_domain_worker(domain)

    job_args = %{
      "domain" => domain,
      "event" => event,
      "dispatched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    :telemetry.execute(
      [:thunderline, :thundercrown, :dispatch],
      %{count: 1},
      %{domain: domain, worker: worker}
    )

    worker.new(job_args)
    |> Oban.insert()
  end

  def dispatch_event(event, domain) when is_atom(domain) do
    dispatch_event(event, Atom.to_string(domain))
  end

  @doc """
  Enqueue a domain job with the appropriate worker.

  Expects a map with at least a "domain" key. Returns an Oban changeset
  ready for insertion, or `nil` if the job cannot be built.

  ## Examples

      iex> job = %{"domain" => "thunderbolt", "event" => %{type: :test}}
      iex> Orchestrator.enqueue_domain_job(job)
      %Ecto.Changeset{...}

  """
  @spec enqueue_domain_job(map()) :: Ecto.Changeset.t() | Oban.Job.t() | nil
  def enqueue_domain_job(%{"domain" => domain} = job) when is_binary(domain) do
    worker = get_domain_worker(domain)

    :telemetry.execute(
      [:thunderline, :thundercrown, :enqueue],
      %{count: 1},
      %{domain: domain, worker: worker}
    )

    worker.new(job)
  end

  def enqueue_domain_job(%{domain: domain} = job) when is_atom(domain) do
    enqueue_domain_job(Map.put(job, "domain", Atom.to_string(domain)))
  end

  def enqueue_domain_job(_job), do: nil

  @doc """
  Enqueue a cross-domain operation job.

  Used for operations that span multiple domains and require coordination.
  """
  @spec enqueue_cross_domain_job(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_cross_domain_job(params) do
    job_args = %{
      "type" => "cross_domain",
      "source_domain" => Map.get(params, :source_domain) || Map.get(params, "source_domain"),
      "target_domain" => Map.get(params, :target_domain) || Map.get(params, "target_domain"),
      "operation_type" => Map.get(params, :operation_type) || Map.get(params, "operation_type"),
      "priority" => Map.get(params, :priority, :normal),
      "payload" => Map.get(params, :payload) || Map.get(params, "payload", %{}),
      "dispatched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    :telemetry.execute(
      [:thunderline, :thundercrown, :cross_domain],
      %{count: 1},
      %{
        source: job_args["source_domain"],
        target: job_args["target_domain"],
        operation: job_args["operation_type"]
      }
    )

    DomainProcessor.new(job_args, queue: :cross_domain)
    |> Oban.insert()
  end

  @doc """
  List all configured domain workers.
  """
  @spec list_domain_workers() :: map()
  def list_domain_workers do
    config_workers()
    |> Map.merge(@default_domain_workers)
  end

  @doc """
  Check if a domain has a configured worker.
  """
  @spec has_worker?(String.t()) :: boolean()
  def has_worker?(domain) when is_binary(domain) do
    Map.has_key?(list_domain_workers(), domain)
  end

  # Private helpers

  defp get_domain_worker(domain) do
    config_workers()
    |> Map.get(domain, @default_domain_workers[domain] || DomainProcessor)
  end

  defp config_workers do
    Application.get_env(:thunderline, :thundercrown, [])
    |> Keyword.get(:domain_workers, %{})
  end
end
