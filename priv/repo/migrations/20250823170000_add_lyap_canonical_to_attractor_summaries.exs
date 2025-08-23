defmodule Thunderline.Repo.Migrations.AddLyapCanonicalToAttractorSummaries do
  use Ecto.Migration

  def change do
    alter table(:probe_attractor_summaries) do
      add :lyap_canonical, :float
    end
  end
end
