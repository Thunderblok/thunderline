defmodule Thunderline.Thunderbolt.Cerebros.Spec do
  @moduledoc """
  Unified search spec & result contracts (versioned) for Cerebros integration.

  These structs are transport‐agnostic; CLI / external service just serialize them
  (JSON keys mirror struct field names). Version the artifact/result schema here
  so Thunderline and external Cerebros remain in lockstep.
  """

  @schema_version 1
  def schema_version, do: @schema_version

  @enforce_keys ~w(task input_shapes output_shapes trials epochs batch_size learning_rate time_budget_ms artifact_store telemetry_run_id)a
  defstruct [
    :task,
    :input_shapes,
    :output_shapes,
    :trials,
    :epochs,
    :batch_size,
    :learning_rate,
    :seed,
    :time_budget_ms,
    :artifact_store,
    :telemetry_run_id,
    :extra
  ]

  @type t :: %__MODULE__{
          task: :regression | :classification | :seq2seq | :custom,
          input_shapes: [tuple()],
          output_shapes: [tuple()],
          trials: pos_integer(),
          epochs: pos_integer(),
          batch_size: pos_integer(),
          learning_rate: float(),
          seed: non_neg_integer() | nil,
          time_budget_ms: pos_integer() | :infinity,
          artifact_store: %{kind: :fs | :s3, path: String.t()},
          telemetry_run_id: String.t(),
          extra: map() | nil
        }

  @default_time_budget 15 * 60_000

  @doc "Validate/build spec from map (raises on invalid)."
  @spec new!(map()) :: t()
  def new!(map) when is_map(map) do
    telemetry_run_id = Map.get(map, "telemetry_run_id") || Map.get(map, :telemetry_run_id) || UUID.uuid4()
    task = get_atom!(map, :task, [:regression, :classification, :seq2seq, :custom])
    trials = get_int!(map, :trials, 1)
    epochs = get_int!(map, :epochs, 1)
    batch_size = get_int!(map, :batch_size, 1)
    lr = get_float!(map, :learning_rate, 1.0e-3)
    time_budget_ms = Map.get(map, :time_budget_ms) || Map.get(map, "time_budget_ms") || @default_time_budget
    artifact_store = Map.get(map, :artifact_store) || Map.get(map, "artifact_store") || %{kind: :fs, path: "priv/cerebros_runs"}
    input_shapes = Map.get(map, :input_shapes) || Map.get(map, "input_shapes") || []
    output_shapes = Map.get(map, :output_shapes) || Map.get(map, "output_shapes") || []
    seed = Map.get(map, :seed)
    extra = Map.get(map, :extra) || %{}

    %__MODULE__{
      task: task,
      input_shapes: input_shapes,
      output_shapes: output_shapes,
      trials: trials,
      epochs: epochs,
      batch_size: batch_size,
      learning_rate: lr,
      seed: seed,
      time_budget_ms: time_budget_ms,
      artifact_store: artifact_store,
      telemetry_run_id: telemetry_run_id,
      extra: extra
    }
  end

  defp get_atom!(map, key, allowed) do
    v = Map.get(map, key) || Map.get(map, to_string(key)) || raise ArgumentError, "missing #{key}"
    v = if is_binary(v), do: String.to_atom(v), else: v
    if v in allowed do
      v
    else
      raise ArgumentError, "invalid #{key}=#{inspect(v)}"
    end
  end
  defp get_int!(map, key, default) do
    v = Map.get(map, key) || Map.get(map, to_string(key)) || default
    unless is_integer(v) and v > 0 do
      raise ArgumentError, "invalid #{key}"
    end
    v
  end
  defp get_float!(map, key, default) do
    v = Map.get(map, key) || Map.get(map, to_string(key)) || default
    cond do
      is_float(v) -> v
      is_integer(v) -> v / 1
      true -> raise ArgumentError, "invalid #{key}"
    end
  end
end

defmodule Thunderline.Thunderbolt.Cerebros.Result do
  @moduledoc "Versioned result schema for Cerebros searches."
  @schema_version 1
  def schema_version, do: @schema_version
  @enforce_keys ~w(run_id best_metric trials artifact_path metrics_summary)a
  defstruct [
    :run_id,
    :best_metric,
    :best_trial,
    :trials,
    :artifact_path,
    :metrics_summary,
    :cerebros_version,
    :schema_version
  ]
end
