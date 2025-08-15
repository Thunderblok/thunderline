defmodule Thunderline.Repo do
  @moduledoc """
  Thunderline primary database repository.

  Configured to use PostgreSQL with Ash framework integration.
  """

  use AshPostgres.Repo,
    otp_app: :thunderline

  # Implement required AshPostgres.Repo callbacks
  @impl true
  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end
end
