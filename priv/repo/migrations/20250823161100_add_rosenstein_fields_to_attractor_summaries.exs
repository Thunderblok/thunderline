defmodule Thunderline.Repo.Migrations.AddRosensteinFieldsToAttractorSummaries do
  use Ecto.Migration
  # This migration became a no-op because the columns were included in the
  # original create table migration. Kept to satisfy historical ordering.
  def change, do: :ok
end
