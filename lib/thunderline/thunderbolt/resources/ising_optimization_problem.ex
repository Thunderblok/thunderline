defmodule Thunderline.Thunderbolt.Resources.IsingOptimizationProblem do
  @moduledoc """
  Represents an Ising optimization problem definition.

  Stores problem parameters, topology, and metadata for reproducible optimization.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Thunderline.Thunderbolt.Domain

  postgres do
    table "ising_optimization_problems"
    repo Thunderline.Repo
  end

  code_interface do
    define :create
    define :create_grid_problem
    define :create_max_cut_problem
    define :read
    define :update
    define :destroy
    define :list, action: :read
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_grid_problem do
      description "Create a grid-based Ising problem"

      argument :height, :integer, allow_nil?: false
      argument :width, :integer, allow_nil?: false
      argument :coupling_type, :atom, default: :uniform
      argument :coupling_strength, :float, default: 1.0

      change fn changeset, _context ->
        height = Ash.Changeset.get_argument(changeset, :height)
        width = Ash.Changeset.get_argument(changeset, :width)
        coupling_type = Ash.Changeset.get_argument(changeset, :coupling_type)
        coupling_strength = Ash.Changeset.get_argument(changeset, :coupling_strength)

        coupling_matrix =
          case coupling_type do
            :uniform ->
              %{type: :uniform, strength: coupling_strength}

            :anisotropic ->
              %{
                type: :anisotropic,
                horizontal: coupling_strength,
                vertical: coupling_strength * 0.5
              }

            _ ->
              %{type: :custom}
          end

        changeset
        |> Ash.Changeset.change_attribute(:topology, :grid_2d)
        |> Ash.Changeset.change_attribute(:dimensions, %{height: height, width: width})
        |> Ash.Changeset.change_attribute(:coupling_matrix, coupling_matrix)
        |> Ash.Changeset.change_attribute(:problem_type, :ising_model)
      end
    end

    create :create_max_cut_problem do
      description "Create a Max-Cut optimization problem"

      argument :num_vertices, :integer, allow_nil?: false
      argument :edges, {:array, :map}, allow_nil?: false

      change fn changeset, _context ->
        num_vertices = Ash.Changeset.get_argument(changeset, :num_vertices)
        edges = Ash.Changeset.get_argument(changeset, :edges)

        changeset
        |> Ash.Changeset.change_attribute(:topology, :graph)
        |> Ash.Changeset.change_attribute(:dimensions, %{vertices: num_vertices})
        |> Ash.Changeset.change_attribute(:edge_list, edges)
        |> Ash.Changeset.change_attribute(:problem_type, :max_cut)
        |> Ash.Changeset.change_attribute(:coupling_matrix, %{type: :from_edges})
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "Human-readable name for the problem"
      allow_nil? false
    end

    attribute :description, :string do
      description "Detailed description of the optimization problem"
    end

    attribute :topology, :atom do
      description "Problem topology: :grid_2d, :grid_3d, or :graph"
      constraints one_of: [:grid_2d, :grid_3d, :graph]
      allow_nil? false
    end

    attribute :dimensions, :map do
      description "Problem dimensions (e.g., %{height: 100, width: 100} for grid)"
      allow_nil? false
    end

    attribute :coupling_matrix, :map do
      description "Coupling parameters (J_ij values)"
    end

    attribute :field_config, :map do
      description "External field configuration (h_i values)"
    end

    attribute :boundary_conditions, :atom do
      description "Boundary conditions for grid problems"
      constraints one_of: [:periodic, :open, :fixed]
      default :periodic
    end

    attribute :problem_type, :atom do
      description "Type of optimization problem"
      constraints one_of: [:ising_model, :max_cut, :graph_coloring, :tsp, :custom]
      allow_nil? false
    end

    attribute :edge_list, {:array, :map} do
      description "Edge list for graph problems: [%{from: i, to: j, weight: w}, ...]"
    end

    attribute :metadata, :map do
      description "Additional problem-specific metadata"
      default %{}
    end

    attribute :tags, {:array, :string} do
      description "Tags for categorizing problems"
      default []
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :optimization_runs, Thunderline.Thunderbolt.Resources.IsingOptimizationRun do
      source_attribute :id
      destination_attribute :problem_id
    end
  end

  def to_lattice(problem) when is_struct(problem) do
    case problem.topology do
      :grid_2d ->
        %{height: height, width: width} = problem.dimensions

        coupling_opts =
          case problem.coupling_matrix do
            %{type: :uniform, strength: _s} ->
              [coupling: :uniform]

            %{type: :anisotropic, horizontal: h, vertical: v} ->
              [coupling: {:anisotropic, {h, v}}]

            _ ->
              [coupling: :uniform]
          end

        lattice_mod = Module.concat([Thunderline, ThunderIsing, Lattice])

        if Code.ensure_loaded?(lattice_mod) do
          apply(lattice_mod, :grid_2d, [height, width, coupling_opts])
        else
          {:error, :ising_unavailable}
        end

      :graph ->
        %{vertices: num_vertices} = problem.dimensions
        edges = problem.edge_list || []

        # Convert edge maps to tuples
        edge_tuples =
          Enum.map(edges, fn %{from: from, to: to, weight: weight} ->
            {from, to, weight}
          end)

        lattice_mod = Module.concat([Thunderline, ThunderIsing, Lattice])

        if Code.ensure_loaded?(lattice_mod) do
          apply(lattice_mod, :max_cut_problem, [edge_tuples, num_vertices])
        else
          {:error, :ising_unavailable}
        end
    end
  end
end
