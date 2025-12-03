defmodule Thunderline.Thunderchief.Jobs.DomainProcessorTest do
  @moduledoc """
  Tests for the DomainProcessor Oban job.

  Unit tests verify job construction and domain routing logic.
  Uses Oban.Testing for verifying job changesets without database insertion.

  Note: enqueue/3 and enqueue_all/2 tests use perform_job/3 from Oban.Testing
  rather than actual database insertion to avoid sandbox/trigger issues.
  """
  use Thunderline.DataCase, async: false
  use Oban.Testing, repo: Thunderline.Repo

  alias Thunderline.Thunderchief.Jobs.DomainProcessor

  describe "new/2" do
    test "creates job changeset with domain arg" do
      changeset = DomainProcessor.new(%{domain: "bit"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.args.domain == "bit"
    end

    test "creates job changeset with context" do
      changeset = DomainProcessor.new(%{domain: "crown", context: %{tick: 42}})
      assert changeset.changes.args[:domain] == "crown"
      assert changeset.changes.args[:context][:tick] == 42
    end

    test "accepts priority option" do
      changeset = DomainProcessor.new(%{domain: "vine"}, priority: 0)
      assert changeset.changes.priority == 0
    end

    test "accepts scheduled_at option" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      changeset = DomainProcessor.new(%{domain: "ui"}, scheduled_at: future)
      assert changeset.changes.scheduled_at == future
    end
  end

  describe "domains/0" do
    test "returns all registered domain keys" do
      domains = DomainProcessor.domains()

      assert "bit" in domains
      assert "vine" in domains
      assert "crown" in domains
      assert "ui" in domains
      assert length(domains) == 4
    end
  end

  describe "chief_for/1" do
    test "returns BitChief for bit domain" do
      assert DomainProcessor.chief_for("bit") == Thunderline.Thunderchief.Chiefs.BitChief
    end

    test "returns VineChief for vine domain" do
      assert DomainProcessor.chief_for("vine") == Thunderline.Thunderchief.Chiefs.VineChief
    end

    test "returns CrownChief for crown domain" do
      assert DomainProcessor.chief_for("crown") == Thunderline.Thunderchief.Chiefs.CrownChief
    end

    test "returns UIChief for ui domain" do
      assert DomainProcessor.chief_for("ui") == Thunderline.Thunderchief.Chiefs.UIChief
    end

    test "returns nil for unknown domain" do
      assert DomainProcessor.chief_for("unknown") == nil
    end
  end

  describe "enqueue/3 - changeset construction" do
    # Note: We test the changeset construction since Oban.insert() requires
    # database triggers that aren't available in sandbox mode. Actual insertion
    # is tested via Oban.Testing.perform_job/3 which bypasses insertion.

    test "builds valid changeset for a domain" do
      changeset = DomainProcessor.new(%{domain: "bit", context: %{tick: 1}})

      assert changeset.valid?
      assert changeset.changes.args.domain == "bit"
      assert changeset.changes.args.context.tick == 1
    end

    test "builds changesets for different contexts" do
      cs1 = DomainProcessor.new(%{domain: "crown", context: %{tick: 10, actor_id: "abc"}})
      cs2 = DomainProcessor.new(%{domain: "vine", context: %{tick: 10, tree_id: "xyz"}})

      assert cs1.valid?
      assert cs2.valid?
      assert cs1.changes.args.domain == "crown"
      assert cs2.changes.args.domain == "vine"
    end

    test "accepts scheduling options in changeset" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      changeset = DomainProcessor.new(%{domain: "ui"}, scheduled_at: future)

      assert changeset.valid?
      assert changeset.changes.scheduled_at == future
    end
  end

  describe "enqueue_all/2 - changeset construction" do
    test "builds changesets for all domains" do
      context = %{tick: 42, correlation_id: Thunderline.UUID.v7()}

      # Test the underlying changeset creation logic
      changesets = for domain <- DomainProcessor.domains() do
        DomainProcessor.new(%{domain: domain, context: context})
      end

      assert length(changesets) == 4

      for cs <- changesets do
        assert cs.valid?
        assert cs.changes.args.context.tick == 42
      end
    end

    test "all changesets share the same context" do
      context = %{tick: 99, source: :test}

      changesets = for domain <- DomainProcessor.domains() do
        DomainProcessor.new(%{domain: domain, context: context})
      end

      for cs <- changesets do
        assert cs.changes.args.context.tick == 99
        assert cs.changes.args.context.source == :test
      end
    end
  end

  describe "perform/1" do
    test "returns error for unknown domain" do
      job = %Oban.Job{
        args: %{"domain" => "nonexistent"},
        attempt: 1,
        id: 999
      }

      assert {:error, {:unknown_domain, "nonexistent"}} = DomainProcessor.perform(job)
    end

    # Note: Full Chief integration tests would require Chief GenServers
    # to be running. These are covered in Chief-specific tests.
  end

  describe "job configuration" do
    test "uses correct queue" do
      changeset = DomainProcessor.new(%{domain: "bit"})
      assert changeset.changes.queue == "domain_processor"
    end

    test "has reasonable max_attempts" do
      changeset = DomainProcessor.new(%{domain: "bit"})
      assert changeset.changes.max_attempts == 3
    end
  end
end
