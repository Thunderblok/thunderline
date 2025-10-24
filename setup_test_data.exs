#!/usr/bin/env elixir

require Ash.Query
import Ash.Expr

IO.puts("\n======================================================================")
IO.puts("Setting up test data for hands-on dashboard testing")
IO.puts("======================================================================")

# Ensure application is started
Application.ensure_all_started(:thunderline)

alias Thunderline.Thundercom.Resources.{Community, Channel, Message}
alias Thunderline.Thundercom.Domain, as: ThundercomDomain
alias Thunderline.Thundergate.Resources.User
alias Thunderline.Thundergate.Domain, as: ThundergateDomain

try do
  # Step 1: Create a test user (directly via repo since User doesn't have create action)
  IO.puts("\nStep 1: Creating test user...")
  
  # Insert directly via Ecto since AshAuthentication manages user creation
  unique_id = System.system_time(:millisecond)
  test_email = "testuser-#{unique_id}@thunderline.local"
  
  %{rows: [[user_id]]} = Ecto.Adapters.SQL.query!(Thunderline.Repo, """
    INSERT INTO users (id, email, hashed_password, inserted_at, updated_at) 
    VALUES (gen_random_uuid(), $1, $2, NOW(), NOW()) 
    RETURNING id
  """, [test_email, "$2b$12$dummyhashfortesting"])
  
  # Create a simple struct for compatibility
  user = %{id: user_id, email: test_email}
  
  IO.puts("  ✓ Created user: #{user.email} (ID: #{user.id})")

  # Step 2: Create a test community
  IO.puts("\nStep 2: Creating test community...")
  
  community = Community
  |> Ash.Changeset.for_create(:create, %{
    community_name: "Test Community",
    community_slug: "test-community",
    description: "A test community for hands-on testing",
    visibility: :public,
    status: :active,
    created_by: user.id
  })
  |> Ash.create!(domain: ThundercomDomain, authorize?: false, load: [])
  
  IO.puts("  ✓ Created community: #{community.community_name} (ID: #{community.id})")
  IO.puts("  ✓ Community slug: #{community.community_slug}")

  # Step 3: Create test channels
  IO.puts("\nStep 3: Creating test channels...")
  
  general_channel = Channel
  |> Ash.Changeset.for_create(:create, %{
    channel_name: "general",
    channel_slug: "general",
    community_id: community.id,
    created_by: user.id,
    channel_type: :text,
    visibility: :public,
    status: :active,
    topic: "General discussion for the test community"
  })
  |> Ash.create!(domain: ThundercomDomain, authorize?: false, load: [])
  
  IO.puts("  ✓ Created channel: ##{general_channel.channel_name} (ID: #{general_channel.id})")
  
  random_channel = Channel
  |> Ash.Changeset.for_create(:create, %{
    channel_name: "random",
    channel_slug: "random",
    community_id: community.id,
    created_by: user.id,
    channel_type: :text,
    visibility: :public,
    status: :active,
    topic: "Random chat and off-topic discussions"
  })
  |> Ash.create!(domain: ThundercomDomain, authorize?: false, load: [])
  
  IO.puts("  ✓ Created channel: ##{random_channel.channel_name} (ID: #{random_channel.id})")

  # Step 4: Create some test messages
  IO.puts("\nStep 4: Creating test messages...")
  
  messages = [
    "Welcome to the test community! 👋",
    "This is a test message to verify the chat functionality.",
    "You can now test real-time messaging in the dashboard!",
    "Try sending your own messages through the web interface."
  ]
  
  for {content, index} <- Enum.with_index(messages, 1) do
    message = Message
    |> Ash.Changeset.for_create(:create, %{
      content: content,
      channel_id: general_channel.id,
      sender_id: user.id,
      message_type: :user
    })
    |> Ash.create!(domain: ThundercomDomain, authorize?: false, load: [])
    
    IO.puts("  ✓ Created message #{index}: #{String.slice(content, 0, 30)}...")
  end

  IO.puts("\n======================================================================")
  IO.puts("✅ TEST DATA SETUP COMPLETE!")
  IO.puts("======================================================================")
  IO.puts("")
  IO.puts("📍 You can now test the chat functionality at:")
  IO.puts("   http://localhost:4000/c/#{community.community_slug}/#{general_channel.channel_slug}")
  IO.puts("")
  IO.puts("🔧 Test user credentials:")
  IO.puts("   Email: #{user.email}")
  IO.puts("   User ID: #{user.id}")
  IO.puts("")
  IO.puts("🏠 Community: #{community.community_name}")
  IO.puts("   Slug: #{community.community_slug}")
  IO.puts("")
  IO.puts("💬 Channels:")
  IO.puts("   ##{general_channel.channel_name} - #{general_channel.topic}")
  IO.puts("   ##{random_channel.channel_name} - #{random_channel.topic}")
  IO.puts("")
  IO.puts("🚀 Start the Phoenix server with: mix phx.server")
  IO.puts("   Then visit the URL above to test live chat!")
  IO.puts("")

rescue
  e ->
    IO.puts("\n✗✗✗ ERROR OCCURRED ✗✗✗")
    IO.puts("Error: #{inspect(e)}")
    IO.puts("")
    IO.puts("This might be due to:")
    IO.puts("1. Database not running")
    IO.puts("2. Data already exists (try clearing DB first)")
    IO.puts("3. Missing migrations")
    IO.puts("")
    IO.puts("Try running: mix ecto.reset")
end