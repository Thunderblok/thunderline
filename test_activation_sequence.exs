#!/usr/bin/env elixir

# Quick test script to verify domain activation sequence
# Usage: mix run test_activation_sequence.exs

IO.puts("🔥 THUNDERBEAT ACTIVATION TEST 🔥\n")
IO.puts("Waiting 6 seconds for domain activations...\n")

# Sleep to let all domains activate (tick 1-4 = 4 seconds + buffer)
Process.sleep(6000)

IO.puts("\n📊 CHECKING ACTIVE DOMAINS...")

try do
  active = Thunderline.Thunderblock.DomainRegistry.active_domains()
  IO.puts("Active domains: #{inspect(active, pretty: true)}")
  IO.puts("Count: #{length(active)}")

  IO.puts("\n🔍 INDIVIDUAL DOMAIN STATUS...")

  domains = ["thunderflow", "thundergate", "thunderlink", "thunderbolt", "thundercrown"]

  Enum.each(domains, fn domain ->
    case Thunderline.Thunderblock.DomainRegistry.domain_status(domain) do
      {:ok, status} ->
        IO.puts("  ✅ #{domain}: #{inspect(status, pretty: true)}")

      {:error, reason} ->
        IO.puts("  ❌ #{domain}: #{inspect(reason)}")
    end
  end)

  IO.puts("\n📜 DATABASE PERSISTENCE CHECK...")

  query = """
  SELECT domain_name, status, tick_count, activated_at
  FROM active_domain_registry
  ORDER BY tick_count
  """

  case Thunderline.Repo.query(query) do
    {:ok, %{rows: rows, columns: cols}} ->
      IO.puts("Columns: #{inspect(cols)}")

      Enum.each(rows, fn row ->
        IO.puts("  #{inspect(row)}")
      end)

    {:error, err} ->
      IO.puts("Error: #{inspect(err)}")
  end

  IO.puts("\n⚡ ACTIVATION TEST COMPLETE ⚡")
rescue
  e ->
    IO.puts("\n❌ ERROR: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end
