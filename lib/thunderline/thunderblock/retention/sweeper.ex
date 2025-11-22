defmodule Thunderline.Thunderblock.Retention.Sweeper do
  @moduledoc """
  Executes retention sweeps against arbitrary resources by consulting
  `Thunderline.Thunderblock.Retention` policies. Callers provide a loader that
  yields candidate records (with their scopes and insertion timestamps) and an
  optional deleter. The sweeper evaluates each record against the effective
  policy, respects dry-run mode, enforces batch limits, and emits telemetry so
  operators can track progress.
  """

  require Logger

  alias Thunderline.Thunderblock.Retention
  alias Thunderline.Thunderblock.Resources.RetentionPolicy

  @telemetry_event [:thunderline, :retention, :sweep]
  @default_batch 5_000

  @type sweep_option ::
          {:load, (-> Enumerable.t())}
          | {:delete, ([map()] -> {:ok, non_neg_integer()} | {:error, term()})}
          | {:now, DateTime.t()}
          | {:dry_run, boolean()}
          | {:batch_size, pos_integer()}
          | {:metadata, map()}

  @spec sweep(atom(), [sweep_option()]) ::
          {:ok,
           %{
             expired: non_neg_integer(),
             deleted: non_neg_integer(),
             kept: non_neg_integer(),
             dry_run?: boolean(),
             metadata: map()
           }}
          | {:error, term()}
  def sweep(resource, opts) when is_atom(resource) and is_list(opts) do
    load_fun = Keyword.fetch!(opts, :load)
    delete_fun = Keyword.get(opts, :delete, fn _ -> {:ok, 0} end)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    dry_run? = Keyword.get(opts, :dry_run, config_dry_run())
    batch_size = Keyword.get(opts, :batch_size, config_batch_size())
    extra_metadata = Keyword.get(opts, :metadata, %{})

    telemetry_metadata =
      extra_metadata
      |> Map.new()
      |> Map.merge(%{
        resource: resource,
        dry_run?: dry_run?,
        batch_size: batch_size
      })

    start = System.monotonic_time()

    with {:ok, candidates} <- collect_candidates(load_fun),
         {:ok, classified, kept, _cache} <- classify(resource, candidates, now) do
      expired_entries = Enum.reverse(classified)
      expired_count = length(expired_entries)

      delete_result = maybe_delete(expired_entries, delete_fun, batch_size, dry_run?)

      measurements =
        %{
          expired: expired_count,
          kept: kept,
          duration_ms: duration_ms(start)
        }
        |> maybe_put_deleted(delete_result)

      maybe_emit_telemetry(measurements, telemetry_metadata)

      case delete_result do
        {:ok, deleted} ->
          {:ok,
           %{
             expired: expired_count,
             deleted: deleted,
             kept: kept,
             dry_run?: dry_run?,
             metadata: telemetry_metadata
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp collect_candidates(load_fun) do
    case load_fun.() do
      candidates when is_list(candidates) ->
        {:ok, candidates}

      %Stream{} = stream ->
        {:ok, Enum.to_list(stream)}

      other ->
        try do
          {:ok, Enum.to_list(other)}
        rescue
          _ -> {:error, :invalid_loader}
        end
    end
  end

  defp classify(resource, entries, now) do
    Enum.reduce_while(entries, {:ok, [], 0, %{}}, fn entry, {:ok, expired, kept, cache} ->
      case normalize_entry(entry) do
        {:ok, normalized} ->
          case fetch_policy(resource, normalized.scope, cache) do
            {:ok, policy, new_cache} ->
              if expired?(normalized.inserted_at, policy, now) do
                {:cont, {:ok, [normalized | expired], kept, new_cache}}
              else
                {:cont, {:ok, expired, kept + 1, new_cache}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, expired, kept, cache} -> {:ok, expired, kept, cache}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_entry(%{id: id, inserted_at: %DateTime{} = inserted_at} = entry)
       when not is_nil(id) do
    scope = Map.get(entry, :scope, :global)
    {:ok, %{entry | scope: scope, inserted_at: inserted_at}}
  end

  defp normalize_entry(_), do: {:error, :invalid_entry}

  defp fetch_policy(resource, scope, cache) do
    case cache do
      %{^scope => policy} ->
        {:ok, policy, cache}

      _ ->
        case Retention.effective(resource, scope) do
          {:ok, {%RetentionPolicy{} = policy, _context}} ->
            {:ok, policy, Map.put(cache, scope, policy)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp expired?(_inserted_at, %RetentionPolicy{ttl_seconds: nil}, _now), do: false

  defp expired?(%DateTime{} = inserted_at, %RetentionPolicy{} = policy, %DateTime{} = now) do
    ttl = policy.ttl_seconds || 0
    grace = policy.grace_seconds || 0
    threshold = ttl + grace

    if threshold <= 0 do
      false
    else
      DateTime.diff(now, inserted_at, :second) >= threshold
    end
  end

  defp maybe_delete(_entries, _delete_fun, _batch_size, true), do: {:ok, 0}

  defp maybe_delete(entries, delete_fun, batch_size, false) do
    entries
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, acc} ->
      case delete_fun.(batch) do
        {:ok, deleted} -> {:cont, {:ok, acc + deleted}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_put_deleted(measurements, {:ok, deleted}),
    do: Map.put(measurements, :deleted, deleted)

  defp maybe_put_deleted(measurements, {:error, _reason}), do: measurements

  defp maybe_emit_telemetry(measurements, metadata) do
    :telemetry.execute(@telemetry_event, measurements, metadata)
  rescue
    _ -> :ok
  end

  defp config_dry_run do
    :thunderline
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:dry_run, false)
  end

  defp config_batch_size do
    :thunderline
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:batch_size, @default_batch)
  end

  defp duration_ms(start) do
    diff = System.monotonic_time() - start
    System.convert_time_unit(diff, :native, :millisecond)
  end
end
