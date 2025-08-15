defmodule Thunderline.Thundergate.Resources.DataAdapter do
  @moduledoc """
  Format transformation and mapping configurations.

  Defines transformation rules for converting data between different formats
  and schemas when integrating with external systems.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergate.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "data_adapters"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :source_format, :string, allow_nil?: false
    attribute :target_format, :string, allow_nil?: false
    attribute :transformation_rules, :map, allow_nil?: false
    attribute :validation_schema, :map
    attribute :field_mappings, :map, default: %{}
    attribute :default_values, :map, default: %{}
    attribute :preprocessing_steps, {:array, :string}, default: []
    attribute :postprocessing_steps, {:array, :string}, default: []
    attribute :status, :atom, constraints: [one_of: [:active, :inactive, :testing]]
    attribute :test_input, :map
    attribute :expected_output, :map
    attribute :metadata, :map, default: %{}
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :register_adapter do
      accept [:name, :source_format, :target_format, :transformation_rules, :validation_schema, :field_mappings, :default_values, :preprocessing_steps, :postprocessing_steps, :test_input, :expected_output, :metadata]
    end

    update :activate do
      change set_attribute(:status, :active)
    end

    update :test_adapter do
      change set_attribute(:status, :testing)
    end

    create :transform_data do
      argument :input_data, :map, allow_nil?: false

      change fn changeset, _context ->
        # This would implement the actual transformation logic
        # For now, just store the transformation request
        changeset
      end
    end

    read :active_adapters do
      filter expr(status == :active)
    end

    read :by_formats do
      argument :source, :string, allow_nil?: false
      argument :target, :string, allow_nil?: false
      filter expr(source_format == ^arg(:source) and target_format == ^arg(:target))
    end
  end

  calculations do
    calculate :transformation_complexity, :atom, expr(
      cond do
        map_size(field_mappings) < 5 -> :simple
        map_size(field_mappings) < 15 -> :moderate
        true -> :complex
      end
    )
  end

  identities do
    identity :unique_adapter_name, [:name]
    identity :unique_transformation_path, [:source_format, :target_format, :name]
  end

  preparations do
    prepare build(sort: [name: :asc])
  end
end
