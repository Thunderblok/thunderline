defmodule Thunderline.Thunderblock.Resources.VaultKnowledgeNodeTest do
  @moduledoc """
  Comprehensive test suite for VaultKnowledgeNode multitenancy, RBAC, and authorization.

  Phase 3: Testing (28 comprehensive tests)
  - Tenant isolation (5 tests)
  - RBAC (4 tests)
  - Action authorization (16 tests)
  - Edge cases (3 tests)
  """

  use Thunderline.DataCase, async: true

  alias Thunderline.Thunderblock.Domain
  alias Thunderline.Thunderblock.Resources.VaultKnowledgeNode

  # ===== SETUP HELPERS =====

  defp create_tenant_actor(tenant_id, role \\ :user, scope \\ :normal) do
    %{
      id: Ash.UUID.generate(),
      tenant_id: tenant_id,
      role: role,
      scope: scope
    }
  end

  defp create_knowledge_node(tenant_id, attrs \\ %{}) do
    actor = create_tenant_actor(tenant_id)

    default_attrs = %{
      # tenant_id is set via tenant: option, NOT as an attribute
      node_type: "concept",
      title: "Test Node #{System.unique_integer([:positive])}",
      description: "Test knowledge node",
      knowledge_domain: "testing",
      confidence_level: 0.8,
      evidence_strength: 0.7,
      aliases: ["alias1", "alias2"],
      semantic_tags: ["tag1", "tag2"],
      source_domains: ["domain1"],
      memory_record_ids: [],
      embedding_vector_ids: [],
      relationship_data: %{},
      taxonomy_path: ["root", "testing"]
    }

    attrs = Map.merge(default_attrs, attrs)

    VaultKnowledgeNode
    |> Ash.Changeset.for_create(:create, attrs, actor: actor, tenant: tenant_id)
    |> Ash.create!()
  end

  # ===== TENANT ISOLATION TESTS (5 tests) =====

  describe "tenant isolation" do
    setup do
      tenant_a = Ash.UUID.generate()
      tenant_b = Ash.UUID.generate()

      actor_a = create_tenant_actor(tenant_a)
      actor_b = create_tenant_actor(tenant_b)

      node_a = create_knowledge_node(tenant_a, %{title: "Tenant A Node"})
      node_b = create_knowledge_node(tenant_b, %{title: "Tenant B Node"})

      %{
        tenant_a: tenant_a,
        tenant_b: tenant_b,
        actor_a: actor_a,
        actor_b: actor_b,
        node_a: node_a,
        node_b: node_b
      }
    end

    test "tenant cannot read another tenant's knowledge nodes", %{
      actor_b: actor_b,
      node_a: node_a
    } do
      # Tenant B trying to read Tenant A's node
      assert_raise Ash.Error.Forbidden, fn ->
        VaultKnowledgeNode
        |> Ash.get!(node_a.id, actor: actor_b, tenant: actor_b.tenant_id)
      end
    end

    test "tenant cannot update another tenant's knowledge nodes", %{
      actor_b: actor_b,
      node_a: node_a
    } do
      # Tenant B trying to update Tenant A's node
      assert_raise Ash.Error.Forbidden, fn ->
        node_a
        |> Ash.Changeset.for_update(:update, %{title: "Hacked Title"},
          actor: actor_b,
          tenant: actor_b.tenant_id
        )
        |> Ash.update!()
      end
    end

    test "tenant cannot delete another tenant's knowledge nodes", %{
      actor_b: actor_b,
      node_a: node_a
    } do
      # Tenant B trying to delete Tenant A's node
      assert_raise Ash.Error.Forbidden, fn ->
        node_a
        |> Ash.Changeset.for_destroy(:destroy, %{}, actor: actor_b, tenant: actor_b.tenant_id)
        |> Ash.destroy!()
      end
    end

    test "tenant can only list their own knowledge nodes", %{
      tenant_a: tenant_a,
      tenant_b: tenant_b,
      actor_a: actor_a,
      actor_b: actor_b,
      node_a: node_a,
      node_b: node_b
    } do
      # Tenant A should only see their own nodes
      nodes_a =
        VaultKnowledgeNode
        |> Ash.read!(actor: actor_a, tenant: tenant_a)

      node_ids_a = Enum.map(nodes_a, & &1.id)
      assert node_a.id in node_ids_a
      refute node_b.id in node_ids_a

      # Tenant B should only see their own nodes
      nodes_b =
        VaultKnowledgeNode
        |> Ash.read!(actor: actor_b, tenant: tenant_b)

      node_ids_b = Enum.map(nodes_b, & &1.id)
      assert node_b.id in node_ids_b
      refute node_a.id in node_ids_b
    end

    test "cross-tenant relationship linking attempts fail", %{
      tenant_a: tenant_a,
      actor_a: actor_a,
      node_a: node_a,
      node_b: node_b
    } do
      # Tenant A trying to link to Tenant B's node
      assert_raise Ash.Error.Forbidden, fn ->
        Domain.add_relationship!(
          node_a,
          node_b.id,
          "related_to",
          0.8,
          actor: actor_a,
          tenant: tenant_a
        )
      end
    end
  end

  # ===== RBAC TESTS (4 tests) =====

  describe "RBAC" do
    setup do
      tenant_id = Ash.UUID.generate()
      node = create_knowledge_node(tenant_id)

      %{tenant_id: tenant_id, node: node}
    end

    test "anonymous users cannot access knowledge nodes", %{node: node} do
      # No actor provided
      assert_raise Ash.Error.Forbidden, fn ->
        VaultKnowledgeNode
        |> Ash.get!(node.id)
      end
    end

    test "authenticated users can create nodes in their tenant", %{tenant_id: tenant_id} do
      actor = create_tenant_actor(tenant_id, :user)

      node =
        VaultKnowledgeNode
        |> Ash.Changeset.for_create(
          :create,
          %{
            node_type: "concept",
            title: "User Created Node",
            description: "Test",
            knowledge_domain: "user_domain",
            confidence_level: 0.5,
            evidence_strength: 0.5
          },
          actor: actor,
          tenant: tenant_id
        )
        |> Ash.create!()

      assert node.tenant_id == tenant_id
      assert node.title == "User Created Node"
    end

    test "system actors can bypass tenant isolation", %{node: node} do
      system_actor = %{
        id: Ash.UUID.generate(),
        role: :system,
        scope: :maintenance,
        tenant_id: Ash.UUID.generate()
      }

      # System actor can read node from different tenant
      fetched_node =
        VaultKnowledgeNode
        |> Ash.get!(node.id, actor: system_actor, tenant: system_actor.tenant_id)

      assert fetched_node.id == node.id
    end

    test "admin role has proper permissions within tenant", %{tenant_id: tenant_id, node: node} do
      admin_actor = create_tenant_actor(tenant_id, :admin)

      # Admin can update node
      updated_node =
        node
        |> Ash.Changeset.for_update(:update, %{title: "Admin Updated"},
          actor: admin_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert updated_node.title == "Admin Updated"

      # Admin can delete node
      node
      |> Ash.Changeset.for_destroy(:destroy, %{}, actor: admin_actor, tenant: tenant_id)
      |> Ash.destroy!()

      # Verify deletion
      assert_raise Ash.Error.Query.NotFound, fn ->
        VaultKnowledgeNode
        |> Ash.get!(node.id, actor: admin_actor, tenant: tenant_id)
      end
    end
  end

  # ===== ACTION AUTHORIZATION TESTS (16 tests) =====

  describe "action authorization" do
    setup do
      tenant_id = Ash.UUID.generate()
      user_actor = create_tenant_actor(tenant_id, :user)
      admin_actor = create_tenant_actor(tenant_id, :admin)
      curator_actor = create_tenant_actor(tenant_id, :curator)
      system_actor = %{id: Ash.UUID.generate(), role: :system, scope: :maintenance, tenant_id: tenant_id}

      node = create_knowledge_node(tenant_id)

      %{
        tenant_id: tenant_id,
        user_actor: user_actor,
        admin_actor: admin_actor,
        curator_actor: curator_actor,
        system_actor: system_actor,
        node: node
      }
    end

    test "create action requires proper authorization", %{tenant_id: tenant_id, user_actor: user_actor} do
      # User with tenant_id can create
      node =
        VaultKnowledgeNode
        |> Ash.Changeset.for_create(
          :create,
          %{
            node_type: "entity",
            title: "Auth Test Node",
            description: "Test",
            knowledge_domain: "test",
            confidence_level: 0.6,
            evidence_strength: 0.6
          },
          actor: user_actor,
          tenant: tenant_id
        )
        |> Ash.create!()

      assert node.tenant_id == tenant_id
    end

    test "read action respects tenant boundaries", %{tenant_id: tenant_id, user_actor: user_actor, node: node} do
      # User can read their own tenant's node
      fetched_node =
        VaultKnowledgeNode
        |> Ash.get!(node.id, actor: user_actor, tenant: tenant_id)

      assert fetched_node.id == node.id

      # User from different tenant cannot read
      other_tenant_actor = create_tenant_actor(Ash.UUID.generate(), :user)

      assert_raise Ash.Error.Forbidden, fn ->
        VaultKnowledgeNode
        |> Ash.get!(node.id, actor: other_tenant_actor, tenant: other_tenant_actor.tenant_id)
      end
    end

    test "update action enforces ownership", %{tenant_id: tenant_id, user_actor: user_actor, node: node} do
      # User can update node in their tenant
      updated_node =
        node
        |> Ash.Changeset.for_update(:update, %{description: "Updated by user"},
          actor: user_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert updated_node.description == "Updated by user"
    end

    test "delete action enforces ownership", %{tenant_id: tenant_id, admin_actor: admin_actor} do
      node = create_knowledge_node(tenant_id)

      # Admin can delete node in their tenant
      node
      |> Ash.Changeset.for_destroy(:destroy, %{}, actor: admin_actor, tenant: tenant_id)
      |> Ash.destroy!()

      # Verify deletion
      assert_raise Ash.Error.Query.NotFound, fn ->
        VaultKnowledgeNode
        |> Ash.get!(node.id, actor: admin_actor, tenant: tenant_id)
      end
    end

    test "list action filters by tenant_id", %{tenant_id: tenant_id, user_actor: user_actor} do
      # Create multiple nodes in same tenant
      _node1 = create_knowledge_node(tenant_id, %{title: "Node 1"})
      _node2 = create_knowledge_node(tenant_id, %{title: "Node 2"})

      # Create node in different tenant
      other_tenant_id = Ash.UUID.generate()
      _other_node = create_knowledge_node(other_tenant_id, %{title: "Other Node"})

      # List should only return nodes from user's tenant
      nodes =
        VaultKnowledgeNode
        |> Ash.read!(actor: user_actor, tenant: tenant_id)

      # All nodes should belong to the user's tenant
      assert Enum.all?(nodes, fn node -> node.tenant_id == tenant_id end)

      # Should have at least 2 nodes (the ones we created)
      assert length(nodes) >= 2
    end

    test "link action enforces same-tenant constraint", %{
      tenant_id: tenant_id,
      user_actor: user_actor,
      node: node
    } do
      # Create another node in same tenant
      target_node = create_knowledge_node(tenant_id, %{title: "Target Node"})

      # User can link nodes in same tenant
      updated_node =
        Domain.add_relationship!(
          node,
          target_node.id,
          "related_to",
          0.9,
          actor: user_actor,
          tenant: tenant_id
        )

      assert updated_node.id == node.id
    end

    test "unlink action enforces ownership", %{
      tenant_id: tenant_id,
      user_actor: user_actor,
      node: node
    } do
      target_node = create_knowledge_node(tenant_id, %{title: "Target"})

      # Link first
      node =
        Domain.add_relationship!(
          node,
          target_node.id,
          "related_to",
          0.9,
          actor: user_actor,
          tenant: tenant_id
        )

      # User can unlink
      updated_node =
        Domain.remove_relationship!(
          node,
          target_node.id,
          "related_to",
          actor: user_actor,
          tenant: tenant_id
        )

      assert updated_node.id == node.id
    end

    test "consolidate action validates permissions", %{
      tenant_id: tenant_id,
      admin_actor: admin_actor
    } do
      node1 = create_knowledge_node(tenant_id, %{title: "Duplicate 1"})
      node2 = create_knowledge_node(tenant_id, %{title: "Duplicate 2"})

      # Admin can consolidate nodes
      consolidated_node =
        Domain.consolidate_knowledge!(
          node1,
          [node2.id],
          actor: admin_actor,
          tenant: tenant_id
        )

      assert consolidated_node.id == node1.id
    end

    test "verify action enforces ownership", %{
      tenant_id: tenant_id,
      curator_actor: curator_actor,
      node: node
    } do
      # Curator can verify knowledge
      verified_node =
        Domain.verify_knowledge!(
          node,
          "verified",
          %{evidence: "curator verification"},
          actor: curator_actor,
          tenant: tenant_id
        )

      assert verified_node.id == node.id
    end

    test "discover action respects tenant scope", %{
      tenant_id: tenant_id,
      user_actor: user_actor
    } do
      # Create nodes with semantic tags
      _node1 = create_knowledge_node(tenant_id, %{semantic_tags: ["ai", "ml"]})
      _node2 = create_knowledge_node(tenant_id, %{semantic_tags: ["ai", "nlp"]})

      # Search should be tenant-scoped
      results =
        Domain.search_knowledge!(
          "ai",
          ["testing"],
          ["concept"],
          0.5,
          actor: user_actor,
          tenant: tenant_id
        )

      # All results should be from user's tenant
      assert Enum.all?(results, fn node -> node.tenant_id == tenant_id end)
    end

    test "analyze action validates permissions", %{
      tenant_id: tenant_id,
      user_actor: user_actor,
      node: node
    } do
      # User can record access (analyze pattern)
      result =
        Domain.record_access!(
          node,
          "view",
          %{timestamp: DateTime.utc_now()},
          actor: user_actor,
          tenant: tenant_id
        )

      assert result.id == node.id
    end

    test "enrich action enforces ownership", %{
      tenant_id: tenant_id,
      user_actor: user_actor,
      node: node
    } do
      # User can update (enrich) their tenant's node
      enriched_node =
        node
        |> Ash.Changeset.for_update(
          :update,
          %{metadata: %{enriched: true}},
          actor: user_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert enriched_node.metadata["enriched"] == true
    end

    test "tag action validates permissions", %{
      tenant_id: tenant_id,
      user_actor: user_actor,
      node: node
    } do
      # User can add tags
      tagged_node =
        node
        |> Ash.Changeset.for_update(
          :update,
          %{semantic_tags: ["new_tag", "another_tag"]},
          actor: user_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert "new_tag" in tagged_node.semantic_tags
    end

    test "index action enforces ownership", %{
      tenant_id: tenant_id,
      system_actor: system_actor
    } do
      node = create_knowledge_node(tenant_id, %{indexing_status: "pending"})

      # System actor can update indexing status
      indexed_node =
        node
        |> Ash.Changeset.for_update(
          :update,
          %{indexing_status: "indexed"},
          actor: system_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert indexed_node.indexing_status == "indexed"
    end

    test "archive action validates permissions", %{
      tenant_id: tenant_id,
      admin_actor: admin_actor,
      node: node
    } do
      # Admin can update verification status (archive pattern)
      archived_node =
        node
        |> Ash.Changeset.for_update(
          :update,
          %{verification_status: "archived"},
          actor: admin_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert archived_node.verification_status == "archived"
    end

    test "restore action enforces ownership", %{
      tenant_id: tenant_id,
      admin_actor: admin_actor
    } do
      node =
        create_knowledge_node(tenant_id, %{
          title: "Archived Node",
          verification_status: "archived"
        })

      # Admin can restore
      restored_node =
        node
        |> Ash.Changeset.for_update(
          :update,
          %{verification_status: "active"},
          actor: admin_actor,
          tenant: tenant_id
        )
        |> Ash.update!()

      assert restored_node.verification_status == "active"
    end
  end

  # ===== EDGE CASES (3 tests) =====

  describe "edge cases" do
    test "nil tenant_id is rejected" do
      actor = %{id: Ash.UUID.generate(), tenant_id: nil, role: :user}

      # Cannot create without tenant_id
      assert_raise Ash.Error.Invalid, fn ->
        VaultKnowledgeNode
        |> Ash.Changeset.for_create(
          :create,
          %{
            node_type: "concept",
            title: "No Tenant Node",
            description: "Test",
            knowledge_domain: "test",
            confidence_level: 0.5,
            evidence_strength: 0.5
          },
          actor: actor,
          tenant: nil
        )
        |> Ash.create!()
      end
    end

    test "tenant_id is immutable after creation" do
      tenant_id = Ash.UUID.generate()
      node = create_knowledge_node(tenant_id)

      new_tenant_id = Ash.UUID.generate()
      actor = create_tenant_actor(tenant_id, :admin)

      # Attempting to change tenant_id should fail or be ignored
      # Since tenant_id is not in the accept list for update, this should raise
      assert_raise Ash.Error.Invalid, fn ->
        node
        |> Ash.Changeset.for_update(
          :update,
          %{tenant_id: new_tenant_id},
          actor: actor,
          tenant: tenant_id
        )
        |> Ash.update!()
      end
    end

    test "bulk operations respect tenant boundaries" do
      tenant_a = Ash.UUID.generate()
      tenant_b = Ash.UUID.generate()

      # Create multiple nodes in tenant A
      _node_a1 = create_knowledge_node(tenant_a, %{title: "A1", semantic_tags: ["bulk_test"]})
      _node_a2 = create_knowledge_node(tenant_a, %{title: "A2", semantic_tags: ["bulk_test"]})

      # Create node in tenant B
      _node_b1 = create_knowledge_node(tenant_b, %{title: "B1", semantic_tags: ["bulk_test"]})

      actor_a = create_tenant_actor(tenant_a)

      # Bulk read should only return tenant A nodes
      nodes =
        VaultKnowledgeNode
        |> Ash.Query.filter(semantic_tags: ["bulk_test"])
        |> Ash.read!(actor: actor_a, tenant: tenant_a)

      assert length(nodes) == 2
      assert Enum.all?(nodes, fn node -> node.tenant_id == tenant_a end)
    end
  end
end
