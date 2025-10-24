defmodule Thunderline.Repo do
  @moduledoc """
  Thunderline primary database repository.

  Configured to use PostgreSQL with Ash framework integration.
  """

  use AshPostgres.Repo,
    otp_app: :thunderline

  require Logger

  # Implement required AshPostgres.Repo callbacks
  @impl true
  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext", "vector"]
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

  @impl true
  # Log (once) when running in slim mode. We avoid overriding child_spec since
  # it's not an overridable callback in AshPostgres.Repo's use macro.
  def init(_type, config) do
    if System.get_env("SKIP_ASH_SETUP") in ["1", "true"] do
      Logger.warning(
        "[Thunderline.Repo] SKIP_ASH_SETUP active - repo would normally start (excluded by supervision tree)"
      )
    end

    {:ok, config}
  end
end
