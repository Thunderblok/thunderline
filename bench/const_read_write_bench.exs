Mix.install([
  {:benchee, "~> 1.3"}
])

tab = :const_bench
:ets.new(tab, [:named_table, :public, :set, read_concurrency: true])

big_map = for i <- 1..50_000, into: %{}, do: {"k#{i}", i}

:persistent_term.put({:bench, :map}, big_map)
:ets.insert(tab, {:map, big_map})

write_payload = for i <- 1..10_000, into: %{}, do: {"w#{i}", i}

Benchee.run(%{
  "persistent_term.get" => fn -> :persistent_term.get({:bench, :map}) end,
  "ets.lookup_element" => fn -> :ets.lookup_element(tab, :map, 2) end,
  "persistent_term.put (write)" => fn -> :persistent_term.put({:bench, :tmp}, write_payload) end,
  "ets.insert (write)" => fn -> :ets.insert(tab, {:tmp, write_payload}) end
}, time: 2, warmup: 1, memory_time: 0.4,
print: [configuration: false, benchmarking: false])

IO.puts("\nNOTE: persistent_term.put shows why we avoid frequent swaps.")
