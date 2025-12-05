defmodule Thunderline.Repo.Migrations.ChiefPlanResources do
  @moduledoc """
  Creates the chief_plan_trees and chief_plan_nodes tables for Thunderchief domain.
  
  This migration was cleaned to only include Thunderchief-specific tables.
  Other tables (thunderblock_channel_participants, evolution_elite_entries) are 
  handled by separate migrations.
  """

  use Ecto.Migration

  def up do
    create table(:chief_plan_nodes, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :label, :text, null: false
      add :node_type, :text, null: false, default: "action"
      add :status, :text, null: false, default: "pending"
      add :order, :bigint, null: false, default: 0
      add :payload, :map, default: %{}
      add :result, :map
      add :error, :map
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :plan_tree_id, :uuid, null: false
      add :parent_id, :uuid
    end

    create table(:chief_plan_trees, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:chief_plan_nodes) do
      modify :plan_tree_id,
             references(:chief_plan_trees,
               column: :id,
               name: "chief_plan_nodes_plan_tree_id_fkey",
               type: :uuid,
               on_delete: :delete_all
             )

      modify :parent_id,
             references(:chief_plan_nodes,
               column: :id,
               name: "chief_plan_nodes_parent_id_fkey",
               type: :uuid,
               on_delete: :nilify_all
             )
    end

    alter table(:chief_plan_trees) do
      add :goal, :text, null: false
      add :domain, :text, default: "bit"
      add :status, :text, null: false, default: "pending"
      add :metadata, :map, default: %{}
      add :error_message, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :root_node_id,
          references(:chief_plan_nodes,
            column: :id,
            name: "chief_plan_trees_root_node_id_fkey",
            type: :uuid,
            on_delete: :nilify_all
          )
    end

    create unique_index(:chief_plan_trees, [:goal, :domain],
             name: "chief_plan_trees_unique_goal_domain_index"
           )
  end

  def down do
    drop_if_exists unique_index(:chief_plan_trees, [:goal, :domain],
                     name: "chief_plan_trees_unique_goal_domain_index"
                   )

    drop constraint(:chief_plan_trees, "chief_plan_trees_root_node_id_fkey")

    alter table(:chief_plan_trees) do
      remove :root_node_id
      remove :updated_at
      remove :inserted_at
      remove :completed_at
      remove :started_at
      remove :error_message
      remove :metadata
      remove :status
      remove :domain
      remove :goal
    end

    drop constraint(:chief_plan_nodes, "chief_plan_nodes_plan_tree_id_fkey")

    drop constraint(:chief_plan_nodes, "chief_plan_nodes_parent_id_fkey")

    alter table(:chief_plan_nodes) do
      modify :parent_id, :uuid
      modify :plan_tree_id, :uuid
    end

    drop table(:chief_plan_trees)

    drop table(:chief_plan_nodes)
  end
end
