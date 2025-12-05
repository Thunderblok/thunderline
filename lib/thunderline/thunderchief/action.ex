defmodule Thunderline.Thunderchief.Action do
  @moduledoc """
  Chief action types and utilities.

  Provides a standardized action representation for domain orchestrators.
  Actions are the outputs of chief policy decisions that get applied
  to domain contexts.

  ## Action Types

  - **Simple**: Atom-only actions (`:wait`, `:maintain`, `:consolidate`)
  - **Parameterized**: Tuple actions with params (`{:activate, %{id: id}}`)
  - **Compound**: Multi-step action sequences

  ## Categories

  Actions are categorized for logging and analysis:

  - `:resource` - Resource allocation (scale up/down)
  - `:control` - Flow control (throttle, pause, resume)
  - `:transition` - State transitions (activate, deactivate)
  - `:maintenance` - Housekeeping (consolidate, gc)
  - `:observation` - Passive actions (wait, defer)

  ## Usage

  ```elixir
  # Create action
  action = Action.new(:activate, %{target: "bit-123"})

  # Validate action
  {:ok, action} = Action.validate(action, valid_actions)

  # Log action
  Action.log(action, :executed, %{duration_ms: 42})
  ```
  """

  alias __MODULE__
  alias Thunderline.Thunderflow.EventBus

  @type category :: :resource | :control | :transition | :maintenance | :observation
  @type status :: :pending | :executing | :completed | :failed | :cancelled

  @type t :: %Action{
          id: String.t(),
          type: atom(),
          params: map(),
          category: category(),
          status: status(),
          created_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :id,
    :type,
    :created_at,
    params: %{},
    category: :control,
    status: :pending,
    metadata: %{}
  ]

  # Action category mappings
  @categories %{
    # Resource actions
    scale_up: :resource,
    scale_down: :resource,
    allocate: :resource,
    deallocate: :resource,

    # Control actions
    throttle: :control,
    pause: :control,
    resume: :control,
    reset: :control,

    # Transition actions
    activate: :transition,
    deactivate: :transition,
    transition: :transition,
    initialize: :transition,

    # Maintenance actions
    consolidate: :maintenance,
    gc: :maintenance,
    cleanup: :maintenance,
    checkpoint: :maintenance,

    # Observation actions
    wait: :observation,
    defer: :observation,
    maintain: :observation,
    observe: :observation
  }

  @doc """
  Create a new action.

  ## Parameters

  - `type` - Action type atom
  - `params` - Optional parameters map
  - `opts` - Additional options:
    - `:category` - Override auto-detected category
    - `:metadata` - Additional tracking info

  ## Examples

      iex> Action.new(:activate)
      %Action{type: :activate, category: :transition, ...}

      iex> Action.new(:scale_up, %{count: 2})
      %Action{type: :scale_up, params: %{count: 2}, category: :resource, ...}
  """
  @spec new(atom(), map(), keyword()) :: t()
  def new(type, params \\ %{}, opts \\ []) do
    %Action{
      id: Thunderline.UUID.v7(),
      type: type,
      params: params,
      category: Keyword.get(opts, :category, infer_category(type)),
      status: :pending,
      created_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create action from tuple format.

  Converts `{:action, params}` or `:action` to Action struct.
  """
  @spec from_tuple(atom() | {atom(), map()}) :: t()
  def from_tuple(action_tuple)
  def from_tuple({type, params}) when is_atom(type) and is_map(params), do: new(type, params)
  def from_tuple(type) when is_atom(type), do: new(type)

  @doc """
  Convert action back to tuple format.
  """
  @spec to_tuple(t()) :: atom() | {atom(), map()}
  def to_tuple(%Action{type: type, params: params}) when map_size(params) == 0, do: type
  def to_tuple(%Action{type: type, params: params}), do: {type, params}

  @doc """
  Validate action against allowed action space.

  ## Parameters

  - `action` - Action to validate
  - `allowed` - List of allowed action types

  ## Returns

  - `{:ok, action}` if valid
  - `{:error, reason}` if invalid
  """
  @spec validate(t(), [atom()]) :: {:ok, t()} | {:error, term()}
  def validate(%Action{type: type} = action, allowed) when is_list(allowed) do
    if type in allowed do
      {:ok, action}
    else
      {:error, {:invalid_action, type, allowed}}
    end
  end

  @doc """
  Update action status.
  """
  @spec update_status(t(), status(), map()) :: t()
  def update_status(%Action{} = action, status, additional_meta \\ %{}) do
    %{action | status: status, metadata: Map.merge(action.metadata, additional_meta)}
  end

  @doc """
  Mark action as executing.
  """
  @spec mark_executing(t()) :: t()
  def mark_executing(%Action{} = action) do
    update_status(action, :executing, %{started_at: DateTime.utc_now()})
  end

  @doc """
  Mark action as completed.
  """
  @spec mark_completed(t(), map()) :: t()
  def mark_completed(%Action{} = action, result \\ %{}) do
    update_status(action, :completed, %{
      completed_at: DateTime.utc_now(),
      result: result
    })
  end

  @doc """
  Mark action as failed.
  """
  @spec mark_failed(t(), term()) :: t()
  def mark_failed(%Action{} = action, reason) do
    update_status(action, :failed, %{
      failed_at: DateTime.utc_now(),
      error: inspect(reason)
    })
  end

  @doc """
  Log action event to EventBus.
  """
  @spec log(t(), atom(), map()) :: :ok | {:error, term()}
  def log(%Action{} = action, event_type, details \\ %{}) do
    case EventBus.publish_event(%{
           name: "chief.action.#{event_type}",
           source: :thunderchief,
           payload: %{
             action_id: action.id,
             action_type: action.type,
             category: action.category,
             status: action.status,
             params: action.params,
             details: details
           }
         }) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Check if action is a wait/observation action.
  """
  @spec wait_action?(t()) :: boolean()
  def wait_action?(%Action{category: :observation}), do: true
  def wait_action?(_), do: false

  @doc """
  Check if action modifies state.
  """
  @spec mutating?(t()) :: boolean()
  def mutating?(%Action{category: cat}) when cat in [:observation], do: false
  def mutating?(_), do: true

  @doc """
  Get action duration if completed.
  """
  @spec duration_ms(t()) :: non_neg_integer() | nil
  def duration_ms(%Action{metadata: meta}) do
    with %{started_at: started, completed_at: completed} <- meta do
      DateTime.diff(completed, started, :millisecond)
    else
      _ -> nil
    end
  end

  @doc """
  Compare actions by creation time.
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%Action{created_at: t1}, %Action{created_at: t2}) do
    DateTime.compare(t1, t2)
  end

  # Private helpers

  defp infer_category(type) do
    Map.get(@categories, type, :control)
  end
end
