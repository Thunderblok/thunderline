defmodule Thunderline.Thunderchief.Behaviour do
  @moduledoc """
  Contract for domain-level orchestrators (puppeteers).

  Each Thunderchief observes domain state, selects the next action,
  and reports outcomes for RL trajectory logging. This implements
  the "puppeteer" pattern from multi-agent collaboration research.

  ## Architecture

  ```
  Thunderchief → Per-domain orchestrator (puppeteer)
  Puppets     → Domain resources (Thunderbits, DAG nodes, policies)
  Action      → Serialized choice from action space
  Outcome     → Reward signal for RL optimization
  ```

  ## Lifecycle

  1. `observe_state/1` - Extract compressed observation vector
  2. `choose_action/1` - Select action via policy (heuristic or learned)
  3. `apply_action/2` - Execute action in domain context
  4. `report_outcome/1` - Log trajectory for Cerebros training

  ## Implementation Example

  ```elixir
  defmodule MyApp.Chiefs.ProcessorChief do
    @behaviour Thunderline.Thunderchief.Behaviour

    @impl true
    def observe_state(ctx) do
      %{
        queue_depth: length(ctx.pending),
        cpu_load: System.schedulers_online() / ctx.active_workers,
        memory_pressure: :erlang.memory(:total) / ctx.memory_limit
      }
    end

    @impl true
    def choose_action(state) do
      cond do
        state.queue_depth > 100 -> {:ok, :scale_up}
        state.cpu_load > 0.8 -> {:ok, :throttle}
        true -> {:ok, :maintain}
      end
    end

    @impl true
    def apply_action(:scale_up, ctx) do
      # Spawn more workers
      {:ok, %{ctx | workers: ctx.workers + 1}}
    end

    @impl true
    def report_outcome(ctx) do
      %{
        reward: calculate_throughput_reward(ctx),
        metrics: %{processed: ctx.processed_count},
        trajectory_step: build_step(ctx)
      }
    end
  end
  ```
  """

  @type state :: map()
  @type action :: atom() | {atom(), map()}
  @type outcome :: :success | :error | {:partial, map()}
  @type context :: map()

  @type trajectory_step :: %{
          state: state(),
          action: action(),
          next_state: state(),
          timestamp: DateTime.t()
        }

  @type outcome_report :: %{
          reward: float(),
          metrics: map(),
          trajectory_step: trajectory_step()
        }

  @doc """
  Extract compressed feature vector from domain state.

  The observation should capture domain-specific features that
  are relevant for action selection. Keep observations compact
  for efficient RL training.

  ## Parameters

  - `context` - Domain execution context with state and resources

  ## Returns

  Map of observable features with numeric or categorical values.
  """
  @callback observe_state(context()) :: state()

  @doc """
  Choose next action given observed state.

  This is the core "puppeteer" decision function. Initially
  implemented with heuristics, later replaceable with learned
  policies via Cerebros.

  ## Parameters

  - `state` - Observation from `observe_state/1`

  ## Returns

  - `{:ok, action}` - Action to execute immediately
  - `{:wait, timeout_ms}` - Wait for external stimulus
  - `{:defer, reason}` - Delegate to another chief
  """
  @callback choose_action(state()) ::
              {:ok, action()}
              | {:wait, non_neg_integer()}
              | {:defer, atom()}

  @doc """
  Apply selected action to domain context.

  Execute the action in the domain, modifying state as needed.
  Should be idempotent where possible for fault tolerance.

  ## Parameters

  - `action` - Action returned from `choose_action/1`
  - `context` - Domain execution context

  ## Returns

  - `{:ok, updated_context}` - Success with updated context
  - `{:error, reason}` - Action failed
  """
  @callback apply_action(action(), context()) ::
              {:ok, context()}
              | {:error, term()}

  @doc """
  Report outcome for RL trajectory logging.

  Called after action execution to record the transition
  for later Cerebros policy optimization.

  ## Parameters

  - `context` - Domain context after action execution

  ## Returns

  Map containing:
  - `reward` - Scalar reward signal for RL
  - `metrics` - Domain-specific metrics for monitoring
  - `trajectory_step` - (state, action, next_state) tuple for training
  """
  @callback report_outcome(context()) :: outcome_report()

  @doc """
  Optional: Return the action space for this chief.

  Used for policy initialization and validation.
  """
  @callback action_space() :: [action()]

  @optional_callbacks [action_space: 0]
end
