defmodule Thunderline.ML.Cerebros.Data.Dataset do
  @moduledoc """
  Behaviour defining the dataset interface for Cerebros NAS pipeline.

  Responsibilities:
  - Provide dataset metadata (task type, input shape, target info)
  - Stream training and validation samples lazily
  - Apply preprocessing / feature engineering to raw samples
  - Optionally expose a batch builder yielding Nx tensors
  """

  @type sample :: map()
  @type stream_opt :: term()
  @type task_type :: :regression | :binary | :multiclass | :multilabel

  @callback info() :: %{task: task_type(), input_shape: tuple(), features: list(atom()), target: atom(), classes: list(any()) | nil}
  @callback stream(split :: :train | :val, opts :: [stream_opt()]) :: Enumerable.t()
  @callback preprocess(sample()) :: sample()
  @callback to_batch(enum :: Enumerable.t(), batch_size :: pos_integer()) :: %{inputs: Nx.t(), targets: Nx.t()}
end
