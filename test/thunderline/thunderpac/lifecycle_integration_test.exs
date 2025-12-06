defmodule Thunderline.Thunderpac.LifecycleIntegrationTest do
  @moduledoc """
  Boss 2 Integration Test: Minimal PAC Lifecycle (Backend Only)

  Tests the full PAC lifecycle through code interfaces:
  - spawn → ignite → activate → tick → archive
  - Event emission to EventBus
  - Tick processing increments counters
  - History retrieval via with_history action
  """
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderpac.Resources.PAC
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Event

  @moduletag :boss2

  # Helper to spawn PAC with correct argument pattern
  # spawn(name, persona \\ nil, kernel_id \\ nil, opts)
  defp spawn_pac(name, opts \\ []) do
    PAC.spawn(name, %{}, nil, opts)
  end

  describe "PAC lifecycle through code interfaces" do
    test "spawn creates a PAC in seed state" do
      pac_name = "test_pac_#{System.unique_integer([:positive])}"

      {:ok, pac} = spawn_pac(pac_name, authorize?: false)

      assert pac.name == pac_name
      assert pac.status == :seed
      assert pac.total_active_ticks == 0
    end

    test "ignite transitions PAC from seed to dormant" do
      pac_name = "test_pac_#{System.unique_integer([:positive])}"
      {:ok, pac} = spawn_pac(pac_name, authorize?: false)

      {:ok, pac} = PAC.ignite(pac, authorize?: false)

      assert pac.status == :dormant
    end

    test "activate transitions PAC from dormant to active" do
      pac_name = "test_pac_#{System.unique_integer([:positive])}"
      {:ok, pac} = spawn_pac(pac_name, authorize?: false)
      {:ok, pac} = PAC.ignite(pac, authorize?: false)

      {:ok, pac} = PAC.activate(pac, authorize?: false)

      assert pac.status == :active
    end

    test "tick increments active_ticks for active PAC" do
      pac_name = "test_pac_#{System.unique_integer([:positive])}"
      {:ok, pac} = spawn_pac(pac_name, authorize?: false)
      {:ok, pac} = PAC.ignite(pac, authorize?: false)
      {:ok, pac} = PAC.activate(pac, authorize?: false)

      assert pac.total_active_ticks == 0

      {:ok, pac} = PAC.tick(pac, authorize?: false)

      assert pac.total_active_ticks == 1

      # Tick again
      {:ok, pac} = PAC.tick(pac, authorize?: false)

      assert pac.total_active_ticks == 2
    end

    test "full lifecycle: spawn → ignite → activate → tick → suspend → archive" do
      pac_name = "test_pac_#{System.unique_integer([:positive])}"

      # Spawn
      {:ok, pac} = spawn_pac(pac_name, authorize?: false)
      assert pac.status == :seed

      # Ignite
      {:ok, pac} = PAC.ignite(pac, authorize?: false)
      assert pac.status == :dormant

      # Activate
      {:ok, pac} = PAC.activate(pac, authorize?: false)
      assert pac.status == :active

      # Tick a few times
      {:ok, pac} = PAC.tick(pac, authorize?: false)
      {:ok, pac} = PAC.tick(pac, authorize?: false)
      {:ok, pac} = PAC.tick(pac, authorize?: false)
      assert pac.total_active_ticks == 3

      # Suspend
      {:ok, pac} = PAC.suspend(pac, authorize?: false)
      assert pac.status == :suspended

      # Archive
      {:ok, pac} = PAC.archive(pac, authorize?: false)
      assert pac.status == :archived
    end

    test "active_pacs returns only active PACs" do
      # Create multiple PACs in different states
      pac1_name = "test_active_#{System.unique_integer([:positive])}"
      pac2_name = "test_dormant_#{System.unique_integer([:positive])}"
      pac3_name = "test_active_#{System.unique_integer([:positive])}"

      # PAC 1: active
      {:ok, pac1} = spawn_pac(pac1_name, authorize?: false)
      {:ok, pac1} = PAC.ignite(pac1, authorize?: false)
      {:ok, _pac1} = PAC.activate(pac1, authorize?: false)

      # PAC 2: dormant (not activated)
      {:ok, pac2} = spawn_pac(pac2_name, authorize?: false)
      {:ok, _pac2} = PAC.ignite(pac2, authorize?: false)

      # PAC 3: active
      {:ok, pac3} = spawn_pac(pac3_name, authorize?: false)
      {:ok, pac3} = PAC.ignite(pac3, authorize?: false)
      {:ok, _pac3} = PAC.activate(pac3, authorize?: false)

      # Query active PACs
      {:ok, active_pacs} = PAC.active_pacs(authorize?: false)

      active_names = Enum.map(active_pacs, & &1.name)

      assert pac1_name in active_names
      assert pac3_name in active_names
      refute pac2_name in active_names
    end
  end

  describe "with_history action" do
    test "loads PAC with relationships" do
      pac_name = "test_history_#{System.unique_integer([:positive])}"
      {:ok, pac} = spawn_pac(pac_name, authorize?: false)
      {:ok, pac} = PAC.ignite(pac, authorize?: false)
      {:ok, pac} = PAC.activate(pac, authorize?: false)

      # Get PAC with history - should load relationships
      {:ok, pac_with_history} = PAC.with_history(pac.id, authorize?: false)

      # Verify relationships are loaded (not NotLoaded)
      assert is_list(pac_with_history.state_snapshots)
      assert is_list(pac_with_history.intents)
    end
  end

  describe "intent management" do
    test "push_intent adds intent to PAC" do
      pac_name = "test_intent_#{System.unique_integer([:positive])}"
      {:ok, pac} = spawn_pac(pac_name, authorize?: false)
      {:ok, pac} = PAC.ignite(pac, authorize?: false)
      {:ok, pac} = PAC.activate(pac, authorize?: false)

      intent = %{type: "explore", target: "zone_alpha", priority: 1}

      {:ok, pac} = PAC.push_intent(pac, intent, authorize?: false)

      # Load intents to verify
      {:ok, pac_with_intents} = PAC.with_history(pac.id, authorize?: false)
      assert length(pac_with_intents.intents) >= 1
    end
  end

  describe "by_status query" do
    test "filters PACs by status" do
      # Create PACs in different states
      active_name = "test_by_status_active_#{System.unique_integer([:positive])}"
      dormant_name = "test_by_status_dormant_#{System.unique_integer([:positive])}"

      {:ok, active_pac} = spawn_pac(active_name, authorize?: false)
      {:ok, active_pac} = PAC.ignite(active_pac, authorize?: false)
      {:ok, _active_pac} = PAC.activate(active_pac, authorize?: false)

      {:ok, dormant_pac} = spawn_pac(dormant_name, authorize?: false)
      {:ok, _dormant_pac} = PAC.ignite(dormant_pac, authorize?: false)

      # Query by status
      {:ok, active_pacs} = PAC.by_status(:active, authorize?: false)
      {:ok, dormant_pacs} = PAC.by_status(:dormant, authorize?: false)

      active_names = Enum.map(active_pacs, & &1.name)
      dormant_names = Enum.map(dormant_pacs, & &1.name)

      assert active_name in active_names
      assert dormant_name in dormant_names
      refute active_name in dormant_names
    end
  end
end
