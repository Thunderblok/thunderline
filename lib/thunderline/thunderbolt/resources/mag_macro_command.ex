defmodule Thunderline.Thunderbolt.Resources.MagMacroCommand do
  @moduledoc """
  Ash resource for macro commands that get converted to micro tasks.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "thundermag_macro_commands"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :command_type, :atom do
      allow_nil? false
    end

    attribute :macro_input, :string do
      allow_nil? false
    end

    attribute :micro_tasks, {:array, :map} do
      allow_nil? false
      default []
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
    end

    attribute :execution_metadata, :map do
      default %{}
    end

    attribute :session_id, :uuid
    attribute :zone_preferences, {:array, :string}, default: []
    attribute :priority, :atom, default: :normal
    attribute :estimated_duration_ms, :integer
    attribute :actual_duration_ms, :integer

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :command_type,
        :macro_input,
        :execution_metadata,
        :session_id,
        :zone_preferences,
        :priority
      ]
    end

    create :convert_message do
      accept [:command_type, :macro_input, :execution_metadata, :session_id]

      change fn changeset, _context ->
        macro_input = Ash.Changeset.get_attribute(changeset, :macro_input)
        command_type = Ash.Changeset.get_attribute(changeset, :command_type)

        case command_type do
          :type_message ->
            micro_tasks = convert_typing_message(macro_input)
            estimated_duration = estimate_duration(micro_tasks)

            changeset
            |> Ash.Changeset.change_attribute(:micro_tasks, micro_tasks)
            |> Ash.Changeset.change_attribute(:estimated_duration_ms, estimated_duration)
            |> Ash.Changeset.change_attribute(:status, :converted)

          _ ->
            changeset
        end
      end
    end

    update :mark_executing do
      accept [:status, :actual_duration_ms]
    end

    update :mark_completed do
      accept [:status, :actual_duration_ms]
    end
  end

  preparations do
    prepare build(load: [:micro_tasks, :execution_metadata])
  end

  # === Private Functions ===

  defp convert_typing_message(message) do
    message
    |> String.graphemes()
    |> Enum.with_index(1)
    |> Enum.map(fn {character, sequence} ->
      %{
        task_id: UUID.uuid4(),
        task_type: :type_letter,
        value: character,
        sequence: sequence,
        zone_assignment: :auto,
        execution_window: calculate_execution_window(sequence),
        priority: :normal,
        retry_count: 0,
        max_retries: 3,
        timeout_ms: 5000,
        metadata: %{
          created_at: DateTime.utc_now(),
          character_type: classify_character(character)
        }
      }
    end)
  end

  defp calculate_execution_window(sequence) do
    # Group tasks in batches of 5 for staggered execution
    div(sequence - 1, 5) + 1
  end

  defp classify_character(character) do
    cond do
      character =~ ~r/[A-Z]/ -> :uppercase
      character =~ ~r/[a-z]/ -> :lowercase
      character =~ ~r/[0-9]/ -> :digit
      character == " " -> :space
      character =~ ~r/[[:punct:]]/ -> :punctuation
      true -> :other
    end
  end

  defp estimate_duration(micro_tasks) do
    # Estimate 50ms per character
    length(micro_tasks) * 50
  end
end
