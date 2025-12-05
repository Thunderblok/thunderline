defmodule Thunderline.Thunderbolt.CerebrosBridge.RunOptions do
  @moduledoc """
  Helper utilities for preparing Cerebros NAS run specifications prior to
  enqueueing Oban jobs. Centralising this logic keeps LiveViews and other
  callers consistent when shaping metadata.
  """

  alias Thunderline.UUID

  @type run_id :: String.t()
  @type run_spec :: map()
  @type enqueue_opts :: keyword()

  @default_source "thunderline_ui"
  @default_operator "manual"

  @doc """
  Ensures a specification contains a `run_id` and returns the tuple
  `{run_id, normalized_spec, enqueue_options}` expected by
  `CerebrosBridge.enqueue_run/2`.

  Options:
    * `:run_id` – supply a pre-generated run id (defaults to existing spec run_id or UUID)
    * `:source` – string recorded in metadata (defaults to `thunderline_ui`)
    * `:operator` – string recorded in metadata (defaults to `manual`)
    * `:meta` – additional metadata map merged into the generated metadata
  """
  @spec prepare(run_spec(), keyword()) ::
          {run_id(), run_spec(), enqueue_opts()} | {:error, :invalid_spec}
  def prepare(spec, opts \\ [])

  def prepare(spec, opts) when is_map(spec) do
    run_id =
      Keyword.get_lazy(opts, :run_id, fn ->
        Map.get(spec, "run_id") || Map.get(spec, :run_id) || UUID.v7()
      end)

    spec_with_run_id = Map.put(spec, "run_id", run_id)
    metadata = build_metadata(spec_with_run_id, opts)
    enqueue_opts = build_enqueue_opts(run_id, spec_with_run_id, metadata)

    {run_id, spec_with_run_id, enqueue_opts}
  end

  def prepare(_spec, _opts), do: {:error, :invalid_spec}

  defp build_enqueue_opts(run_id, spec, metadata) do
    [
      {:run_id, run_id},
      {:pulse_id, Map.get(spec, "pulse_id") || get_in(spec, ["pulse", "id"])},
      {:budget, Map.get(spec, "budget", %{})},
      {:parameters, Map.get(spec, "parameters", %{})},
      {:tau, Map.get(spec, "tau") || get_in(spec, ["pulse", "tau"])},
      {:correlation_id, Map.get(spec, "correlation_id") || run_id},
      {:extra, Map.get(spec, "extra")},
      {:meta, metadata}
    ]
    |> Enum.reject(fn {key, value} -> key != :run_id and is_nil(value) end)
  end

  defp build_metadata(spec, opts) do
    base = spec |> Map.get("metadata", %{}) |> normalize_map()
    override = opts |> Keyword.get(:meta, %{}) |> normalize_map()

    source =
      override["source"] || base["source"] ||
        normalize_string(Keyword.get(opts, :source, @default_source))

    operator =
      override["operator"] || base["operator"] ||
        normalize_string(Keyword.get(opts, :operator, @default_operator))

    base
    |> Map.merge(override)
    |> Map.put("source", source)
    |> Map.put("operator", operator)
    |> Map.put("submitted_at", DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp normalize_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string_key(k), v)
    end)
  end

  defp normalize_map(list) when is_list(list) do
    Enum.reduce(list, %{}, fn
      {k, v}, acc -> Map.put(acc, to_string_key(k), v)
      _other, acc -> acc
    end)
  end

  defp normalize_map(_), do: %{}

  defp to_string_key(key) when is_binary(key), do: key
  defp to_string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_string_key(key), do: to_string(key)

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value), do: to_string(value)
end
