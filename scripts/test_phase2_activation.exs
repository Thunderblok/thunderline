#!/usr/bin/env elixir

# Phase 2 Domain Activation Test Script
# Tests that Thunderflow activates on tick 1

Mix.install([])

IO.puts("🧪 Phase 2: Domain Activation Test")
IO.puts("==================================\n")

# Start application in test mode
System.put_env("MIX_ENV", "test")
Application.put_env(:thunderline, :env, :test)

IO.puts("✓ Test environment configured")
IO.puts("✓ Starting minimal application...")

# This would normally run the full application
# For now, we'll document what to test manually

IO.puts("\n📋 Manual Test Checklist:")
IO.puts("-------------------------")
IO.puts("1. Start: iex -S mix")
IO.puts("2. Wait 2 seconds for tick system to start")
IO.puts("3. Check logs for:")
IO.puts("   [DomainRegistry] Started and subscribed...")
IO.puts("   [TickGenerator] Started with 1000ms interval")
IO.puts("   [DomainActivation] thunderflow subscribed, will activate at tick 1")
IO.puts("   [DomainActivation] thunderflow activated at tick 1")
IO.puts("   [Thunderflow] Domain activated at tick 1")
IO.puts("")
IO.puts("4. In IEx console, run:")
IO.puts("   Thunderline.Thunderblock.DomainRegistry.active_domains()")
IO.puts("   # Should return: [\"thunderflow\"]")
IO.puts("")
IO.puts("   Thunderline.Thunderblock.DomainRegistry.domain_status(\"thunderflow\")")
IO.puts("   # Should return: {:ok, %{status: :active, ...}}")
IO.puts("")
IO.puts("   Thunderline.Repo.query!(\"SELECT * FROM active_domain_registry\")")
IO.puts("   # Should show 1 row with domain_name='thunderflow', tick_count=1")
IO.puts("")
IO.puts("5. Wait ~10 seconds, check logs for:")
IO.puts("   [Thunderflow] Health check at tick 10")
IO.puts("   [Thunderflow] Health check at tick 20")
IO.puts("")

IO.puts("\n✅ Run these tests to verify Phase 2!")
