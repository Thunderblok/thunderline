defmodule Thunderline.Thunderblock.Jobs.RetentionSweepWorker do
  @moduledoc """
  Orchestrates retention sweeps via `Thunderline.Thunderblock.Retention.Sweeper`.

  The worker is designed to fan out across configured targets (resources) using
  loader/deleter functions defined in application configuration:

      config :thunderline, Thunderline.Thunderblock.Retention.Sweeper,
        targets: [
          %{
            resource: :event_log,
            loader: {MyModule, :load_candidates, []},
            deleter: {MyModule, :delete_candidates, []},
            metadata: %{surface: :event_log}
          }
        ]

  Each target entry must provide at least a `:resource` atom and a loader. The
  loader must be either a zero-arity function or an `{M, F, A}` tuple. The
  optional deleter receives the list of expired entries; when omitted the sweep
  operates in dry-run mode for that target.

  The worker supports two invocation modes:
    * No args / empty map — sweep all configured targets
    * %{"resource" => resource} — sweep only the requested resource
  """

  use Oban.Worker,
    queue: :retention,
    max_attempts: 3,
    tags: ["retention"]

  require Logger

  alias Thunderline.Thunderblock.Retention.Sweeper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource" => resource}}) do
    with {:ok, resource_atom} <- normalize_resource(resource),
         {:ok, target} <- target_for(resource_atom) do
      execute_target(target)
    else
      {:error, :unknown_resource} ->
        Logger.warning("[RetentionSweepWorker] unknown resource #{inspect(resource)}")
        {:discard, :unknown_resource}

      {:error, :no_target} ->
        Logger.warning("[RetentionSweepWorker] no configured target for #{inspect(resource)}")
        {:discard, :no_target}
    end
  end

  def perform(%Oban.Job{}) do
    targets = configured_targets()

    if Enum.empty?(targets) do
      Logger.debug("[RetentionSweepWorker] no configured targets; skipping sweep")
      :ok
    else
      targets
      |> Enum.reduce_while(:ok, fn target, _acc ->
        case execute_target(target) do
          {:ok, _result} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Convenience helper to enqueue a retention sweep job.
  """
  @spec enqueue(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(args \\ %{}) when is_map(args) do
    args
    |> Map.new()
    |> new()
    |> Oban.insert()
  end

  defp execute_target(%{resource: resource} = target) do
    metadata =
      target
      |> Map.get(:metadata, %{})
      |> Map.put_new(:target, resource)

    options =
      [
        load: build_loader(target),
        metadata: metadata
      ]
      |> maybe_put_deleter(target)

    case Sweeper.sweep(resource, options) do
      {:ok, result} ->
        log_success(resource, result)
        {:ok, result}

      {:error, reason} ->
        Logger.error(
          "[RetentionSweepWorker] sweep failed resource=#{inspect(resource)} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_loader(%{loader: {mod, fun, args}})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    fn -> apply(mod, fun, args) end
  end

  defp build_loader(%{loader: fun}) when is_function(fun, 0), do: fun

  defp build_loader(_target) do
    fn -> [] end
  end

  defp maybe_put_deleter(options, %{deleter: {mod, fun, args}})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    Keyword.put(options, :delete, fn entries -> apply(mod, fun, [entries | args]) end)
  end

  defp maybe_put_deleter(options, %{deleter: fun}) when is_function(fun, 1) do
    Keyword.put(options, :delete, fun)
  end

  defp maybe_put_deleter(options, _target), do: options

  defp normalize_resource(resource) when is_atom(resource), do: {:ok, resource}

  defp normalize_resource(resource) when is_binary(resource) do
    try do
      {:ok, String.to_existing_atom(resource)}
    rescue
      ArgumentError -> {:error, :unknown_resource}
    end
  end

  defp normalize_resource(_), do: {:error, :unknown_resource}

  defp configured_targets do
    sweeper_config()
    |> Keyword.get(:targets, [])
    |> Enum.map(&normalize_target/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_target(%{resource: resource} = target) when is_atom(resource) do
    target
  end

  defp normalize_target(%{resource: resource} = target) when is_binary(resource) do
    case normalize_resource(resource) do
      {:ok, resource_atom} -> Map.put(target, :resource, resource_atom)
      {:error, _} -> nil
    end
  end

  defp normalize_target(_), do: nil

  defp target_for(resource) do
    configured_targets()
    |> Enum.find(fn target -> target.resource == resource end)
    |> case do
      nil -> {:error, :no_target}
      target -> {:ok, target}
    end
  end

  defp sweeper_config do
    Application.get_env(:thunderline, Sweeper, [])
  end

  defp log_success(resource, result) do
    Logger.info(
      "[RetentionSweepWorker] resource=#{inspect(resource)} expired=#{result.expired} deleted=#{result.deleted} kept=#{result.kept} dry_run=#{result.dry_run?}"
    )
  end
end
