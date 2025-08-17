defmodule Thunderline.ML.Cerebros.Utils.ParamCount do
  @moduledoc """
  Parameter counting utilities for Axon models.

  Provides a stable replacement for any deprecated internal counting logic.
  Returns a map with total parameter count and layer-wise breakdown to support
  budget checks and reporting in search summaries.
  """

  @doc """
  Count the parameters in an Axon model.

  Accepts an `%Axon{}` or `{init_fn, predict_fn}` tuple produced by `Axon.build/2`.
  Optionally accepts an initialized parameter map (if already built) to avoid re-init.
  Returns `%{total: integer, layers: %{layer_id => %{shape: tuple, size: integer}}}`.
  """
  def count(model, params \\ nil, rng \\ :rand.uniform(1_000_000))

  def count(%Axon{} = axon, nil, rng) do
    {init_fn, _predict_fn} = Axon.build(axon, compiler: EXLA) # Future: configurable backend
    params = init_fn.(Axon.MixedPrecision.create_key(rng), [])
    derive(params)
  end

  def count(%Axon{} = axon, %{} = params, _rng) do
    # Assume provided params already match the model
    derive(params)
  end

  def count({init_fn, _predict_fn}, nil, rng) when is_function(init_fn, 2) do
    params = init_fn.(Axon.MixedPrecision.create_key(rng), [])
    derive(params)
  end

  def count({_init_fn, _predict_fn}, %{} = params, _rng), do: derive(params)

  defp derive(params) when is_map(params) do
    {layers, total} =
      params
      |> flatten_params()
      |> Enum.map(fn {path, tensor} ->
        size = Nx.size(tensor)
        {path, %{shape: tuple_shape(tensor), size: size}}
      end)
      |> Enum.reduce({%{}, 0}, fn {k, info}, {acc, t} ->
        {Map.put(acc, k, info), t + info.size}
      end)

    %{total: total, layers: layers}
  end

  defp flatten_params(map, prefix \\ []) when is_map(map) do
    Enum.flat_map(map, fn {k, v} ->
      new_prefix = prefix ++ [k]
      if is_map(v) do
        flatten_params(v, new_prefix)
      else
        [{Enum.join(Enum.map(new_prefix, &to_string/1), "."), v}]
      end
    end)
  end

  defp tuple_shape(%Nx.Tensor{shape: shape}), do: shape
  defp tuple_shape(_), do: {}
end
