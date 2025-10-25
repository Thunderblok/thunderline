# Seeds for Chat Demo - Creates test community, channels, and a user

IO.puts("\n=== Creating Chat Demo Data ===\n")

alias Thunderline.Thundercom.Resources.{Channel, Community}
alias Thunderline.Thundergate.Resources.User
alias Thunderline.Repo

# Clean up any existing demo data
IO.puts("Cleaning up existing demo data...")
Repo.delete_all(Channel)
Repo.delete_all(Community)

# Create a test user (insert directly since User only has auth actions)
{:ok, user} = Repo.insert(%User{
  id: Ash.UUID.generate(),
  email: "demo@thunderline.dev",
  hashed_password: "$2b$12$dummyhashfortest",
  inserted_at: DateTime.utc_now(),
  updated_at: DateTime.utc_now()
})

IO.puts("✓ Created demo user: #{user.email}")

# Create a demo community
community = Community
|> Ash.Changeset.for_create(:create, %{
  community_name: "Thunderline Demo",
  community_slug: "demo",
  owner_id: user.id
})
|> Ash.create!(authorize?: false)

IO.puts("✓ Created community: #{community.community_name}")
IO.puts("  URL: http://localhost:4000/c/demo")

# Create some demo channels
channels = [
  %{name: "General", slug: "general", description: "General discussion"},
  %{name: "Development", slug: "dev", description: "Development chat"},
  %{name: "Random", slug: "random", description: "Off-topic chat"}
]

created_channels = Enum.map(channels, fn channel_data ->
  channel = Channel
  |> Ash.Changeset.for_create(:create, %{
    channel_name: channel_data.name,
    channel_slug: channel_data.slug,
    community_id: community.id,
    created_by: user.id
  })
  |> Ash.create!(authorize?: false)
  
  IO.puts("✓ Created channel: ##{channel_data.slug}")
  IO.puts("  URL: http://localhost:4000/c/demo/#{channel_data.slug}")
  
  channel
end)

IO.puts("\n=== Demo Data Created Successfully! ===")
IO.puts("\nAccess the demo:")
IO.puts("  Community: http://localhost:4000/c/demo")
IO.puts("  Channel:   http://localhost:4000/c/demo/general")
IO.puts("\nNote: Authentication may be required. Use sign-in at:")
IO.puts("  Sign-in:   http://localhost:4000/sign-in")
IO.puts("")
