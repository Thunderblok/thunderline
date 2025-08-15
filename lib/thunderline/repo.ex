defmodule Thunderline.Repo do
  @moduledoc """
  Thunderline primary database repository.

  Configured to use PostgreSQL with Ash framework integration.
  """

  use AshPostgres.Repo,
    otp_app: :thunderline

  # Implement required AshPostgres.Repo callbacks
  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
