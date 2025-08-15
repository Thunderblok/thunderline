defmodule Thunderline.Thundercrown.Introspection.SupervisionTreeMapper do
  @moduledoc """
  Maps the Elixir supervision tree to an ExRoseTree structure for visualization
  and analysis purposes.

  This module provides functionality to:
  - Extract the current supervision tree structure
  - Map it to a RoseTree representation
  - Provide utilities for traversal and analysis
  """

  alias ExRoseTree

  @doc """
  Maps the entire supervision tree starting from the main application supervisor
  to an ExRoseTree structure.

  ## Examples

      iex> tree = Thunderline.Thundercrown.Introspection.SupervisionTreeMapper.map_supervision_tree()
      iex> ExRoseTree.get_term(tree)
      {Thunderline.Supervisor, :supervisor, [:one_for_one]}

  """
  @spec map_supervision_tree() :: ExRoseTree.t()
  def map_supervision_tree do
    case Process.whereis(Thunderline.Supervisor) do
      nil ->
        ExRoseTree.new({:error, :supervisor_not_found})

      pid ->
        supervisor_info = get_supervisor_info(pid)
        map_supervisor_to_tree(supervisor_info)
    end
  end

  @doc """
  Maps a specific supervisor PID to an ExRoseTree structure.

  ## Parameters
  - `supervisor_pid`: The PID of the supervisor to map

  ## Returns
  An ExRoseTree where:
  - The term contains supervisor metadata: `{name, type, strategy}`
  - Children are the supervised processes/supervisors
  """
  @spec map_supervisor_to_tree(pid() | {atom(), any(), any()}) :: ExRoseTree.t()
  def map_supervisor_to_tree(supervisor_pid) when is_pid(supervisor_pid) do
    supervisor_info = get_supervisor_info(supervisor_pid)
    map_supervisor_to_tree(supervisor_info)
  end

  def map_supervisor_to_tree({name, strategy, children_info}) do
    children_trees =
      children_info
      |> Enum.map(&map_child_to_tree/1)

    ExRoseTree.new({name, :supervisor, strategy}, children_trees)
  end

  @doc """
  Maps an individual child process to an ExRoseTree structure.
  """
  @spec map_child_to_tree({atom(), pid() | :undefined, atom(), list()}) :: ExRoseTree.t()
  def map_child_to_tree({id, pid, type, modules}) when is_pid(pid) do
    case type do
      :supervisor ->
        # Recursively map supervisor children
        supervisor_info = get_supervisor_info(pid)
        map_supervisor_to_tree(supervisor_info)

      _ ->
        # Regular worker process
        process_info = get_process_info(pid)
        ExRoseTree.new({id, type, process_info})
    end
  end

  def map_child_to_tree({id, :undefined, type, modules}) do
    # Process not running
    ExRoseTree.new({id, type, {:not_running, modules}})
  end

  @doc """
  Retrieves detailed information about a supervisor.
  """
  @spec get_supervisor_info(pid()) :: {atom(), any(), list()}
  def get_supervisor_info(supervisor_pid) when is_pid(supervisor_pid) do
    try do
      case Supervisor.which_children(supervisor_pid) do
        children when is_list(children) ->
          # Try to get the supervisor's registered name
          name =
            case Process.info(supervisor_pid, :registered_name) do
              {:registered_name, []} -> :unnamed_supervisor
              {:registered_name, [registered_name]} -> registered_name
              _ -> :unnamed_supervisor
            end

          # Get basic supervisor strategy info safely
          strategy =
            try do
              # Check if this looks like a DynamicSupervisor by examining the state
              case :sys.get_state(supervisor_pid) do
                %DynamicSupervisor{strategy: strategy} -> strategy
                {state, _} when is_map(state) -> Map.get(state, :strategy, :one_for_one)
                _ -> :one_for_one
              end
            rescue
              _ -> :basic_supervisor
            end

          {name, strategy, children}

        error ->
          {supervisor_pid, :error, [error]}
      end
    rescue
      error ->
        {supervisor_pid, :error, [error]}
    end
  end

  @doc """
  Retrieves detailed information about a process.
  """
  @spec get_process_info(pid()) :: map()
  def get_process_info(pid) when is_pid(pid) do
    try do
      info =
        Process.info(pid, [
          :registered_name,
          :current_function,
          :initial_call,
          :message_queue_len,
          :status,
          :memory,
          :reductions
        ])

      case info do
        nil ->
          %{status: :dead}

        process_info ->
          process_info
          |> Enum.into(%{})
          |> Map.put(:pid, pid)
      end
    rescue
      _ ->
        %{status: :error, pid: pid}
    end
  end

  @doc """
  Prints a human-readable representation of the supervision tree.
  """
  @spec print_supervision_tree(ExRoseTree.t(), integer()) :: :ok
  def print_supervision_tree(tree, indent \\ 0) do
    padding = String.duplicate("  ", indent)

    case ExRoseTree.get_term(tree) do
      {name, :supervisor, strategy} ->
        IO.puts("#{padding}📦 #{name} (supervisor: #{inspect(strategy)})")

      {name, type, info} ->
        IO.puts("#{padding}⚡ #{name} (#{type}: #{format_process_info(info)})")

      other ->
        IO.puts("#{padding}❓ #{inspect(other)}")
    end

    tree
    |> ExRoseTree.get_children()
    |> Enum.each(&print_supervision_tree(&1, indent + 1))

    :ok
  end

  @doc """
  Analyzes the supervision tree and returns statistics.
  """
  @spec analyze_supervision_tree(ExRoseTree.t()) :: map()
  def analyze_supervision_tree(tree) do
    stats = %{
      total_processes: 0,
      supervisors: 0,
      workers: 0,
      running: 0,
      not_running: 0,
      domains: %{}
    }

    tree
    |> traverse_and_count(stats)
  end

  @doc """
  Finds all processes in the supervision tree that match a given pattern.
  """
  @spec find_processes(ExRoseTree.t(), (ExRoseTree.t() -> boolean())) :: [ExRoseTree.t()]
  def find_processes(tree, predicate) when is_function(predicate, 1) do
    tree
    |> Enum.filter(predicate)
  end

  @doc """
  Extracts all Thunder domain services from the supervision tree.
  """
  @spec extract_thunder_domains(ExRoseTree.t()) :: map()
  def extract_thunder_domains(tree) do
    domains = %{
      thunderbolt: [],
      thunderflow: [],
      thundergate: [],
      thunderblock: [],
      thunderlink: [],
      thundercrown: [],
      thunderguard: [],
      thundergrid: []
    }

    tree
    |> find_processes(fn process_tree ->
      case ExRoseTree.get_term(process_tree) do
        {name, _, _} when is_atom(name) ->
          name_str = Atom.to_string(name) |> String.downcase()
          String.contains?(name_str, "thunder")

        _ ->
          false
      end
    end)
    |> Enum.reduce(domains, fn process_tree, acc ->
      case ExRoseTree.get_term(process_tree) do
        {name, _, _} ->
          name_str = Atom.to_string(name) |> String.downcase()

          cond do
            String.contains?(name_str, "thunderbolt") ->
              Map.update!(acc, :thunderbolt, &[process_tree | &1])

            String.contains?(name_str, "thunderflow") ->
              Map.update!(acc, :thunderflow, &[process_tree | &1])

            String.contains?(name_str, "thundergate") ->
              Map.update!(acc, :thundergate, &[process_tree | &1])

            String.contains?(name_str, "thunderblock") ->
              Map.update!(acc, :thunderblock, &[process_tree | &1])

            String.contains?(name_str, "thunderlink") ->
              Map.update!(acc, :thunderlink, &[process_tree | &1])

            String.contains?(name_str, "thundercrown") ->
              Map.update!(acc, :thundercrown, &[process_tree | &1])

            String.contains?(name_str, "thunderguard") ->
              Map.update!(acc, :thunderguard, &[process_tree | &1])

            String.contains?(name_str, "thundergrid") ->
              Map.update!(acc, :thundergrid, &[process_tree | &1])

            true ->
              acc
          end

        _ ->
          acc
      end
    end)
  end

  # Private helper functions

  defp traverse_and_count(tree, stats) do
    updated_stats =
      case ExRoseTree.get_term(tree) do
        {_name, :supervisor, _} ->
          stats
          |> Map.update!(:total_processes, &(&1 + 1))
          |> Map.update!(:supervisors, &(&1 + 1))

        {_name, _, {:not_running, _}} ->
          stats
          |> Map.update!(:total_processes, &(&1 + 1))
          |> Map.update!(:workers, &(&1 + 1))
          |> Map.update!(:not_running, &(&1 + 1))

        {_name, _, _} ->
          stats
          |> Map.update!(:total_processes, &(&1 + 1))
          |> Map.update!(:workers, &(&1 + 1))
          |> Map.update!(:running, &(&1 + 1))

        _ ->
          stats
      end

    tree
    |> ExRoseTree.get_children()
    |> Enum.reduce(updated_stats, &traverse_and_count/2)
  end

  defp format_process_info(%{status: status, pid: pid}) do
    "#{status} [#{inspect(pid)}]"
  end

  defp format_process_info({:not_running, modules}) do
    "not_running [#{inspect(modules)}]"
  end

  defp format_process_info(info) when is_map(info) do
    status = Map.get(info, :status, :unknown)
    pid = Map.get(info, :pid, :unknown)
    "#{status} [#{inspect(pid)}]"
  end

  defp format_process_info(info) do
    inspect(info)
  end
end
