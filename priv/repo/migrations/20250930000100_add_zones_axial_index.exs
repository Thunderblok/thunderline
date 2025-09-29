defmodule Thunderline.Repo.Migrations.AddZonesAxialIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists unique_index(:zones, [:q, :r], name: :zones_axial_coordinate_index)
  end
end
