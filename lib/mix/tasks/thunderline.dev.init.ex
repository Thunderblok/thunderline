defmodule Mix.Tasks.Thunderline.Dev.Init do
  @shortdoc "(Re)create local Postgres DB, run ash codegen + migrations, and print next steps"
  @moduledoc """
  Boots a fresh development database after it has been dropped or deleted.

  What it does:
    1. Ensures the application is compiled
    2. Creates the database (ignores 'already exists')
    3. Runs `mix ash.codegen` to produce any pending migrations
    4. Runs `mix ash_postgres.migrate`
    5. (Optional) Seeds a baseline community + channel if OWNER_USER_ID env is set

  Usage:
      mix thunderline.dev.init

  Environment variables:
    OWNER_USER_ID   - UUID of an existing user to own the seed community
    COMMUNITY_SLUG  - Defaults to "general"
    CHANNEL_SLUG    - Defaults to "lobby"
  """
  use Mix.Task

  alias Thunderline.Repo

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    ensure_db_created()
    run_task("ash.codegen")
    run_task("ash_postgres.migrate")
    maybe_seed()

    Mix.shell().info("\n✅ Dev bootstrap complete. Start server with: mix phx.server")
    Mix.shell().info("If LiveView UI still shows DB errors, ensure Postgres is actually running and port matches config.")
  end

  defp ensure_db_created do
    Mix.shell().info("Creating database (if missing)...")
    try do
      run_task("ash_postgres.create")
    rescue
      e -> Mix.shell().info("(ignoring create error) #{Exception.message(e)}")
    end
  end

  defp run_task(name) do
    Mix.shell().info("→ #{name}")
    Mix.Task.run(name, [])
  end

  defp maybe_seed do
    owner_id = System.get_env("OWNER_USER_ID")
    if owner_id do
      community_slug = System.get_env("COMMUNITY_SLUG") || "general"
      channel_slug = System.get_env("CHANNEL_SLUG") || "lobby"

      seed_results = seed_comm_channel(owner_id, community_slug, channel_slug)
      Mix.shell().info("Seed results: #{inspect(seed_results)}")
    else
      Mix.shell().info("Skipping seed (set OWNER_USER_ID env var to seed baseline community & channel)")
    end
  end

  defp seed_comm_channel(owner_id, community_slug, channel_slug) do
    {:ok, community} =
      Thunderline.Thunderlink.Resources.Community
      |> Ash.Changeset.for_create(:create, %{
        community_name: String.capitalize(community_slug),
        community_slug: community_slug,
        community_type: :public_realm,
        governance_model: :founder_led,
        owner_id: owner_id
      })
      |> Ash.create()

    {:ok, channel} =
      Thunderline.Thunderlink.Resources.Channel
      |> Ash.Changeset.for_create(:create, %{
        channel_name: String.capitalize(channel_slug),
        channel_slug: channel_slug,
        channel_type: :text,
        community_id: community.id
      })
      |> Ash.create()

    %{community: community.id, channel: channel.id}
  rescue
    e -> %{error: Exception.message(e)}
  end
end
