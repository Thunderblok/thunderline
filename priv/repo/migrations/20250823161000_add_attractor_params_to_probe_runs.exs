defmodule Thunderline.Repo.Migrations.AddAttractorParamsToProbeRuns do
  use Ecto.Migration

  def change do
    alter table(:probe_runs) do
      add :attractor_m, :integer
      add :attractor_tau, :integer
      add :attractor_min_points, :integer
    end
  end
end
