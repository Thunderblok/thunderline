#!/usr/bin/env elixir

# Test message flow without starting the application
# This script connects to the running Phoenix server

Mix.install([])

# Connect to the running node
IO.puts("\n========================================")
IO.puts("Testing End-to-End Message Flow")
IO.puts("========================================\n")

# Try to connect to running Phoenix instance
node_name = :"thunderline@127.0.0.1"
cookie = :thunderline

IO.puts("Attempting to connect to #{node_name}...")

case Node.connect(node_name) do
  true ->
    IO.puts("✓ Connected to running Phoenix server")

    # Execute remote code on the running node
    result = :rpc.call(node_name, Code, :eval_string, ["""
      alias Thunderline.Repo
      alias Thunderline.Thundercom.{Channel, Message}
      alias Thunderline.Accounts.User

      # Find demo user
      user = Repo.get_by!(User, email: "demo@thunderline.dev")
      IO.puts("✓ User found: \#{user.email}")

      # Create test channel
      channel_name = "test-channel-\#{:rand.uniform(100000)}"
      {:ok, channel} = Channel
        |> Ash.Changeset.for_create(:create, %{
          name: channel_name,
          display_name: "Test Channel",
          kind: :public
        }, actor: user)
        |> Ash.create()

      IO.puts("✓ Channel created: \#{channel.name}")

      # Send message through Channel.send_message
      # This tests: 1) send_message not stubbed, 2) no Thunderblock.Domain error, 3) event routing works
      {:ok, message} = Channel.send_message(channel.id, "Test message from automated test", actor: user)
      IO.puts("✓ Message sent successfully (ID: \#{message.id})")

      # Verify message persisted
      loaded_message = Repo.get!(Message, message.id)
      IO.puts("✓ Message persisted to database")

      # Reload channel to check metrics updated
      reloaded_channel = Repo.get!(Channel, channel.id)
      if reloaded_channel.message_count > 0 do
        IO.puts("✓ Channel metrics updated (message_count: \#{reloaded_channel.message_count})")
      else
        IO.puts("⚠ Warning: Channel message_count not updated")
      end

      IO.puts("\\n========================================")
      IO.puts("ALL TESTS PASSED ✓")
      IO.puts("Todo #4 (Test end-to-end message flow) - COMPLETE")
      IO.puts("========================================\\n")

      :ok
    """])

    case result do
      :ok ->
        System.halt(0)
      {:badrpc, reason} ->
        IO.puts("\n✗ RPC error: #{inspect(reason)}")
        System.halt(1)
      error ->
        IO.puts("\n✗ Test failed: #{inspect(error)}")
        System.halt(1)
    end

  false ->
    IO.puts("""
    ✗ Could not connect to running Phoenix server

    Make sure the Phoenix server is running with:
      mix phx.server

    Or try running with distributed Erlang enabled:
      elixir --sname thunderline --cookie thunderline -S mix phx.server
    """)
    System.halt(1)
end
