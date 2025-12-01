defmodule Thunderline.Thunderflow.DomainProcessorTest do
  @moduledoc """
  Tests for the DomainProcessor behaviour and __using__ macro.

  HC-12: Validates that the behaviour correctly eliminates Broadway boilerplate
  while providing proper telemetry, DLQ handling, and extensibility.
  """

  use ExUnit.Case, async: true

  alias Thunderline.Thunderflow.DomainProcessor
  alias Thunderline.Event

  # --- Test Module Using the Behaviour ---

  defmodule TestPipeline do
    @moduledoc false
    use Thunderline.Thunderflow.DomainProcessor,
      name: :test_pipeline,
      queue: :test_queue,
      batchers: [:events, :critical],
      batch_size: 10,
      batch_timeout: 500,
      concurrency: 2

    @impl Thunderline.Thunderflow.DomainProcessor
    def process_event(%{type: :critical} = event, _context) do
      {:ok, Map.put(event, :processed, true), :critical}
    end

    def process_event(%{type: :error} = _event, _context) do
      {:error, :simulated_error}
    end

    def process_event(%{type: :exception}, _context) do
      raise "simulated exception"
    end

    def process_event(event, _context) do
      {:ok, Map.put(event, :processed, true), :events}
    end

    @impl Thunderline.Thunderflow.DomainProcessor
    def handle_event_batch(:events, messages, _batch_info, _context) do
      # Simulate batch processing
      messages
    end

    def handle_event_batch(:critical, messages, _batch_info, _context) do
      # Simulate critical batch processing
      messages
    end
  end

  defmodule CustomConfigPipeline do
    @moduledoc false
    use Thunderline.Thunderflow.DomainProcessor,
      name: :custom_config_pipeline,
      batchers: [:fast, :slow]

    @impl Thunderline.Thunderflow.DomainProcessor
    def process_event(event, _context) do
      {:ok, event, :fast}
    end

    @impl Thunderline.Thunderflow.DomainProcessor
    def handle_event_batch(_batcher, messages, _batch_info, _context) do
      messages
    end

    # Override default batcher config via defoverridable
    def do_batcher_config(:fast), do: [batch_size: 5, batch_timeout: 100]
    def do_batcher_config(:slow), do: [batch_size: 50, batch_timeout: 5_000]
    def do_batcher_config(_), do: []

    # Override default processor config via defoverridable
    def do_processor_config, do: [concurrency: 8, max_demand: 20]

    @impl Thunderline.Thunderflow.DomainProcessor
    def telemetry_prefix, do: [:custom, :pipeline]
  end

  # --- Behaviour Definition Tests ---

  describe "behaviour callbacks" do
    test "defines required callbacks" do
      callbacks = Thunderline.Thunderflow.DomainProcessor.behaviour_info(:callbacks)

      assert {:process_event, 2} in callbacks
      assert {:handle_event_batch, 4} in callbacks
    end

    test "defines optional callbacks" do
      optional = Thunderline.Thunderflow.DomainProcessor.behaviour_info(:optional_callbacks)

      assert {:telemetry_prefix, 0} in optional
    end
  end

  # --- __using__ Macro Tests ---

  describe "__using__ macro" do
    test "creates child_spec/1" do
      spec = TestPipeline.child_spec([])

      assert spec.id == TestPipeline
      assert spec.type == :supervisor
      assert spec.restart == :permanent
      assert {TestPipeline, :start_link, [[]]} = spec.start
    end

    test "exposes telemetry prefix" do
      assert TestPipeline.__telemetry_prefix__() == [
               :thunderline,
               :domain_processor,
               :test_pipeline
             ]
    end

    test "custom telemetry prefix works" do
      assert CustomConfigPipeline.telemetry_prefix() == [:custom, :pipeline]
    end
  end

  # --- normalize_event/1 Tests ---

  describe "normalize_event/1" do
    test "passes through Event structs unchanged" do
      {:ok, event} =
        Event.new(%{
          name: "system.event.test",
          type: :system,
          source: :flow,
          payload: %{foo: "bar"}
        })

      assert {:ok, ^event} = DomainProcessor.normalize_event(event)
    end

    test "converts map with atom keys to Event" do
      map = %{
        name: "system.event.test",
        type: :system,
        source: :flow,
        payload: %{data: 123}
      }

      assert {:ok, %Event{} = event} = DomainProcessor.normalize_event(map)
      assert event.name == "system.event.test"
      assert event.type == :system
      assert event.payload == %{data: 123}
    end

    test "converts map with string keys to Event" do
      map = %{
        "name" => "system.string.event",
        "type" => "string_type",
        "source" => "flow",
        "payload" => %{"key" => "value"}
      }

      assert {:ok, %Event{} = event} = DomainProcessor.normalize_event(map)
      assert event.name == "system.string.event"
    end

    test "handles missing fields with defaults" do
      map = %{name: "system.minimal.event"}

      assert {:ok, %Event{} = event} = DomainProcessor.normalize_event(map)
      assert event.name == "system.minimal.event"
      assert event.type == :unknown
      assert event.source == :unknown
      assert event.payload == %{}
    end

    test "returns error for invalid input" do
      assert {:error, {:invalid_event, "not a map"}} =
               DomainProcessor.normalize_event("not a map")

      assert {:error, {:invalid_event, nil}} = DomainProcessor.normalize_event(nil)
    end
  end

  # --- broadcast/2 Tests ---

  describe "broadcast/2" do
    test "broadcasts to PubSub topic" do
      # Subscribe to topic
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "test:broadcast")

      # Broadcast event
      event = %{id: "123", type: :test}
      assert :ok = DomainProcessor.broadcast("test:broadcast", event)

      # Verify receipt
      assert_receive {:domain_event, ^event}, 1000
    end
  end

  # --- Configuration Tests ---

  describe "configuration" do
    test "module attributes are set from options" do
      # We can't directly access module attributes, but we can verify behavior
      # through the telemetry prefix which uses @__dp_name
      assert TestPipeline.__telemetry_prefix__() == [
               :thunderline,
               :domain_processor,
               :test_pipeline
             ]
    end

    test "custom batcher_config is called via do_batcher_config" do
      # CustomConfigPipeline defines custom batcher configs
      # We verify this by checking the function exists and returns expected values
      assert CustomConfigPipeline.do_batcher_config(:fast) == [batch_size: 5, batch_timeout: 100]

      assert CustomConfigPipeline.do_batcher_config(:slow) == [
               batch_size: 50,
               batch_timeout: 5_000
             ]
    end

    test "custom processor_config is called via do_processor_config" do
      assert CustomConfigPipeline.do_processor_config() == [concurrency: 8, max_demand: 20]
    end
  end

  # --- process_event Routing Tests ---

  describe "process_event routing" do
    test "routes to correct batcher based on return value" do
      # Normal event -> :events batcher
      assert {:ok, %{type: :normal, processed: true}, :events} =
               TestPipeline.process_event(%{type: :normal}, %{})

      # Critical event -> :critical batcher
      assert {:ok, %{type: :critical, processed: true}, :critical} =
               TestPipeline.process_event(%{type: :critical}, %{})
    end

    test "returns error tuple on failure" do
      assert {:error, :simulated_error} =
               TestPipeline.process_event(%{type: :error}, %{})
    end
  end

  # --- Integration Smoke Test ---

  describe "integration" do
    @tag :integration
    test "pipeline can be started and stopped" do
      # Start the pipeline
      assert {:ok, pid} = TestPipeline.start_link([])
      assert Process.alive?(pid)

      # Stop it gracefully
      Broadway.stop(TestPipeline)

      # Give it time to terminate
      Process.sleep(100)
      refute Process.whereis(TestPipeline)
    end
  end
end
