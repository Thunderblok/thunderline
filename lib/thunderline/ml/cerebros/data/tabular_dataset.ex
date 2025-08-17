defmodule Thunderline.ML.Cerebros.Data.TabularDataset do
  @moduledoc """
  Simple in-memory tabular dataset implementation used for early integration.
  Accepts raw rows (list of maps) and a feature specification; performs
  minimal numeric normalization and target extraction.
  """
  @behaviour Thunderline.ML.Cerebros.Data.Dataset

  alias Thunderline.ML.Cerebros.Data.Dataset

  defstruct [:rows, :features, :target, :task, :train_ratio, :cached]

  @type t :: %__MODULE__{
          rows: [map()],
          features: [atom()],
          target: atom(),
          task: Dataset.task_type(),
          train_ratio: float(),
          cached: map()
        }

  @impl true
  def info(%__MODULE__{features: feats, target: tgt, task: task}) do
    %{task: task, input_shape: {length(feats)}, features: feats, target: tgt, classes: nil}
  end

  @impl true
  def stream(split, opts) do
    ds = Keyword.fetch!(opts, :dataset)
    {train, val} = split_rows(ds)
    rows = case split do
      :train -> train
      :val -> val
    end

    Stream.map(rows, &preprocess_row(ds, &1))
  end

  @impl true
  def preprocess(sample), do: sample

  @impl true
  def to_batch(enum, batch_size) do
    batch = enum |> Enum.take(batch_size)
    inputs =
      batch
      |> Enum.map(& &1.inputs)
      |> Nx.stack()

    targets =
      batch
      |> Enum.map(& &1.target)
      |> Nx.stack()

    %{inputs: inputs, targets: targets}
  end

  # Public constructor
  def new(rows, features, target, opts \\ []) when is_list(rows) do
    %__MODULE__{
      rows: rows,
      features: features,
      target: target,
      task: Keyword.get(opts, :task, :regression),
      train_ratio: Keyword.get(opts, :train_ratio, 0.8),
      cached: %{}
    }
  end

  # Internal helpers
  defp split_rows(%__MODULE__{rows: rows, train_ratio: ratio}) do
    total = length(rows)
    train_count = trunc(total * ratio)
    {Enum.take(rows, train_count), Enum.drop(rows, train_count)}
  end

  defp preprocess_row(%__MODULE__{features: feats, target: tgt}, row) do
    inputs =
      feats
      |> Enum.map(fn f -> normalize_value(Map.get(row, f)) end)
      |> Nx.tensor()

    target_val = normalize_value(Map.get(row, tgt))
    %{inputs: inputs, target: Nx.tensor(target_val)}
  end

  defp normalize_value(v) when is_number(v), do: v
  defp normalize_value(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp normalize_value(_), do: 0.0
end
