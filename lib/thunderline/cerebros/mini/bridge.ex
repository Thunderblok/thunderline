defmodule Thunderline.Cerebros.Mini.Bridge do
  @moduledoc """
  Unified bridge for Cerebros-mini scoring pipeline.

  Implements the complete flow:

      Thunderbit → from_bit/1 → Feature → infer/1 → Result → apply_result/3 → Mutation

  ## Architecture

  The Bridge serves as the single entry point for:
  1. Feature extraction from Thunderbits
  2. Inference via the scoring model
  3. Result application back to bits via Protocol.mutate/3
  4. Event emission for observability

  ## Integration Points

  - **BitChief**: Calls `evaluate/2` during domain processing
  - **DomainProcessor**: Can trigger batch evaluation via Oban
  - **Protocol**: Uses `mutate/3` for bit updates
  - **EventBus**: Emits `cerebros.mini.*` events

  ## Usage

      # Single bit evaluation
      {:ok, result, ctx} = Bridge.evaluate(bit, ctx)

      # Batch evaluation
      {:ok, results, ctx} = Bridge.evaluate_batch(bits, ctx)

      # Full pipeline with mutation
      {:ok, bit, ctx} = Bridge.evaluate_and_apply(bit, ctx)

  ## Telemetry

  Emits:
  - `[:thunderline, :cerebros, :mini, :evaluate]` - Per-evaluation metrics
  - `[:thunderline, :cerebros, :mini, :batch]` - Batch metrics
  """

  alias Thunderline.Cerebros.Mini.{Feature, Scorer}
  alias Thunderline.Thunderbit.{Protocol, Context}

  require Logger

  @type evaluation_result :: %{
          bit_id: String.t(),
          feature: Feature.t(),
          score: float(),
          label: atom(),
          next_action: atom() | nil,
          confidence: float()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Evaluates a single Thunderbit through the Cerebros-mini pipeline.

  Extracts features, runs inference, but does NOT mutate the bit.
  Use `evaluate_and_apply/2` for the full pipeline with mutation.

  ## Parameters

  - `bit` - A Thunderbit map
  - `ctx` - Context struct (optional, defaults to new context)

  ## Returns

  - `{:ok, result, ctx}` with evaluation result
  - `{:error, reason}` if extraction or inference fails

  ## Example

      {:ok, result, ctx} = Bridge.evaluate(bit, ctx)
      result.score     # => 0.72
      result.label     # => :high
  """
  @spec evaluate(map(), Context.t() | nil) :: {:ok, evaluation_result(), Context.t()} | {:error, term()}
  def evaluate(bit, ctx \\ nil) do
    start_time = System.monotonic_time()
    ctx = ctx || Context.new()

    with {:ok, feature} <- Feature.from_bit(bit),
         {:ok, inference} <- Scorer.infer(feature) do
      result = %{
        bit_id: feature.bit_id,
        feature: feature,
        score: inference.score,
        label: inference.label,
        next_action: inference.next_action,
        confidence: inference.confidence
      }

      # Emit telemetry
      emit_telemetry(:evaluate, start_time, %{
        bit_id: feature.bit_id,
        score: inference.score,
        label: inference.label
      })

      # Emit event
      ctx = emit_event(ctx, :evaluated, result)

      {:ok, result, ctx}
    else
      {:error, reason} = error ->
        Logger.warning("[Cerebros.Mini.Bridge] Evaluation failed: #{inspect(reason)}")
        emit_telemetry(:evaluate_error, start_time, %{reason: reason})
        error
    end
  end

  @doc """
  Evaluates a batch of Thunderbits.

  More efficient than calling `evaluate/2` in a loop.

  ## Parameters

  - `bits` - List of Thunderbit maps
  - `ctx` - Context struct

  ## Returns

  - `{:ok, [result, ...], ctx}` with list of results
  - `{:error, reason}` if batch fails
  """
  @spec evaluate_batch([map()], Context.t()) :: {:ok, [evaluation_result()], Context.t()} | {:error, term()}
  def evaluate_batch(bits, ctx \\ nil) when is_list(bits) do
    start_time = System.monotonic_time()
    ctx = ctx || Context.new()

    # Extract features
    feature_results =
      bits
      |> Enum.map(&Feature.from_bit/1)
      |> Enum.with_index()

    # Separate successes and failures
    {features, failed_indices} =
      Enum.reduce(feature_results, {[], []}, fn
        {{:ok, feature}, _idx}, {acc, failed} -> {[feature | acc], failed}
        {{:error, _}, idx}, {acc, failed} -> {acc, [idx | failed]}
      end)

    features = Enum.reverse(features)

    # Run batch inference
    case Scorer.infer_batch(features) do
      {:ok, inferences} ->
        # Combine features with inferences
        results =
          Enum.zip(features, inferences)
          |> Enum.map(fn {feature, inference} ->
            %{
              bit_id: feature.bit_id,
              feature: feature,
              score: inference.score,
              label: inference.label,
              next_action: inference.next_action,
              confidence: inference.confidence
            }
          end)

        # Emit batch telemetry
        emit_telemetry(:batch, start_time, %{
          count: length(results),
          failed: length(failed_indices),
          avg_score: average_score(results)
        })

        # Emit batch event
        ctx = emit_event(ctx, :batch_evaluated, %{
          count: length(results),
          labels: Enum.frequencies_by(results, & &1.label)
        })

        {:ok, results, ctx}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Evaluates a Thunderbit and applies the result via Protocol.mutate/3.

  This is the full Cerebros-mini pipeline:

      bit → Feature → Scorer → Result → mutate(bit, changes, ctx)

  ## Applied Changes

  Based on the evaluation result, the following may be mutated:

  - `cerebros_score` - The raw score (0-1)
  - `cerebros_label` - The categorical label
  - `cerebros_action` - Suggested next action
  - `needs_cerebros_eval?` - Set to false after evaluation
  - `last_cerebros_eval` - Timestamp of evaluation

  Additionally, if `next_action` suggests a change:
  - `:boost_energy` → increases energy by 0.1
  - `:flag_for_review` → sets `flagged?: true`

  ## Parameters

  - `bit` - A Thunderbit map
  - `ctx` - Context struct

  ## Returns

  - `{:ok, updated_bit, ctx}` with mutated bit
  - `{:error, reason}` if pipeline fails
  """
  @spec evaluate_and_apply(map(), Context.t()) :: {:ok, map(), Context.t()} | {:error, term()}
  def evaluate_and_apply(bit, ctx \\ nil) do
    ctx = ctx || Context.new()

    with {:ok, result, ctx} <- evaluate(bit, ctx) do
      changes = build_changes(result)

      case Protocol.mutate(bit, changes, ctx) do
        {:ok, updated_bit, ctx} ->
          # Emit event for mutation
          ctx = emit_event(ctx, :result_applied, %{
            bit_id: result.bit_id,
            changes: Map.keys(changes)
          })

          {:ok, updated_bit, ctx}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Evaluates and applies to a batch of bits.

  ## Parameters

  - `bits` - List of Thunderbit maps
  - `ctx` - Context struct

  ## Returns

  - `{:ok, [updated_bit, ...], ctx}` with mutated bits
  """
  @spec evaluate_and_apply_batch([map()], Context.t()) :: {:ok, [map()], Context.t()} | {:error, term()}
  def evaluate_and_apply_batch(bits, ctx \\ nil) when is_list(bits) do
    ctx = ctx || Context.new()

    with {:ok, results, ctx} <- evaluate_batch(bits, ctx) do
      # Create bit_id -> result lookup
      result_map = Map.new(results, &{&1.bit_id, &1})

      # Apply changes to each bit
      {updated_bits, final_ctx} =
        Enum.map_reduce(bits, ctx, fn bit, acc_ctx ->
          bit_id = to_string(bit.id)

          case Map.get(result_map, bit_id) do
            nil ->
              # No result for this bit (extraction failed)
              {bit, acc_ctx}

            result ->
              changes = build_changes(result)

              case Protocol.mutate(bit, changes, acc_ctx) do
                {:ok, updated_bit, new_ctx} -> {updated_bit, new_ctx}
                {:error, _} -> {bit, acc_ctx}
              end
          end
        end)

      {:ok, updated_bits, final_ctx}
    end
  end

  @doc """
  Returns health status of the Cerebros-mini subsystem.
  """
  @spec health() :: map()
  def health do
    %{
      status: :ok,
      model: Scorer.model_info(),
      feature_dim: Feature.dimension()
    }
  end

  # ---------------------------------------------------------------------------
  # Private: Change Building
  # ---------------------------------------------------------------------------

  defp build_changes(result) do
    base_changes = %{
      cerebros_score: result.score,
      cerebros_label: result.label,
      cerebros_action: result.next_action,
      needs_cerebros_eval?: false,
      last_cerebros_eval: DateTime.utc_now()
    }

    # Apply action-specific changes
    case result.next_action do
      :boost_energy ->
        # Get current energy from feature, boost by 0.1
        current_energy = result.feature.energy
        Map.put(base_changes, :energy, min(1.0, current_energy + 0.1))

      :flag_for_review ->
        Map.put(base_changes, :flagged?, true)

      _ ->
        base_changes
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Telemetry & Events
  # ---------------------------------------------------------------------------

  defp emit_telemetry(event, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:thunderline, :cerebros, :mini, event],
      %{duration: duration},
      metadata
    )
  end

  defp emit_event(ctx, event_name, payload) do
    full_name = "cerebros.mini.#{event_name}"

    # Try to use EventBus if available
    case Thunderline.Thunderflow.EventBus.publish_event(%{
           name: full_name,
           source: :cerebros_mini,
           payload: payload,
           meta: %{pipeline: :general}
         }) do
      {:ok, _} -> :ok
      {:error, _} -> :ok  # Non-critical, continue
    end

    # Also emit to context event log
    Context.emit_event(ctx, String.to_atom(full_name), payload)
  rescue
    _ -> ctx
  end

  defp average_score([]), do: 0.0

  defp average_score(results) do
    total = Enum.reduce(results, 0.0, &(&1.score + &2))
    Float.round(total / length(results), 4)
  end
end
