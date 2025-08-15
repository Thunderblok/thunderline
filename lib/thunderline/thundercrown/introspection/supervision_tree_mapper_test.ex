defmodule Thunderline.Thundercrown.Introspection.SupervisionTreeMapperTest do
  @moduledoc """
  Test module to verify supervision tree mapping functionality
  """

  alias Thunderline.Thundercrown.Introspection.SupervisionTreeMapper
  alias ExRoseTree

  def test_basic_mapping do
    IO.puts("\n🌩️ THUNDERCROWN SUPERVISION TREE MAPPING TEST 🌩️")
    IO.puts("=" |> String.duplicate(50))

    # Map the supervision tree
    IO.puts("\n📊 Mapping current supervision tree...")
    tree = SupervisionTreeMapper.map_supervision_tree()

    # Print the tree structure
    IO.puts("\n🌳 SUPERVISION TREE STRUCTURE:")
    SupervisionTreeMapper.print_supervision_tree(tree)

    # Analyze the tree
    IO.puts("\n📈 TREE ANALYSIS:")
    stats = SupervisionTreeMapper.analyze_supervision_tree(tree)
    IO.puts("Total processes: #{stats.total_processes}")
    IO.puts("Supervisors: #{stats.supervisors}")
    IO.puts("Workers: #{stats.workers}")
    IO.puts("Running: #{stats.running}")
    IO.puts("Not running: #{stats.not_running}")

    # Extract Thunder domain services
    IO.puts("\n⚡ THUNDER DOMAIN SERVICES:")
    domains = SupervisionTreeMapper.extract_thunder_domains(tree)

    Enum.each(domains, fn {domain, processes} ->
      if length(processes) > 0 do
        IO.puts("  #{String.upcase(to_string(domain))}: #{length(processes)} process(es)")

        Enum.each(processes, fn process_tree ->
          {name, type, _info} = ExRoseTree.get_term(process_tree)
          IO.puts("    - #{name} (#{type})")
        end)
      end
    end)

    IO.puts("\n✅ Supervision tree mapping test completed!")
    IO.puts("=" |> String.duplicate(50))

    :ok
  end

  def test_rose_tree_operations do
    IO.puts("\n🌹 ROSE TREE OPERATIONS TEST 🌹")
    IO.puts("=" |> String.duplicate(40))

    # Create a simple rose tree
    tree =
      ExRoseTree.new(:root, [
        ExRoseTree.new(:child1, [:grandchild1, :grandchild2]),
        ExRoseTree.new(:child2, [:grandchild3])
      ])

    IO.puts("\n📊 Testing rose tree basic operations...")
    IO.puts("Root term: #{inspect(ExRoseTree.get_term(tree))}")
    IO.puts("Children count: #{length(ExRoseTree.get_children(tree))}")

    # Test enumeration
    IO.puts("\n🔄 Enumerating all terms in tree:")
    tree |> Enum.each(fn term -> IO.puts("  - #{inspect(term)}") end)

    IO.puts("\n✅ Rose tree operations test completed!")
    IO.puts("=" |> String.duplicate(40))

    :ok
  end

  def run_all_tests do
    test_basic_mapping()
    test_rose_tree_operations()
  end
end
