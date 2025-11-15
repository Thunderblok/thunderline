defmodule Thunderline.Thunderblock.RetentionTest do
  use Thunderline.DataCase, async: false
  doctest Thunderline.Thunderblock.Retention

  alias Ash
  alias Thunderline.Repo
  alias Thunderline.Thunderblock.Retention
  alias Thunderline.Thunderblock.Resources.RetentionPolicy

  @seed_key {:thunderline, :thunderblock_retention_defaults}

  setup do
    Repo.query!("DELETE FROM thunderblock_retention_policies")
    :persistent_term.erase(@seed_key)
    :ok
  end

  describe "ensure_defaults!/0" do
    test "creates baseline policies" do
      :ok = Retention.ensure_defaults!()

      {:ok, %RetentionPolicy{} = policy} = Retention.get(:event_log)
      assert policy.scope_type == :global
      assert policy.action == :delete
      assert policy.ttl_seconds == 30 * 86_400
      assert policy.grace_seconds == 2 * 86_400

      {:ok, policies} = RetentionPolicy |> Ash.read()
      assert length(policies) >= length(Retention.defaults())
    end
  end

  describe "scope semantics" do
    setup do
      Retention.ensure_defaults!()
      :ok
    end

    test "global lookups return policies with nil scope_id" do
      assert {:ok, %RetentionPolicy{} = policy} = Retention.get(:event_log, scope: :global)
      assert policy.scope_type == :global
      assert is_nil(policy.scope_id)
    end

    test "returns scoped override when present" do
      dataset_id = Ecto.UUID.generate()

      {:ok, %RetentionPolicy{} = override} =
        RetentionPolicy
        |> Ash.Changeset.for_create(:define, %{
          resource: :artifact,
          scope_type: :dataset,
          scope_id: dataset_id,
          ttl_seconds: 604_800,
          keep_versions: 3,
          action: :archive,
          grace_seconds: 86_400
        })
        |> Ash.create()

      assert {:ok, {policy, :exact}} = Retention.effective(:artifact, {:dataset, dataset_id})
      assert policy.id == override.id
      assert policy.keep_versions == 3
    end

    test "falls back to global when scoped policy missing" do
      dataset_id = Ecto.UUID.generate()
      assert {:ok, {policy, :fallback}} = Retention.effective(:vector, {:dataset, dataset_id})
      assert policy.scope_type == :global
      refute policy.scope_id
    end

    test "matches org scoped policies when defined" do
      tenant_id = Ecto.UUID.generate()

      {:ok, %RetentionPolicy{} = scoped} =
        RetentionPolicy
        |> Ash.Changeset.for_create(:define, %{
          resource: :event_log,
          scope_type: :tenant,
          scope_id: tenant_id,
          ttl_seconds: 604_800,
          action: :delete,
          grace_seconds: 0
        })
        |> Ash.create()

      assert {:ok, %RetentionPolicy{} = policy} =
               Retention.get(:event_log, scope: {:tenant, tenant_id})

      assert policy.id == scoped.id
      assert policy.scope_type == :tenant
      assert policy.scope_id == tenant_id
    end
  end

  describe "ensure_defaults! idempotency" do
    test "does not error when called repeatedly" do
      assert :ok = Retention.ensure_defaults!()
      assert :ok = Retention.ensure_defaults!()

      {:ok, policy} = Retention.get(:cache)
      assert policy.scope_type == :global
      assert policy.ttl_seconds == 24 * 3_600
    end
  end
end
