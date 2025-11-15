defmodule Thunderline.Thunderchief.OrchestratorTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderchief.Orchestrator

  setup do
    original = System.get_env("TL_ENABLE_REACTOR")
    System.delete_env("TL_ENABLE_REACTOR")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("TL_ENABLE_REACTOR")
        value -> System.put_env("TL_ENABLE_REACTOR", value)
      end
    end)

    :ok
  end

  describe "dispatch_event/2" do
    test "falls back to processor when reactor disabled" do
      event = %{"type" => "test_dispatch", "payload" => %{"foo" => "bar"}}

      assert {:ok, :acked} = Orchestrator.dispatch_event(event)
    end

    test "returns error for invalid payload" do
      assert {:error, {:invalid_event, :nope}} = Orchestrator.dispatch_event(:nope)
    end
  end

  describe "enqueue_domain_job/1" do
    test "returns job changeset for known domain" do
      job = %{"domain" => "thunderbolt", "event" => %{}}

      assert %Ecto.Changeset{valid?: true, changes: %{args: %{"domain" => "thunderbolt"}}} =
               Orchestrator.enqueue_domain_job(job)
    end

    test "returns nil when domain missing" do
      assert Orchestrator.enqueue_domain_job(%{"event" => %{}}) == nil
    end
  end
end
