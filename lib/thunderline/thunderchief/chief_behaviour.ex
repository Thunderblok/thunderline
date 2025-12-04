defmodule Thunderline.Thunderchief.ChiefBehaviour do
  @moduledoc """
  Extended Chief behaviour with plan tree capabilities.

  This behaviour extends the original `Thunderline.Thunderchief.Behaviour` with
  support for hierarchical plan trees, node expansion, and step execution.

  ## Chief Responsibilities

  A Chief is the domain-level orchestrator (puppeteer) responsible for:

  1. **Observation** - Reading current domain state
  2. **Planning** - Choosing actions and expanding plan nodes
  3. **Execution** - Performing discrete steps
  4. **Reporting** - Emitting outcomes and telemetry

  ## Plan Tree Integration

  Chiefs that support plan trees implement additional callbacks:

  - `plan_capabilities/0` - Returns list of supported action types
  - `expand_node/3` - Expands abstract nodes into concrete children
  - `perform_step/3` - Executes a single leaf node

  ## Example

      defmodule MyApp.MyChief do
        @behaviour Thunderline.Thunderchief.ChiefBehaviour

        @impl true
        def observe_state(context), do: {:ok, current_state}

        @impl true
        def choose_action(observed_state), do: {:ok, :advance}

        @impl true
        def apply_action(action, context), do: {:ok, result}

        @impl true
        def report_outcome(result), do: :ok

        @impl true
        def plan_capabilities do
          [
            %{action: :fetch_data, domain: :thunderblock},
            %{action: :transform, domain: :thundervine}
          ]
        end

        @impl true
        def expand_node(node_id, node_value, context) do
          {:ok, [
            {make_id(), %{action: :step1}},
            {make_id(), %{action: :step2}}
          ]}
        end

        @impl true
        def perform_step(node_id, node_value, context) do
          {:ok, %{status: :succeeded, output: result}}
        end
      end

  ## Action Space

  The `action_space/0` callback returns the discrete set of actions a Chief
  can select from during `choose_action/1`. This is used for:

  - RL agent training (mapping actions to indices)
  - Validation of chosen actions
  - Documentation/introspection

  ## Domain Integration

  Each Chief is associated with a domain (e.g., `:thundervine`, `:thunderblock`).
  The `DomainProcessor` Oban worker routes work to the appropriate Chief based
  on domain assignment.
  """

  @typedoc "Unique identifier for a plan node"
  @type node_id :: binary()

  @typedoc "Node payload containing action and metadata"
  @type node_value :: map()

  @typedoc "Execution context with PAC, tick info, etc."
  @type context :: map()

  @typedoc "Observed state from domain"
  @type observed_state :: map()

  @typedoc "Action chosen by the Chief"
  @type action :: atom() | {atom(), map()}

  @typedoc "Result of action application"
  @type action_result :: map()

  @typedoc "Step execution result"
  @type step_result :: %{
          required(:status) => :succeeded | :failed | :skipped,
          optional(:output) => term(),
          optional(:error) => term(),
          optional(:metadata) => map()
        }

  @typedoc "Action capability descriptor"
  @type capability :: %{
          required(:action) => atom(),
          required(:domain) => atom(),
          optional(:description) => String.t(),
          optional(:params) => map()
        }

  # ============================================================================
  # Core Callbacks (from original Behaviour)
  # ============================================================================

  @doc """
  Observes the current state of the domain.

  Called at the beginning of each tick cycle to gather information about
  the domain's current state. The returned state is passed to `choose_action/1`.

  ## Parameters

  - `context` - Execution context containing PAC info, tick number, etc.

  ## Returns

  - `{:ok, observed_state}` - Successfully observed state
  - `{:error, reason}` - Failed to observe state
  """
  @callback observe_state(context()) :: {:ok, observed_state()} | {:error, term()}

  @doc """
  Chooses an action based on observed state.

  Uses the observed state to select the next action to take. This may use
  heuristics, ML models, or deterministic logic.

  ## Parameters

  - `observed_state` - State returned from `observe_state/1`

  ## Returns

  - `{:ok, action}` - Selected action (atom or {action, params} tuple)
  - `{:error, reason}` - Failed to choose action
  """
  @callback choose_action(observed_state()) :: {:ok, action()} | {:error, term()}

  @doc """
  Applies the chosen action to the domain.

  Executes the action, potentially modifying domain state.

  ## Parameters

  - `action` - Action to apply
  - `context` - Execution context

  ## Returns

  - `{:ok, result}` - Action completed successfully
  - `{:error, reason}` - Action failed
  """
  @callback apply_action(action(), context()) :: {:ok, action_result()} | {:error, term()}

  @doc """
  Reports the outcome of the action.

  Called after action completion to emit telemetry, events, and logs.
  This is where reward signals are computed and emitted.

  ## Parameters

  - `result` - Result from `apply_action/2`

  ## Returns

  - `:ok` - Outcome reported successfully
  - `{:error, reason}` - Failed to report
  """
  @callback report_outcome(action_result()) :: :ok | {:error, term()}

  # ============================================================================
  # Optional Core Callbacks
  # ============================================================================

  @doc """
  Returns the action space (set of possible actions).

  Used for RL integration and validation. Default returns empty list.
  """
  @callback action_space() :: [atom()]

  # ============================================================================
  # Plan Tree Callbacks
  # ============================================================================

  @doc """
  Returns the list of plan capabilities this Chief supports.

  Each capability describes an action type the Chief can execute,
  along with metadata about domain, parameters, etc.

  ## Returns

  List of capability maps, each with at least `:action` and `:domain` keys.

  ## Example

      def plan_capabilities do
        [
          %{action: :fetch_data, domain: :thunderblock, description: "Fetch from Block"},
          %{action: :transform, domain: :thundervine, params: %{batch_size: {:integer, 100}}}
        ]
      end
  """
  @callback plan_capabilities() :: [capability()]

  @doc """
  Expands a plan node into child nodes.

  Called when a non-leaf node needs to be expanded into concrete steps.
  This is used for hierarchical planning where abstract goals are
  decomposed into actionable tasks.

  ## Parameters

  - `node_id` - ID of the node being expanded
  - `node_value` - Current node payload
  - `context` - Execution context

  ## Returns

  - `{:ok, children}` - List of `{child_id, child_value}` tuples
  - `{:skip, reason}` - Skip expansion (node becomes leaf)
  - `{:error, reason}` - Expansion failed
  """
  @callback expand_node(node_id(), node_value(), context()) ::
              {:ok, [{node_id(), node_value()}]}
              | {:skip, term()}
              | {:error, term()}

  @doc """
  Executes a single leaf node step.

  Called when a leaf node is ready for execution. This performs
  the actual work described by the node's value.

  ## Parameters

  - `node_id` - ID of the executing node
  - `node_value` - Node payload with action details
  - `context` - Execution context

  ## Returns

  - `{:ok, step_result}` - Step completed with status and optional output
  - `{:error, reason}` - Step failed
  """
  @callback perform_step(node_id(), node_value(), context()) ::
              {:ok, step_result()}
              | {:error, term()}

  @doc """
  Estimates the cost/reward of executing a node.

  Used by the scheduler to prioritize node execution.
  Higher values indicate more valuable/urgent nodes.

  ## Parameters

  - `node_value` - Node payload

  ## Returns

  Numeric priority value (default 0.5)
  """
  @callback estimate_priority(node_value()) :: float()

  # ============================================================================
  # Optional Callbacks with Defaults
  # ============================================================================

  @optional_callbacks [
    action_space: 0,
    plan_capabilities: 0,
    expand_node: 3,
    perform_step: 3,
    estimate_priority: 1
  ]

  # ============================================================================
  # Default Implementations
  # ============================================================================

  @doc """
  Provides default implementations for optional callbacks.

  Use this in your Chief module:

      use Thunderline.Thunderchief.ChiefBehaviour

  This adds default implementations that can be overridden.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Thunderline.Thunderchief.ChiefBehaviour

      @impl true
      def action_space, do: []

      @impl true
      def plan_capabilities, do: []

      @impl true
      def expand_node(_node_id, _node_value, _context), do: {:skip, :not_expandable}

      @impl true
      def perform_step(_node_id, _node_value, _context), do: {:error, :not_implemented}

      @impl true
      def estimate_priority(_node_value), do: 0.5

      defoverridable action_space: 0,
                     plan_capabilities: 0,
                     expand_node: 3,
                     perform_step: 3,
                     estimate_priority: 1
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Checks if a module implements the full plan tree interface.
  """
  @spec supports_plans?(module()) :: boolean()
  def supports_plans?(module) do
    function_exported?(module, :plan_capabilities, 0) and
      function_exported?(module, :expand_node, 3) and
      function_exported?(module, :perform_step, 3)
  end

  @doc """
  Checks if a module implements the core Chief interface.
  """
  @spec valid_chief?(module()) :: boolean()
  def valid_chief?(module) do
    function_exported?(module, :observe_state, 1) and
      function_exported?(module, :choose_action, 1) and
      function_exported?(module, :apply_action, 2) and
      function_exported?(module, :report_outcome, 1)
  end

  @doc """
  Returns capabilities for a Chief module, with defaults.
  """
  @spec get_capabilities(module()) :: [capability()]
  def get_capabilities(module) do
    if function_exported?(module, :plan_capabilities, 0) do
      module.plan_capabilities()
    else
      []
    end
  end
end
