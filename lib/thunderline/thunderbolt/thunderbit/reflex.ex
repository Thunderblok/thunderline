defmodule Thunderline.Thunderbolt.Thunderbit.Reflex do
  @moduledoc """
  Thunderbit Reflexive Intelligence Layer (HC-Ω-1).

  Binds DiffLogic CA to individual Thunderbits, enabling:
  - Local policy override via Thundercrown
  - PLV & λ̂ metrics injection into Thunderbit state
  - Activation reflexes that propagate change events
  - Self-organizing behavior at voxel-level granularity

  ## Architecture

      ┌─────────────────────────────────────────────────────────────┐
      │                  THUNDERBIT REFLEX LAYER                    │
      │                                                             │
      │  ┌──────────┐   ┌──────────────┐   ┌──────────────────┐    │
      │  │ DiffLogic│ → │  Thunderbit  │ → │ LoopMonitor      │    │
      │  │ Gate     │   │  .state      │   │ (local metrics)  │    │
      │  └──────────┘   └──────────────┘   └──────────────────┘    │
      │        │               │                    │               │
      │        │    ┌──────────┴───────────┐       │               │
      │        │    │    REFLEX ENGINE     │       │               │
      │        │    │  ┌───────────────┐   │       │               │
      │        └────│  │ Policy Check  │   │←──────┘               │
      │             │  └───────────────┘   │                       │
      │             │  ┌───────────────┐   │                       │
      │             │  │ Activation    │   │→ EventBus             │
      │             │  │ Propagation   │   │                       │
      │             │  └───────────────┘   │                       │
      │             └──────────────────────┘                       │
      └─────────────────────────────────────────────────────────────┘

  ## Reflexes

  A reflex is a condition → action pair that fires automatically:

  - **Stability Reflex**: σ_flow drops → reduce trust, emit warning
  - **Chaos Reflex**: λ̂ spikes → trigger path collapse, quarantine
  - **Presence Reflex**: PAC approaches → adjust relay weight
  - **Trust Reflex**: Successful relay → boost trust score
  - **Decay Reflex**: Long idle → reduce presence, prepare for GC

  ## Usage

      # Apply a reflex step to a Thunderbit
      {:ok, updated_bit, events} = Reflex.step(bit, neighbors, metrics, policy)

      # Check if activation should propagate
      {:propagate, targets} = Reflex.check_propagation(bit, event)

      # Apply DiffLogic rule with policy override
      {:ok, new_state} = Reflex.apply_rule(bit, neighbors, gate_logits, policy)
  """

  alias Thunderline.Thunderbolt.Thunderbit
  alias Thunderline.Thunderbolt.DiffLogic.Gates
  alias Thunderline.Thunderbolt.Cerebros.PACCompute
  alias Thunderline.Event
  alias Thunderline.Thunderflow.EventBus
  require Logger

  @telemetry_event [:thunderline, :thunderbit, :reflex]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type reflex_type ::
          :stability
          | :chaos
          | :presence
          | :trust
          | :decay
          | :activation

  @type policy :: %{
          optional(:stability_threshold) => float(),
          optional(:chaos_threshold) => float(),
          optional(:trust_boost) => float(),
          optional(:trust_penalty) => float(),
          optional(:decay_rate) => float(),
          optional(:propagation_enabled) => boolean(),
          optional(:override_rules) => map()
        }

  @type neighbor_state :: %{
          coord: Thunderbit.coord(),
          sigma_flow: float(),
          phi_phase: float(),
          lambda_sensitivity: float(),
          trust_score: float()
        }

  @type local_metrics :: %{
          plv: float(),
          entropy: float(),
          lambda_hat: float(),
          neighbor_count: non_neg_integer()
        }

  @type reflex_event :: %{
          type: reflex_type(),
          bit_id: String.t(),
          coord: Thunderbit.coord(),
          trigger: atom(),
          data: map()
        }

  @type step_result :: {:ok, Thunderbit.t(), [reflex_event()]}

  # ═══════════════════════════════════════════════════════════════
  # Main Entry Point
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Performs a complete reflex step on a Thunderbit.

  1. Computes local metrics from neighbors
  2. Applies DiffLogic rule (with policy override)
  3. Evaluates all reflex conditions
  4. Fires triggered reflexes
  5. Returns updated Thunderbit and emitted events

  ## Parameters

  - `bit` - The Thunderbit to update
  - `neighbors` - List of neighbor state maps
  - `gate_logits` - DiffLogic gate weights (Nx tensor)
  - `policy` - Thundercrown policy overrides
  - `tick` - Current simulation tick

  ## Returns

  `{:ok, updated_bit, events}` where events are reflex activations
  """
  @spec step(Thunderbit.t(), [neighbor_state()], Nx.Tensor.t(), policy(), non_neg_integer()) ::
          step_result()
  def step(%Thunderbit{} = bit, neighbors, gate_logits, policy \\ %{}, tick \\ 0) do
    started = System.monotonic_time(:microsecond)

    # 1. Compute local metrics
    local_metrics = compute_local_metrics(bit, neighbors)

    # 2. Apply DiffLogic rule
    {new_state, new_flow, new_phase, new_lambda} =
      apply_rule(bit, neighbors, gate_logits, policy)

    # 3. Inject metrics into Thunderbit
    updated_bit =
      bit
      |> Thunderbit.update_state(
        state: new_state,
        sigma_flow: new_flow,
        phi_phase: new_phase,
        lambda_sensitivity: new_lambda,
        tick: tick
      )
      |> inject_local_metrics(local_metrics)

    # 4. Evaluate and fire reflexes
    {final_bit, events} = evaluate_reflexes(updated_bit, local_metrics, policy)

    # 5. Telemetry
    duration_us = System.monotonic_time(:microsecond) - started

    :telemetry.execute(
      @telemetry_event,
      %{duration_us: duration_us, reflex_count: length(events)},
      %{bit_id: bit.id, coord: bit.coord}
    )

    {:ok, final_bit, events}
  end

  @doc """
  Applies DiffLogic rule with policy override.

  Policy can override:
  - Gate selection (force specific gate)
  - Lambda modulation
  - Bias adjustment
  - Complete rule bypass
  """
  @spec apply_rule(Thunderbit.t(), [neighbor_state()], Nx.Tensor.t(), policy()) ::
          {atom(), float(), float(), float()}
  def apply_rule(%Thunderbit{} = bit, neighbors, gate_logits, policy) do
    # Check for complete rule override
    case Map.get(policy, :override_rules) do
      %{rule: override_rule} ->
        apply_override_rule(bit, neighbors, override_rule)

      _ ->
        apply_difflogic_rule(bit, neighbors, gate_logits, policy)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Local Metrics Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes local criticality metrics from a Thunderbit's neighborhood.

  These metrics are injected into the Thunderbit for:
  - Reflex condition evaluation
  - LoopMonitor aggregation
  - Visualization
  """
  @spec compute_local_metrics(Thunderbit.t(), [neighbor_state()]) :: local_metrics()
  def compute_local_metrics(%Thunderbit{} = bit, neighbors) do
    neighbor_count = length(neighbors)

    if neighbor_count == 0 do
      %{plv: 0.5, entropy: 0.5, lambda_hat: bit.lambda_sensitivity, neighbor_count: 0}
    else
      # Local PLV: phase coherence with neighbors
      plv = compute_local_plv(bit.phi_phase, neighbors)

      # Local entropy: flow variance
      entropy = compute_local_entropy(bit.sigma_flow, neighbors)

      # Lambda hat: average sensitivity in neighborhood
      lambda_hat = compute_local_lambda(bit.lambda_sensitivity, neighbors)

      %{
        plv: plv,
        entropy: entropy,
        lambda_hat: lambda_hat,
        neighbor_count: neighbor_count
      }
    end
  end

  defp compute_local_plv(my_phase, neighbors) do
    # Mean resultant length of phase differences
    {sum_cos, sum_sin} =
      neighbors
      |> Enum.reduce({0.0, 0.0}, fn n, {sc, ss} ->
        diff = my_phase - n.phi_phase
        {sc + :math.cos(diff), ss + :math.sin(diff)}
      end)

    n = length(neighbors)
    mean_cos = sum_cos / n
    mean_sin = sum_sin / n
    :math.sqrt(mean_cos * mean_cos + mean_sin * mean_sin)
  end

  defp compute_local_entropy(my_flow, neighbors) do
    flows = [my_flow | Enum.map(neighbors, & &1.sigma_flow)]
    mean_flow = Enum.sum(flows) / length(flows)

    variance =
      flows
      |> Enum.map(fn f -> (f - mean_flow) ** 2 end)
      |> Enum.sum()
      |> Kernel./(length(flows))

    # Normalize variance to [0, 1] entropy-like value
    # High variance = high entropy
    min(1.0, :math.sqrt(variance) * 2)
  end

  defp compute_local_lambda(my_lambda, neighbors) do
    lambdas = [my_lambda | Enum.map(neighbors, & &1.lambda_sensitivity)]
    Enum.sum(lambdas) / length(lambdas)
  end

  defp inject_local_metrics(%Thunderbit{} = bit, metrics) do
    # Store metrics in presence_vector under special key
    metrics_entry = %{
      type: :local_metrics,
      plv: metrics.plv,
      entropy: metrics.entropy,
      lambda_hat: metrics.lambda_hat,
      neighbor_count: metrics.neighbor_count,
      computed_at: System.system_time(:millisecond)
    }

    Thunderbit.add_presence(bit, "__local_metrics__", metrics_entry)
  end

  # ═══════════════════════════════════════════════════════════════
  # DiffLogic Rule Application
  # ═══════════════════════════════════════════════════════════════

  defp apply_difflogic_rule(bit, neighbors, gate_logits, policy) do
    if length(neighbors) == 0 do
      # Isolated - apply decay
      decay_rate = Map.get(policy, :decay_rate, 0.99)
      {bit.state, bit.sigma_flow * decay_rate, bit.phi_phase, bit.lambda_sensitivity}
    else
      # Get policy parameters
      lambda_mod = Map.get(policy, :lambda_modulation, 0.5)
      bias = Map.get(policy, :bias, 0.3)

      # Compute neighbor average
      neighbor_flows = Enum.map(neighbors, & &1.sigma_flow)
      avg_flow = Enum.sum(neighbor_flows) / length(neighbor_flows)

      # Apply DiffLogic soft gate
      a = Nx.tensor([bit.sigma_flow])
      b = Nx.tensor([avg_flow])
      new_flow_tensor = Gates.soft_gate(a, b, gate_logits)
      new_flow = Nx.to_number(Nx.squeeze(new_flow_tensor))

      # Apply lambda modulation
      new_flow = new_flow * lambda_mod + bias * (1.0 - lambda_mod)
      new_flow = max(0.0, min(1.0, new_flow))

      # Phase advancement
      new_phase = Float.mod(bit.phi_phase + new_flow * 0.1, 2 * :math.pi())

      # Lambda sensitivity from variance
      variance =
        neighbor_flows
        |> Enum.map(fn f -> (f - avg_flow) ** 2 end)
        |> Enum.sum()
        |> Kernel./(length(neighbor_flows))

      new_lambda = bit.lambda_sensitivity * 0.9 + variance * 0.5
      new_lambda = max(0.0, min(1.0, new_lambda))

      # Derive state
      new_state = derive_state(new_flow, new_lambda)

      {new_state, new_flow, new_phase, new_lambda}
    end
  end

  defp apply_override_rule(bit, _neighbors, :freeze) do
    # Freeze: no change
    {bit.state, bit.sigma_flow, bit.phi_phase, bit.lambda_sensitivity}
  end

  defp apply_override_rule(bit, _neighbors, :collapse) do
    # Collapse: zero out everything
    {:collapsed, 0.0, 0.0, 1.0}
  end

  defp apply_override_rule(bit, _neighbors, :activate) do
    # Force activation
    {:active, 1.0, bit.phi_phase, 0.0}
  end

  defp apply_override_rule(bit, neighbors, {:custom, fun}) when is_function(fun, 2) do
    fun.(bit, neighbors)
  end

  defp derive_state(_flow, lambda) when lambda > 0.8, do: :chaotic
  defp derive_state(flow, _lambda) when flow > 0.8, do: :active
  defp derive_state(flow, _lambda) when flow > 0.5, do: :stable
  defp derive_state(flow, _lambda) when flow > 0.2, do: :dormant
  defp derive_state(_flow, _lambda), do: :inactive

  # ═══════════════════════════════════════════════════════════════
  # Reflex Evaluation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Evaluates all reflex conditions and fires triggered reflexes.

  Returns updated Thunderbit and list of reflex events.
  """
  @spec evaluate_reflexes(Thunderbit.t(), local_metrics(), policy()) ::
          {Thunderbit.t(), [reflex_event()]}
  def evaluate_reflexes(%Thunderbit{} = bit, metrics, policy) do
    reflexes = [
      {:stability, &evaluate_stability_reflex/3},
      {:chaos, &evaluate_chaos_reflex/3},
      {:decay, &evaluate_decay_reflex/3},
      {:trust, &evaluate_trust_reflex/3}
    ]

    {final_bit, events} =
      Enum.reduce(reflexes, {bit, []}, fn {type, eval_fn}, {current_bit, acc_events} ->
        case eval_fn.(current_bit, metrics, policy) do
          {:fire, updated_bit, event} ->
            full_event = %{
              type: type,
              bit_id: current_bit.id,
              coord: current_bit.coord,
              trigger: event.trigger,
              data: event.data
            }

            {updated_bit, [full_event | acc_events]}

          :skip ->
            {current_bit, acc_events}
        end
      end)

    # Emit events to EventBus if propagation enabled
    if Map.get(policy, :propagation_enabled, true) do
      Enum.each(events, &emit_reflex_event/1)
    end

    {final_bit, Enum.reverse(events)}
  end

  defp evaluate_stability_reflex(bit, metrics, policy) do
    threshold = Map.get(policy, :stability_threshold, 0.3)

    if bit.sigma_flow < threshold do
      # Apply trust penalty
      penalty = Map.get(policy, :trust_penalty, -0.05)
      updated_bit = Thunderbit.update_trust(bit, penalty)

      {:fire, updated_bit,
       %{
         trigger: :low_stability,
         data: %{
           sigma_flow: bit.sigma_flow,
           threshold: threshold,
           trust_delta: penalty
         }
       }}
    else
      :skip
    end
  end

  defp evaluate_chaos_reflex(bit, metrics, policy) do
    threshold = Map.get(policy, :chaos_threshold, 0.8)

    if metrics.lambda_hat > threshold do
      # Mark for quarantine
      updated_bit = Thunderbit.add_presence(bit, "__quarantine__", %{
        reason: :chaos_spike,
        lambda_hat: metrics.lambda_hat,
        quarantined_at: System.system_time(:millisecond)
      })

      {:fire, updated_bit,
       %{
         trigger: :chaos_spike,
         data: %{
           lambda_hat: metrics.lambda_hat,
           threshold: threshold,
           action: :quarantine
         }
       }}
    else
      :skip
    end
  end

  defp evaluate_decay_reflex(bit, _metrics, policy) do
    # Check for long idle
    decay_threshold_ms = Map.get(policy, :decay_threshold_ms, 60_000)

    case Map.get(bit.presence_vector, "__local_metrics__") do
      %{computed_at: last_compute} ->
        age_ms = System.system_time(:millisecond) - last_compute

        if age_ms > decay_threshold_ms do
          decay_rate = Map.get(policy, :decay_rate, 0.9)
          updated_bit = Thunderbit.decay_presence(bit, decay_rate)

          {:fire, updated_bit,
           %{
             trigger: :idle_decay,
             data: %{
               age_ms: age_ms,
               decay_rate: decay_rate
             }
           }}
        else
          :skip
        end

      _ ->
        :skip
    end
  end

  defp evaluate_trust_reflex(bit, metrics, policy) do
    # Boost trust when stable and coherent
    stability_threshold = Map.get(policy, :stability_threshold, 0.3)
    plv_threshold = Map.get(policy, :plv_threshold, 0.6)

    if bit.sigma_flow > stability_threshold and metrics.plv > plv_threshold do
      boost = Map.get(policy, :trust_boost, 0.02)
      updated_bit = Thunderbit.update_trust(bit, boost)

      {:fire, updated_bit,
       %{
         trigger: :trust_boost,
         data: %{
           sigma_flow: bit.sigma_flow,
           plv: metrics.plv,
           trust_delta: boost
         }
       }}
    else
      :skip
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Propagation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Checks if an activation should propagate to neighbors.

  Returns `{:propagate, target_coords}` or `:no_propagate`.
  """
  @spec check_propagation(Thunderbit.t(), reflex_event()) ::
          {:propagate, [Thunderbit.coord()]} | :no_propagate
  def check_propagation(%Thunderbit{} = bit, %{type: :chaos_spike}) do
    # Chaos propagates to all neighbors for warning
    {:propagate, bit.neighborhood}
  end

  def check_propagation(%Thunderbit{} = bit, %{type: :stability, trigger: :low_stability}) do
    # Stability warnings propagate to neighbors with high flow
    # (they might be affected)
    {:propagate, bit.neighborhood}
  end

  def check_propagation(_bit, _event), do: :no_propagate

  defp emit_reflex_event(reflex_event) do
    event_name = "bolt.thunderbit.reflex.#{reflex_event.type}"

    payload = %{
      bit_id: reflex_event.bit_id,
      coord: reflex_event.coord,
      trigger: reflex_event.trigger,
      data: reflex_event.data,
      emitted_at: System.system_time(:millisecond)
    }

    case Event.new(name: event_name, source: :bolt, payload: payload, meta: %{pipeline: :realtime}) do
      {:ok, event} ->
        EventBus.publish_event(event)

      {:error, reason} ->
        Logger.warning("[Thunderbit.Reflex] Failed to emit event: #{inspect(reason)}")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Batch Operations
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Applies reflex step to multiple Thunderbits in parallel.

  Useful for grid-level updates with proper neighbor resolution.
  """
  @spec batch_step(
          %{Thunderbit.coord() => Thunderbit.t()},
          Nx.Tensor.t(),
          policy(),
          non_neg_integer()
        ) ::
          {%{Thunderbit.coord() => Thunderbit.t()}, [reflex_event()]}
  def batch_step(bits_map, gate_logits, policy \\ %{}, tick \\ 0) do
    bits_map
    |> Task.async_stream(
      fn {coord, bit} ->
        # Resolve neighbors from the bits map
        neighbors =
          bit.neighborhood
          |> Enum.map(fn n_coord -> Map.get(bits_map, n_coord) end)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&to_neighbor_state/1)

        {:ok, updated_bit, events} = step(bit, neighbors, gate_logits, policy, tick)
        {coord, updated_bit, events}
      end,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce({%{}, []}, fn {:ok, {coord, bit, events}}, {bits_acc, events_acc} ->
      {Map.put(bits_acc, coord, bit), events ++ events_acc}
    end)
  end

  defp to_neighbor_state(%Thunderbit{} = bit) do
    %{
      coord: bit.coord,
      sigma_flow: bit.sigma_flow,
      phi_phase: bit.phi_phase,
      lambda_sensitivity: bit.lambda_sensitivity,
      trust_score: bit.trust_score
    }
  end
end
