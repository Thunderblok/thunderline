defmodule Thunderline.Thunderpac.Evolution do
  @moduledoc """
  Thunderpac Evolution System (HC-Ω-2).

  Exposes PAC traits as tunable TPE parameters and feeds LoopMonitor +
  PAC metrics into Bayesian optimization for evolutionary PAC development.

  ## Architecture

      ┌─────────────────────────────────────────────────────────────────┐
      │                    PAC EVOLUTION ENGINE                         │
      │                                                                 │
      │  ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐    │
      │  │ PAC Traits   │ → │ TPE Bridge   │ → │ Optimization     │    │
      │  │ trait_vector │   │ suggest_     │   │ suggest, record  │    │
      │  │ persona      │   │ record       │   └──────────────────┘    │
      │  └──────────────┘   └──────────────┘           │               │
      │         │                                       │               │
      │         ↓                                       ↓               │
      │  ┌──────────────────────────────────────────────────────┐      │
      │  │              EVOLUTION PROFILES                       │      │
      │  │                                                       │      │
      │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐         │      │
      │  │  │ Explorer  │  │ Exploiter │  │ Balanced  │ ...     │      │
      │  │  │ Profile   │  │ Profile   │  │ Profile   │         │      │
      │  │  └───────────┘  └───────────┘  └───────────┘         │      │
      │  └──────────────────────────────────────────────────────┘      │
      │                           │                                     │
      │                           ↓                                     │
      │  ┌──────────────────────────────────────────────────────┐      │
      │  │                FITNESS EVALUATION                     │      │
      │  │                                                       │      │
      │  │  LoopMonitor Metrics:  │  PAC Metrics:                │      │
      │  │  - PLV (coherence)     │  - Intent completion rate    │      │
      │  │  - Entropy (chaos)     │  - Session stability         │      │
      │  │  - λ̂ (sensitivity)    │  - Trust score evolution     │      │
      │  │  - Lyapunov exponent   │  - Memory efficiency         │      │
      │  └──────────────────────────────────────────────────────┘      │
      │                           │                                     │
      │                           ↓                                     │
      │  ┌──────────────────────────────────────────────────────┐      │
      │  │              PAC LINEAGE TRACKING                     │      │
      │  │  Parent → Child evolution with trait inheritance      │      │
      │  └──────────────────────────────────────────────────────┘      │
      └─────────────────────────────────────────────────────────────────┘

  ## Evolution Profiles

  - **Explorer**: High entropy tolerance, seeks novelty
  - **Exploiter**: Low entropy, optimizes known patterns
  - **Balanced**: Edge-of-chaos target, optimal adaptability
  - **Resilient**: High stability threshold, fault-tolerant
  - **Aggressive**: High λ, fast response to changes

  ## Usage

      # Start evolution for a PAC
      {:ok, session} = Evolution.start_session(pac_id)

      # Run evolution step
      {:ok, updated_pac, metrics} = Evolution.step(pac, metrics)

      # Get best parameters found
      {:ok, best} = Evolution.best_params(session)

      # Apply evolved traits to PAC
      {:ok, evolved_pac} = Evolution.apply_evolution(pac, best)

  ## Events

  - `pac.evolution.started` - Evolution session began
  - `pac.evolution.step` - Evolution step completed
  - `pac.evolution.improved` - Better fitness found
  - `pac.evolution.profile_switched` - Profile changed
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Cerebros.TPEBridge
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Event

  @telemetry_event [:thunderline, :pac, :evolution]

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type profile ::
          :explorer
          | :exploiter
          | :balanced
          | :resilient
          | :aggressive
          | :custom

  @type trait_bounds :: %{
          min: float(),
          max: float(),
          default: float()
        }

  @type evolution_config :: %{
          optional(:profile) => profile(),
          optional(:max_generations) => pos_integer(),
          optional(:population_size) => pos_integer(),
          optional(:mutation_rate) => float(),
          optional(:crossover_rate) => float(),
          optional(:elite_count) => pos_integer(),
          optional(:fitness_weights) => map()
        }

  @type fitness_result :: %{
          total: float(),
          components: %{
            stability: float(),
            coherence: float(),
            adaptability: float(),
            efficiency: float()
          }
        }

  @type lineage_entry :: %{
          generation: non_neg_integer(),
          pac_id: String.t(),
          parent_id: String.t() | nil,
          traits: [float()],
          fitness: float(),
          profile: profile(),
          timestamp: DateTime.t()
        }

  # ═══════════════════════════════════════════════════════════════
  # Evolution Profiles - Predefined Trait Configurations
  # ═══════════════════════════════════════════════════════════════

  @profiles %{
    explorer: %{
      description: "High entropy tolerance, seeks novelty",
      fitness_weights: %{stability: 0.2, coherence: 0.2, adaptability: 0.4, efficiency: 0.2},
      trait_modifiers: %{
        entropy_tolerance: 0.8,
        novelty_bonus: 0.3,
        lambda_target: 0.4,
        plv_target: 0.3
      }
    },
    exploiter: %{
      description: "Low entropy, optimizes known patterns",
      fitness_weights: %{stability: 0.4, coherence: 0.3, adaptability: 0.1, efficiency: 0.2},
      trait_modifiers: %{
        entropy_tolerance: 0.2,
        novelty_bonus: 0.0,
        lambda_target: 0.15,
        plv_target: 0.7
      }
    },
    balanced: %{
      description: "Edge-of-chaos target, optimal adaptability",
      fitness_weights: %{stability: 0.25, coherence: 0.25, adaptability: 0.25, efficiency: 0.25},
      trait_modifiers: %{
        entropy_tolerance: 0.5,
        novelty_bonus: 0.15,
        # Langton's λc
        lambda_target: 0.273,
        plv_target: 0.4
      }
    },
    resilient: %{
      description: "High stability threshold, fault-tolerant",
      fitness_weights: %{stability: 0.5, coherence: 0.2, adaptability: 0.1, efficiency: 0.2},
      trait_modifiers: %{
        entropy_tolerance: 0.3,
        novelty_bonus: 0.0,
        lambda_target: 0.2,
        plv_target: 0.6
      }
    },
    aggressive: %{
      description: "High λ, fast response to changes",
      fitness_weights: %{stability: 0.1, coherence: 0.2, adaptability: 0.5, efficiency: 0.2},
      trait_modifiers: %{
        entropy_tolerance: 0.7,
        novelty_bonus: 0.25,
        lambda_target: 0.5,
        plv_target: 0.35
      }
    }
  }

  # Default trait bounds for TPE optimization
  @trait_bounds %{
    # Behavioral traits (0-5 in trait_vector)
    aggression: %{min: 0.0, max: 1.0, default: 0.5},
    curiosity: %{min: 0.0, max: 1.0, default: 0.5},
    caution: %{min: 0.0, max: 1.0, default: 0.5},
    persistence: %{min: 0.0, max: 1.0, default: 0.5},
    adaptability: %{min: 0.0, max: 1.0, default: 0.5},
    sociability: %{min: 0.0, max: 1.0, default: 0.5},
    # CA-related traits (6-9 in trait_vector)
    lambda_sensitivity: %{min: 0.0, max: 1.0, default: 0.273},
    entropy_tolerance: %{min: 0.0, max: 1.0, default: 0.5},
    phase_coherence: %{min: 0.0, max: 1.0, default: 0.4},
    flow_stability: %{min: 0.0, max: 1.0, default: 0.5}
  }

  # ═══════════════════════════════════════════════════════════════
  # GenServer Setup
  # ═══════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      sessions: %{},
      lineages: %{},
      config: Keyword.get(opts, :config, default_config()),
      tpe_bridge: Keyword.get(opts, :tpe_bridge)
    }

    Logger.info("[Thunderpac.Evolution] Initialized")
    {:ok, state}
  end

  defp default_config do
    %{
      profile: :balanced,
      max_generations: 100,
      population_size: 20,
      mutation_rate: 0.1,
      crossover_rate: 0.7,
      elite_count: 2,
      fitness_weights: %{stability: 0.25, coherence: 0.25, adaptability: 0.25, efficiency: 0.25}
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts an evolution session for a PAC.

  ## Options

  - `:profile` - Evolution profile (:explorer, :exploiter, :balanced, etc.)
  - `:max_generations` - Maximum generations to run
  - `:config` - Custom evolution configuration

  ## Returns

  `{:ok, session_id}` on success
  """
  @spec start_session(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_session(pac_id, opts \\ []) do
    GenServer.call(__MODULE__, {:start_session, pac_id, opts})
  end

  @doc """
  Performs an evolution step on a PAC.

  Takes current PAC state and LoopMonitor metrics, suggests new trait
  parameters via TPE, evaluates fitness, and returns evolved PAC.
  """
  @spec step(map(), map(), keyword()) :: {:ok, map(), fitness_result()} | {:error, term()}
  def step(pac, metrics, opts \\ []) do
    GenServer.call(__MODULE__, {:step, pac, metrics, opts}, 30_000)
  end

  @doc """
  Gets the best parameters found for a PAC evolution session.
  """
  @spec best_params(String.t()) :: {:ok, map()} | {:error, term()}
  def best_params(pac_id) do
    GenServer.call(__MODULE__, {:best_params, pac_id})
  end

  @doc """
  Applies evolved traits to a PAC.

  Updates the PAC's trait_vector and persona with optimized values.
  """
  @spec apply_evolution(map(), map()) :: {:ok, map()}
  def apply_evolution(pac, evolved_traits) do
    trait_vector = traits_to_vector(evolved_traits)

    updated_persona =
      Map.merge(pac.persona || %{}, %{
        "evolved" => true,
        "evolution_timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "evolution_traits" => evolved_traits
      })

    updated_pac = %{
      pac
      | trait_vector: trait_vector,
        persona: updated_persona
    }

    {:ok, updated_pac}
  end

  @doc """
  Gets the lineage history for a PAC.
  """
  @spec get_lineage(String.t()) :: {:ok, [lineage_entry()]} | {:error, term()}
  def get_lineage(pac_id) do
    GenServer.call(__MODULE__, {:get_lineage, pac_id})
  end

  @doc """
  Lists all available evolution profiles.
  """
  @spec list_profiles() :: %{profile() => map()}
  def list_profiles, do: @profiles

  @doc """
  Gets configuration for a specific profile.
  """
  @spec get_profile(profile()) :: {:ok, map()} | {:error, :not_found}
  def get_profile(profile) do
    case Map.get(@profiles, profile) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  @doc """
  Switches evolution profile for an active session.
  """
  @spec switch_profile(String.t(), profile()) :: :ok | {:error, term()}
  def switch_profile(pac_id, new_profile) do
    GenServer.call(__MODULE__, {:switch_profile, pac_id, new_profile})
  end

  @doc """
  Spawns a child PAC from a parent with inherited traits.

  Child inherits traits from parent with optional mutation.
  """
  @spec spawn_child(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def spawn_child(parent_pac_id, opts \\ []) do
    GenServer.call(__MODULE__, {:spawn_child, parent_pac_id, opts})
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def handle_call({:start_session, pac_id, opts}, _from, state) do
    profile = Keyword.get(opts, :profile, state.config.profile)
    config = Keyword.get(opts, :config, state.config)

    session_id = "evo_#{pac_id}_#{System.unique_integer([:positive])}"

    session = %{
      id: session_id,
      pac_id: pac_id,
      profile: profile,
      config: Map.merge(config, %{profile: profile}),
      generation: 0,
      best_fitness: 0.0,
      best_traits: nil,
      history: [],
      started_at: DateTime.utc_now()
    }

    new_sessions = Map.put(state.sessions, pac_id, session)

    # Initialize TPE bridge for this session if available
    if state.tpe_bridge do
      Task.start(fn -> TPEBridge.reset(state.tpe_bridge) end)
    end

    emit_evolution_event(:started, pac_id, %{
      session_id: session_id,
      profile: profile,
      config: config
    })

    {:reply, {:ok, session_id}, %{state | sessions: new_sessions}}
  end

  @impl true
  def handle_call({:step, pac, metrics, opts}, _from, state) do
    pac_id = pac.id
    started = System.monotonic_time(:microsecond)

    case Map.get(state.sessions, pac_id) do
      nil ->
        # Auto-start session if not exists
        session = create_default_session(pac_id, state.config)
        new_state = %{state | sessions: Map.put(state.sessions, pac_id, session)}
        do_evolution_step(pac, metrics, session, opts, new_state, started)

      session ->
        do_evolution_step(pac, metrics, session, opts, state, started)
    end
  end

  @impl true
  def handle_call({:best_params, pac_id}, _from, state) do
    case Map.get(state.sessions, pac_id) do
      nil ->
        {:reply, {:error, :no_session}, state}

      session ->
        if session.best_traits do
          {:reply, {:ok, session.best_traits}, state}
        else
          {:reply, {:error, :no_evolution_yet}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_lineage, pac_id}, _from, state) do
    lineage = Map.get(state.lineages, pac_id, [])
    {:reply, {:ok, lineage}, state}
  end

  @impl true
  def handle_call({:switch_profile, pac_id, new_profile}, _from, state) do
    case Map.get(state.sessions, pac_id) do
      nil ->
        {:reply, {:error, :no_session}, state}

      session ->
        case Map.get(@profiles, new_profile) do
          nil ->
            {:reply, {:error, :invalid_profile}, state}

          profile_config ->
            updated_session = %{
              session
              | profile: new_profile,
                config: Map.merge(session.config, profile_config)
            }

            new_sessions = Map.put(state.sessions, pac_id, updated_session)

            emit_evolution_event(:profile_switched, pac_id, %{
              old_profile: session.profile,
              new_profile: new_profile
            })

            {:reply, :ok, %{state | sessions: new_sessions}}
        end
    end
  end

  @impl true
  def handle_call({:spawn_child, parent_pac_id, opts}, _from, state) do
    case Map.get(state.sessions, parent_pac_id) do
      nil ->
        {:reply, {:error, :parent_not_found}, state}

      parent_session ->
        mutation_rate = Keyword.get(opts, :mutation_rate, state.config.mutation_rate)

        # Get parent's best traits or current traits
        parent_traits = parent_session.best_traits || default_traits()

        # Apply mutation
        child_traits = mutate_traits(parent_traits, mutation_rate)

        # Create child PAC data
        child_id = "pac_#{System.unique_integer([:positive])}"

        child_pac = %{
          id: child_id,
          name: "child_of_#{parent_pac_id}",
          trait_vector: traits_to_vector(child_traits),
          persona: %{
            "lineage" => %{
              "parent_id" => parent_pac_id,
              "generation" => parent_session.generation + 1,
              "inherited_traits" => parent_traits,
              "mutated_traits" => child_traits
            }
          }
        }

        # Record lineage
        lineage_entry = %{
          generation: parent_session.generation + 1,
          pac_id: child_id,
          parent_id: parent_pac_id,
          traits: traits_to_vector(child_traits),
          fitness: 0.0,
          profile: parent_session.profile,
          timestamp: DateTime.utc_now()
        }

        parent_lineage = Map.get(state.lineages, parent_pac_id, [])
        child_lineage = parent_lineage ++ [lineage_entry]

        new_lineages =
          state.lineages
          |> Map.put(parent_pac_id, child_lineage)
          |> Map.put(child_id, [lineage_entry])

        {:reply, {:ok, child_pac}, %{state | lineages: new_lineages}}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Evolution Logic
  # ═══════════════════════════════════════════════════════════════

  defp do_evolution_step(pac, metrics, session, _opts, state, started) do
    profile_config = Map.get(@profiles, session.profile, @profiles.balanced)

    # 1. Convert current PAC traits to TPE parameter space
    current_traits = vector_to_traits(pac.trait_vector)

    # 2. Suggest new traits via TPE
    suggested_traits =
      if state.tpe_bridge do
        suggest_via_tpe(state.tpe_bridge, current_traits)
      else
        suggest_random(current_traits)
      end

    # 3. Compute fitness from metrics
    fitness = compute_fitness(metrics, pac, profile_config)

    # 4. Record trial with TPE
    if state.tpe_bridge do
      Task.start(fn ->
        TPEBridge.record_trial(state.tpe_bridge, suggested_traits, fitness.total)
      end)
    end

    # 5. Check if this is the best so far
    {best_fitness, best_traits, improved} =
      if fitness.total > session.best_fitness do
        {fitness.total, suggested_traits, true}
      else
        {session.best_fitness, session.best_traits, false}
      end

    # 6. Apply suggested traits to PAC
    {:ok, evolved_pac} = apply_evolution(pac, suggested_traits)

    # 7. Update session
    history_entry = %{
      generation: session.generation,
      traits: suggested_traits,
      fitness: fitness,
      timestamp: DateTime.utc_now()
    }

    updated_session = %{
      session
      | generation: session.generation + 1,
        best_fitness: best_fitness,
        best_traits: best_traits,
        history: [history_entry | session.history] |> Enum.take(100)
    }

    new_sessions = Map.put(state.sessions, pac.id, updated_session)

    # 8. Record lineage
    lineage_entry = %{
      generation: updated_session.generation,
      pac_id: pac.id,
      parent_id: nil,
      traits: traits_to_vector(suggested_traits),
      fitness: fitness.total,
      profile: session.profile,
      timestamp: DateTime.utc_now()
    }

    current_lineage = Map.get(state.lineages, pac.id, [])

    new_lineages =
      Map.put(state.lineages, pac.id, [lineage_entry | current_lineage] |> Enum.take(1000))

    # 9. Emit events
    emit_evolution_event(:step, pac.id, %{
      generation: updated_session.generation,
      fitness: fitness,
      improved: improved
    })

    if improved do
      emit_evolution_event(:improved, pac.id, %{
        generation: updated_session.generation,
        fitness: fitness.total,
        traits: suggested_traits
      })
    end

    # 10. Telemetry
    duration_us = System.monotonic_time(:microsecond) - started

    :telemetry.execute(
      @telemetry_event,
      %{duration_us: duration_us, fitness: fitness.total, generation: updated_session.generation},
      %{pac_id: pac.id, profile: session.profile, improved: improved}
    )

    {:reply, {:ok, evolved_pac, fitness},
     %{state | sessions: new_sessions, lineages: new_lineages}}
  end

  defp create_default_session(pac_id, config) do
    %{
      id: "evo_#{pac_id}_#{System.unique_integer([:positive])}",
      pac_id: pac_id,
      profile: config.profile,
      config: config,
      generation: 0,
      best_fitness: 0.0,
      best_traits: nil,
      history: [],
      started_at: DateTime.utc_now()
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Fitness Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes fitness score from LoopMonitor metrics and PAC state.

  Fitness components:
  - **Stability**: Low entropy, consistent flow
  - **Coherence**: High PLV, synchronized with neighbors
  - **Adaptability**: λ near edge-of-chaos (0.273)
  - **Efficiency**: Good intent completion, low memory bloat
  """
  @spec compute_fitness(map(), map(), map()) :: fitness_result()
  def compute_fitness(metrics, pac, profile_config) do
    weights = profile_config.fitness_weights
    modifiers = profile_config.trait_modifiers

    # Extract metrics (with defaults)
    plv = Map.get(metrics, :plv, 0.5)
    entropy = Map.get(metrics, :entropy, 0.5)
    lambda_hat = Map.get(metrics, :lambda_hat, 0.273)
    lyapunov = Map.get(metrics, :lyapunov, 0.0)

    # Stability: inverse entropy (high entropy = low stability)
    stability_raw = 1.0 - entropy

    stability =
      if entropy <= modifiers.entropy_tolerance,
        do: stability_raw * 1.2,
        else: stability_raw * 0.8

    stability = clamp(stability)

    # Coherence: PLV vs target
    plv_target = modifiers.plv_target
    coherence_raw = 1.0 - abs(plv - plv_target) / max(plv_target, 1.0 - plv_target)
    coherence = clamp(coherence_raw)

    # Adaptability: λ̂ near target (edge-of-chaos)
    lambda_target = modifiers.lambda_target
    lambda_distance = abs(lambda_hat - lambda_target)
    adaptability_raw = 1.0 - lambda_distance / max(lambda_target, 1.0 - lambda_target)

    # Bonus for Lyapunov ≈ 0 (edge-of-chaos)
    lyapunov_bonus = 1.0 - min(1.0, abs(lyapunov) * 2)
    adaptability = clamp(adaptability_raw * 0.7 + lyapunov_bonus * 0.3)

    # Efficiency: based on PAC state
    intent_queue_size = length(Map.get(pac, :intent_queue, []))
    memory_size = map_size(Map.get(pac, :memory_state, %{}))
    session_count = Map.get(pac, :session_count, 1)

    # Penalize large queues, reward completed intents
    queue_penalty = min(1.0, intent_queue_size / 10.0)
    memory_efficiency = 1.0 - min(1.0, memory_size / 1000.0)
    session_bonus = min(0.2, session_count * 0.02)

    efficiency = clamp((1.0 - queue_penalty) * 0.5 + memory_efficiency * 0.3 + session_bonus)

    # Weighted total
    total =
      stability * weights.stability +
        coherence * weights.coherence +
        adaptability * weights.adaptability +
        efficiency * weights.efficiency

    # Add novelty bonus for explorer profiles
    novelty_bonus = modifiers.novelty_bonus
    total = total + novelty_bonus * (1.0 - total)

    %{
      total: clamp(total),
      components: %{
        stability: stability,
        coherence: coherence,
        adaptability: adaptability,
        efficiency: efficiency
      }
    }
  end

  defp clamp(v), do: max(0.0, min(1.0, v))

  # ═══════════════════════════════════════════════════════════════
  # Trait Manipulation
  # ═══════════════════════════════════════════════════════════════

  defp suggest_via_tpe(tpe_bridge, current_traits) do
    case TPEBridge.suggest_params(tpe_bridge) do
      {:ok, suggested} ->
        # Map TPE suggestions to trait space
        Map.merge(current_traits, normalize_tpe_suggestions(suggested))

      {:error, _} ->
        # Fallback to random
        suggest_random(current_traits)
    end
  end

  defp suggest_random(current_traits) do
    # Apply small random mutations to each trait
    current_traits
    |> Enum.map(fn {key, value} ->
      bounds = Map.get(@trait_bounds, key, %{min: 0.0, max: 1.0, default: 0.5})
      mutation = (:rand.uniform() - 0.5) * 0.2
      new_value = clamp(value + mutation)
      new_value = max(bounds.min, min(bounds.max, new_value))
      {key, new_value}
    end)
    |> Enum.into(%{})
  end

  defp normalize_tpe_suggestions(suggested) do
    # Map TPE parameter names to trait names
    suggested
    |> Enum.map(fn
      {"lambda_modulation", v} -> {:lambda_sensitivity, v}
      {"bias", v} -> {:flow_stability, v}
      {"weight_decay", v} -> {:caution, 1.0 - v}
      {"gate_temp", v} -> {:adaptability, v}
      {k, v} when is_atom(k) -> {k, v}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
    |> Enum.into(%{})
  rescue
    _ -> %{}
  end

  defp mutate_traits(traits, mutation_rate) do
    traits
    |> Enum.map(fn {key, value} ->
      if :rand.uniform() < mutation_rate do
        bounds = Map.get(@trait_bounds, key, %{min: 0.0, max: 1.0, default: 0.5})
        # Gaussian-ish mutation
        mutation = (:rand.uniform() - 0.5) * 0.3
        new_value = clamp(value + mutation)
        new_value = max(bounds.min, min(bounds.max, new_value))
        {key, new_value}
      else
        {key, value}
      end
    end)
    |> Enum.into(%{})
  end

  defp default_traits do
    @trait_bounds
    |> Enum.map(fn {key, bounds} -> {key, bounds.default} end)
    |> Enum.into(%{})
  end

  @doc """
  Converts a traits map to a fixed-order trait vector.

  Trait order:
  0. aggression
  1. curiosity
  2. caution
  3. persistence
  4. adaptability
  5. sociability
  6. lambda_sensitivity
  7. entropy_tolerance
  8. phase_coherence
  9. flow_stability
  """
  @spec traits_to_vector(map()) :: [float()]
  def traits_to_vector(traits) do
    # Fixed order for trait_vector
    keys = [
      :aggression,
      :curiosity,
      :caution,
      :persistence,
      :adaptability,
      :sociability,
      :lambda_sensitivity,
      :entropy_tolerance,
      :phase_coherence,
      :flow_stability
    ]

    Enum.map(keys, fn key ->
      Map.get(traits, key, Map.get(@trait_bounds, key, %{default: 0.5}).default)
    end)
  end

  @doc """
  Converts a trait vector back to a traits map.
  """
  @spec vector_to_traits([float()] | nil) :: map()
  def vector_to_traits(vector) when is_list(vector) do
    keys = [
      :aggression,
      :curiosity,
      :caution,
      :persistence,
      :adaptability,
      :sociability,
      :lambda_sensitivity,
      :entropy_tolerance,
      :phase_coherence,
      :flow_stability
    ]

    keys
    |> Enum.zip(vector ++ List.duplicate(0.5, 10))
    |> Enum.take(length(keys))
    |> Enum.into(%{})
  end

  def vector_to_traits(_), do: default_traits()

  # ═══════════════════════════════════════════════════════════════
  # Event Emission
  # ═══════════════════════════════════════════════════════════════

  defp emit_evolution_event(event_type, pac_id, data) do
    event_name = "pac.evolution.#{event_type}"

    payload =
      Map.merge(data, %{
        pac_id: pac_id,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    case Event.new(name: event_name, source: :pac, payload: payload, meta: %{pipeline: :realtime}) do
      {:ok, event} ->
        EventBus.publish_event(event)

      {:error, reason} ->
        Logger.warning("[Thunderpac.Evolution] Failed to emit event: #{inspect(reason)}")
    end
  end
end
