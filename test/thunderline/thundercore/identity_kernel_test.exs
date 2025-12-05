defmodule Thunderline.Thundercore.IdentityKernelTest do
  @moduledoc """
  Tests for the IdentityKernel Ash resource.

  HC-46 requirement: Validates that:
  - IdentityKernel can be ignited (created) with unique kernel_id and seed
  - IdentityKernel can be derived from a parent kernel (lineage)
  - Kernel seeds are properly generated (32 bytes)
  - Created_at_tick captures system tick when available
  """
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercore.Resources.IdentityKernel

  describe "ignite/0 (create new kernel)" do
    test "creates a kernel with generated kernel_id" do
      {:ok, kernel} = IdentityKernel.ignite()

      assert is_binary(kernel.kernel_id)
      # kernel_id is a UUID string
      assert String.length(kernel.kernel_id) == 36
    end

    test "creates a kernel with 32-byte seed" do
      {:ok, kernel} = IdentityKernel.ignite()

      assert is_binary(kernel.seed)
      assert byte_size(kernel.seed) == 32
    end

    test "each ignite creates unique kernel_id" do
      {:ok, k1} = IdentityKernel.ignite()
      {:ok, k2} = IdentityKernel.ignite()

      refute k1.kernel_id == k2.kernel_id
    end

    test "each ignite creates unique seed" do
      {:ok, k1} = IdentityKernel.ignite()
      {:ok, k2} = IdentityKernel.ignite()

      refute k1.seed == k2.seed
    end

    test "records created_at_tick if TickEmitter is running" do
      {:ok, kernel} = IdentityKernel.ignite()

      # TickEmitter should be running in test env (via supervisor)
      # If not running, created_at_tick will be nil
      if Process.whereis(Thunderline.Thundercore.TickEmitter) do
        assert is_integer(kernel.created_at_tick)
        assert kernel.created_at_tick >= 0
      end
    end

    test "accepts optional metadata" do
      {:ok, kernel} = IdentityKernel.ignite(%{metadata: %{purpose: "test", version: 1}})

      # Metadata uses string keys due to JSON storage/serialization
      assert kernel.metadata == %{"purpose" => "test", "version" => 1}
    end

    test "defaults metadata to empty map" do
      {:ok, kernel} = IdentityKernel.ignite()

      assert kernel.metadata == %{}
    end
  end

  describe "derive/1 (create from parent)" do
    setup do
      {:ok, parent} = IdentityKernel.ignite(%{metadata: %{generation: 0}})
      {:ok, parent: parent}
    end

    test "creates kernel linked to parent", %{parent: parent} do
      {:ok, child} = IdentityKernel.derive(parent.kernel_id)

      assert child.lineage_id == parent.id
    end

    test "child has its own unique kernel_id", %{parent: parent} do
      {:ok, child} = IdentityKernel.derive(parent.kernel_id)

      refute child.kernel_id == parent.kernel_id
    end

    test "child has its own unique seed", %{parent: parent} do
      {:ok, child} = IdentityKernel.derive(parent.kernel_id)

      refute child.seed == parent.seed
    end

    test "can create multi-generation lineage" do
      {:ok, gen0} = IdentityKernel.ignite(%{metadata: %{generation: 0}})
      {:ok, gen1} = IdentityKernel.derive(gen0.kernel_id, %{metadata: %{generation: 1}})
      {:ok, gen2} = IdentityKernel.derive(gen1.kernel_id, %{metadata: %{generation: 2}})

      assert gen1.lineage_id == gen0.id
      assert gen2.lineage_id == gen1.id
    end

    test "accepts optional metadata", %{parent: parent} do
      {:ok, child} = IdentityKernel.derive(parent.kernel_id, %{metadata: %{derived: true}})

      # Metadata uses string keys due to JSON storage/serialization
      assert child.metadata == %{"derived" => true}
    end
  end

  describe "by_kernel_id/1 (lookup)" do
    test "finds kernel by kernel_id" do
      {:ok, created} = IdentityKernel.ignite()

      {:ok, [found]} = IdentityKernel.by_kernel_id(created.kernel_id)

      assert found.id == created.id
      assert found.kernel_id == created.kernel_id
    end

    test "returns empty list for non-existent kernel_id" do
      fake_uuid = Ash.UUID.generate()

      {:ok, results} = IdentityKernel.by_kernel_id(fake_uuid)

      assert results == []
    end
  end

  describe "identity constraints" do
    test "kernel_id must be unique" do
      {:ok, k1} = IdentityKernel.ignite()

      # Try to manually create another kernel with same kernel_id
      # This should fail due to unique constraint
      result =
        Thunderline.Thundercore.Resources.IdentityKernel
        |> Ash.Changeset.for_create(:ignite, %{})
        |> Ash.Changeset.force_change_attribute(:kernel_id, k1.kernel_id)
        |> Ash.create()

      assert {:error, _} = result
    end
  end

  describe "lineage relationship" do
    test "can load lineage relationship" do
      {:ok, parent} = IdentityKernel.ignite()
      {:ok, child} = IdentityKernel.derive(parent.kernel_id)

      {:ok, loaded} = Ash.load(child, :lineage)

      assert loaded.lineage.id == parent.id
      assert loaded.lineage.kernel_id == parent.kernel_id
    end
  end
end
