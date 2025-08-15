defmodule Thunderline.Thunderbolt.ThunderCell.CACell do
  @moduledoc """
  Individual CA cell process managing a single cellular automaton cell.
  Each cell operates independently with its own state and rules.
  """

  use GenServer
  require Logger

  defstruct [
    # {X, Y, Z} position in 3D grid
    :coordinate,
    # :alive or :dead
    :current_state,
    # Prepared state for next generation
    :next_state,
    # CA rules for evolution
    :ca_rules,
    # Last received neighbor states
    :neighbor_states,
    # Current generation number
    :generation,
    # Recent state history
    :state_history
  ]

  @max_history_size 10

  # ====================================================================
  # API functions
  # ====================================================================

  def start_link(coordinate, ca_rules) do
    GenServer.start_link(__MODULE__, {coordinate, ca_rules})
  end

  def get_state(cell_pid) do
    GenServer.call(cell_pid, :get_state)
  end

  def set_rules(cell_pid, new_rules) do
    GenServer.cast(cell_pid, {:set_rules, new_rules})
  end

  def prepare_evolution(cell_pid, neighbor_states) do
    GenServer.cast(cell_pid, {:prepare_evolution, neighbor_states})
  end

  def commit_evolution(cell_pid) do
    GenServer.cast(cell_pid, :commit_evolution)
  end

  def stop(cell_pid) do
    GenServer.stop(cell_pid)
  end

  # ====================================================================
  # GenServer callbacks
  # ====================================================================

  @impl true
  def init({coordinate, ca_rules}) do
    # Initialize cell with random state
    initial_state = if :rand.uniform() > 0.5, do: :alive, else: :dead

    state = %__MODULE__{
      coordinate: coordinate,
      current_state: initial_state,
      next_state: initial_state,
      ca_rules: ca_rules,
      neighbor_states: [],
      generation: 0,
      state_history: [initial_state]
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    cell_state = %{
      coordinate: state.coordinate,
      current_state: state.current_state,
      generation: state.generation,
      ca_rules: state.ca_rules
    }

    {:reply, {:ok, cell_state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast({:set_rules, new_rules}, state) do
    {:noreply, %{state | ca_rules: new_rules}}
  end

  def handle_cast({:prepare_evolution, neighbor_states}, state) do
    # Calculate next state based on CA rules and neighbor states
    next_state = calculate_next_state(state.current_state, neighbor_states, state.ca_rules)
    updated_state = %{state | neighbor_states: neighbor_states, next_state: next_state}
    {:noreply, updated_state}
  end

  def handle_cast(:commit_evolution, state) do
    # Transition to the prepared next state
    new_generation = state.generation + 1
    new_history = update_state_history(state.state_history, state.next_state)

    updated_state = %{
      state
      | current_state: state.next_state,
        generation: new_generation,
        state_history: new_history
    }

    {:noreply, updated_state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # ====================================================================
  # Internal functions
  # ====================================================================

  defp calculate_next_state(current_state, neighbor_states, ca_rules) do
    alive_neighbors = count_alive_neighbors(neighbor_states)
    birth_neighbors = Map.get(ca_rules, :birth_neighbors, [5, 6, 7])
    survival_neighbors = Map.get(ca_rules, :survival_neighbors, [4, 5, 6])

    case current_state do
      :dead ->
        # Dead cell becomes alive if it has the right number of alive neighbors
        if alive_neighbors in birth_neighbors do
          :alive
        else
          :dead
        end

      :alive ->
        # Living cell survives if it has the right number of alive neighbors
        if alive_neighbors in survival_neighbors do
          :alive
        else
          :dead
        end
    end
  end

  defp count_alive_neighbors(neighbor_states) do
    Enum.count(neighbor_states, fn
      :alive -> true
      %{current_state: :alive} -> true
      _ -> false
    end)
  end

  defp update_state_history(history, new_state) do
    new_history = [new_state | history]
    Enum.take(new_history, @max_history_size)
  end
end
