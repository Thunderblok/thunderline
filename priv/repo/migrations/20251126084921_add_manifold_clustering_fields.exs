defmodule Thunderline.Repo.Migrations.AddManifoldClusteringFields do
  @moduledoc """
  Adds Multi-Manifold Clustering fields to upm_observations table.

  HC-22A: manifold_id, cluster_stability, manifold_distance, simplex_degree
  """
  use Ecto.Migration

  def change do
    alter table(:upm_observations) do
      add :manifold_id, :integer
      add :cluster_stability, :float
      add :manifold_distance, :float
      add :simplex_degree, :integer
    end

    create index(:upm_observations, [:manifold_id], name: "upm_observations_manifold_id_idx")
  end
end
