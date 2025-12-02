defmodule Thunderline.Evolution.Resources.EliteEntry do
  @moduledoc """
  Ash resource for MAP-Elites archive entries (HC-Δ-4).

  Each elite entry represents the best-performing agent for a specific
  behavioral niche (cell) in the MAP-Elites archive.

  ## Archive Structure

  The archive is a sparse N-dimensional grid where:
  - Each dimension corresponds to a behavior descriptor
  - Each cell stores at most one elite (the best for that niche)
  - Cells are keyed by their grid coordinates

  ## Fields

  - `cell_key` - Unique identifier for the grid cell
  - `behavior_coords` - Grid coordinates as a map
  - `behavior_values` - Normalized behavior descriptor values
  - `fitness` - Objective fitness score
  - `pac_snapshot` - Serialized PAC configuration at this point
  - `trait_vector` - PAC traits that produced this behavior
  - `generation` - Which generation this elite was discovered

  ## Lifecycle

  Elites are only replaced when a new candidate has:
  1. The same cell_key (same behavioral niche)
  2. Higher fitness score

  This ensures quality-diversity: we maintain diverse behaviors while
  also maximizing performance within each niche.
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Evolution.Domain,
    data_layer: AshPostgres.DataLayer

  require Logger

  postgres do
    table "evolution_elite_entries"
    repo Thunderline.Repo

    references do
      reference :pac, on_delete: :nilify, on_update: :update
    end

    custom_indexes do
      index [:cell_key], unique: true, name: "elite_entries_cell_key_idx"
      index [:fitness], name: "elite_entries_fitness_idx"
      index [:generation], name: "elite_entries_generation_idx"
      index [:pac_id], name: "elite_entries_pac_idx"
      index [:archive_id], name: "elite_entries_archive_idx"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :create
    define :update_elite, args: [:fitness, :pac_snapshot, :trait_vector]
    define :get_by_cell, args: [:cell_key]
    define :archive_elites, args: [:archive_id]
    define :top_elites, args: [{:optional, :limit}]
    define :coverage_stats, action: :coverage_stats
    define :behavior_distribution, action: :behavior_distribution
    define :prune_old_generations, args: [:keep_generations]
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new elite entry in the archive"

      accept [
        :archive_id,
        :cell_key,
        :behavior_coords,
        :behavior_values,
        :fitness,
        :pac_id,
        :pac_snapshot,
        :trait_vector,
        :generation,
        :discovery_metrics,
        :metadata
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:discovered_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:last_challenged_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:challenge_count, 0)
        |> Ash.Changeset.change_attribute(:defended_count, 0)
      end

      change after_action(fn _changeset, entry, _context ->
               emit_elite_event(entry, :discovered)
               {:ok, entry}
             end)
    end

    update :update_elite do
      description "Update an elite entry when a better candidate is found"
      accept []
      require_atomic? false

      argument :fitness, :float, allow_nil?: false
      argument :pac_snapshot, :map, allow_nil?: false
      argument :trait_vector, {:array, :float}, allow_nil?: false

      change fn changeset, context ->
        old_fitness = Ash.Changeset.get_attribute(changeset, :fitness)
        new_fitness = context.arguments.fitness

        if new_fitness > old_fitness do
          changeset
          |> Ash.Changeset.change_attribute(:fitness, new_fitness)
          |> Ash.Changeset.change_attribute(:pac_snapshot, context.arguments.pac_snapshot)
          |> Ash.Changeset.change_attribute(:trait_vector, context.arguments.trait_vector)
          |> Ash.Changeset.change_attribute(:previous_fitness, old_fitness)
          |> Ash.Changeset.change_attribute(:last_improved_at, DateTime.utc_now())
          |> increment_generation()
        else
          changeset
          |> Ash.Changeset.change_attribute(:last_challenged_at, DateTime.utc_now())
          |> increment_challenge_count()
          |> increment_defended_count()
        end
      end

      change after_action(fn changeset, entry, context ->
               old_fitness = Ash.Changeset.get_data(changeset, :fitness)

               if context.arguments.fitness > old_fitness do
                 emit_elite_event(entry, :replaced, %{
                   old_fitness: old_fitness,
                   new_fitness: entry.fitness
                 })
               else
                 emit_elite_event(entry, :defended)
               end

               {:ok, entry}
             end)
    end

    read :get_by_cell do
      description "Get elite entry by cell key"
      argument :cell_key, :string, allow_nil?: false
      get? true
      filter expr(cell_key == ^arg(:cell_key))
    end

    read :archive_elites do
      description "Get all elites for an archive"
      argument :archive_id, :uuid, allow_nil?: false
      filter expr(archive_id == ^arg(:archive_id))
      prepare build(sort: [fitness: :desc])
    end

    read :top_elites do
      description "Get top elites by fitness"
      argument :limit, :integer, default: 10
      prepare build(sort: [fitness: :desc])

      prepare fn query, context ->
        limit = context.arguments.limit || 10
        Ash.Query.limit(query, limit)
      end
    end

    read :coverage_stats do
      description "Get archive coverage statistics"

      prepare fn query, _context ->
        # This will be aggregated at the caller level
        Ash.Query.select(query, [:cell_key, :fitness, :behavior_coords, :generation])
      end
    end

    read :behavior_distribution do
      description "Get behavior value distribution across archive"

      prepare fn query, _context ->
        Ash.Query.select(query, [:behavior_values, :fitness])
      end
    end

    action :prune_old_generations do
      description "Remove entries from generations older than threshold"
      argument :keep_generations, :integer, allow_nil?: false

      run fn input, _context ->
        threshold = input.arguments.keep_generations

        # Use a bulk destroy with filter
        __MODULE__
        |> Ash.Query.filter(expr(generation < ^threshold))
        |> Ash.bulk_destroy(:destroy, %{}, return_errors?: true)
        |> case do
          %{status: :success, records: records} ->
            {:ok, %{pruned_count: length(records)}}

          %{errors: errors} ->
            {:error, errors}
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :archive_id, :uuid do
      allow_nil? false
      public? true
      description "Parent archive this entry belongs to"
    end

    attribute :cell_key, :string do
      allow_nil? false
      public? true
      description "Unique cell identifier (grid coordinates as string)"
    end

    attribute :behavior_coords, :map do
      allow_nil? false
      public? true
      description "Grid coordinates for each behavior dimension"
    end

    attribute :behavior_values, :map do
      allow_nil? false
      public? true
      description "Normalized behavior values (0.0-1.0)"
    end

    attribute :fitness, :float do
      allow_nil? false
      public? true
      description "Objective fitness score"
    end

    attribute :previous_fitness, :float do
      allow_nil? true
      public? true
      description "Previous fitness before last update"
    end

    attribute :pac_snapshot, :map do
      allow_nil? false
      public? true
      description "Serialized PAC configuration"
    end

    attribute :trait_vector, {:array, :float} do
      allow_nil? false
      default []
      public? true
      description "PAC trait vector that produced this behavior"
    end

    attribute :generation, :integer do
      allow_nil? false
      default 0
      public? true
      description "Generation when this elite was discovered/updated"
    end

    attribute :challenge_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Number of times this cell was challenged"
    end

    attribute :defended_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Number of times the elite defended its position"
    end

    attribute :discovery_metrics, :map do
      allow_nil? false
      default %{}
      public? true
      description "Metrics from the evaluation that discovered this elite"
    end

    attribute :discovered_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When this cell was first occupied"
    end

    attribute :last_improved_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When fitness was last improved"
    end

    attribute :last_challenged_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When this cell was last challenged"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
      description "Additional metadata"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # RELATIONSHIPS
  # ═══════════════════════════════════════════════════════════════

  relationships do
    belongs_to :pac, Thunderline.Thunderpac.Resources.PAC do
      allow_nil? true
      public? true
      attribute_writable? true
      description "Source PAC that produced this elite"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # IDENTITIES
  # ═══════════════════════════════════════════════════════════════

  identities do
    identity :unique_cell, [:archive_id, :cell_key]
  end

  # ═══════════════════════════════════════════════════════════════
  # CALCULATIONS
  # ═══════════════════════════════════════════════════════════════

  calculations do
    calculate :defense_rate, :float do
      description "Ratio of successful defenses to challenges"

      calculation fn records, _context ->
        Enum.map(records, fn record ->
          if record.challenge_count > 0 do
            record.defended_count / record.challenge_count
          else
            1.0
          end
        end)
      end
    end

    calculate :age_generations, :integer do
      description "Number of generations since discovery"
      argument :current_generation, :integer, allow_nil?: false

      calculation fn records, context ->
        current = context.arguments.current_generation

        Enum.map(records, fn record ->
          current - record.generation
        end)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp increment_generation(changeset) do
    current = Ash.Changeset.get_attribute(changeset, :generation) || 0
    Ash.Changeset.change_attribute(changeset, :generation, current + 1)
  end

  defp increment_challenge_count(changeset) do
    current = Ash.Changeset.get_attribute(changeset, :challenge_count) || 0
    Ash.Changeset.change_attribute(changeset, :challenge_count, current + 1)
  end

  defp increment_defended_count(changeset) do
    current = Ash.Changeset.get_attribute(changeset, :defended_count) || 0
    Ash.Changeset.change_attribute(changeset, :defended_count, current + 1)
  end

  defp emit_elite_event(entry, event_type, extra \\ %{}) do
    payload =
      Map.merge(
        %{
          entry_id: entry.id,
          cell_key: entry.cell_key,
          fitness: entry.fitness,
          generation: entry.generation,
          timestamp: DateTime.utc_now()
        },
        extra
      )

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "evolution:elites",
      {:elite_event, event_type, payload}
    )

    :telemetry.execute(
      [:thunderline, :evolution, :elite, event_type],
      %{count: 1, fitness: entry.fitness},
      %{cell_key: entry.cell_key, generation: entry.generation}
    )

    :ok
  end
end
