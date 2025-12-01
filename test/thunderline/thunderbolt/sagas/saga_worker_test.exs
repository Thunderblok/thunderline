defmodule Thunderline.Thunderbolt.Sagas.SagaWorkerTest do
  use Thunderline.DataCase, async: false
  use Oban.Testing, repo: Thunderline.Repo

  alias Thunderline.Thunderbolt.Sagas.SagaWorker
  alias Thunderline.Thunderbolt.Sagas.SagaState

  # Define a simple test saga
  defmodule TestSaga do
    use Reactor, extensions: [Reactor.Dsl]

    input :value
    input :correlation_id
    input :causation_id

    step :process do
      argument :value, input(:value)

      run fn %{value: value}, _context ->
        if value == "fail" do
          {:error, :test_failure}
        else
          {:ok, %{processed: true, value: value}}
        end
      end
    end

    return :process
  end

  defmodule SlowSaga do
    use Reactor, extensions: [Reactor.Dsl]

    input :delay_ms
    input :correlation_id
    input :causation_id

    step :slow_process do
      argument :delay_ms, input(:delay_ms)

      run fn %{delay_ms: delay_ms}, _context ->
        Process.sleep(delay_ms)
        {:ok, %{delayed: true}}
      end
    end

    return :slow_process
  end

  describe "enqueue/3" do
    test "enqueues a saga job" do
      correlation_id = Thunderline.UUID.v7()

      assert {:ok, job} =
               SagaWorker.enqueue(
                 TestSaga,
                 %{value: "test"},
                 correlation_id: correlation_id,
                 timeout_ms: 5000
               )

      assert job.worker == "Thunderline.Thunderbolt.Sagas.SagaWorker"
      assert job.queue == "sagas"

      assert job.args["saga_module"] ==
               "Elixir.Thunderline.Thunderbolt.Sagas.SagaWorkerTest.TestSaga"

      assert job.args["correlation_id"] == correlation_id
      assert job.args["timeout_ms"] == 5000
    end

    test "auto-generates correlation_id if not provided" do
      assert {:ok, job} = SagaWorker.enqueue(TestSaga, %{value: "test"})
      assert is_binary(job.args["correlation_id"])
    end
  end

  describe "perform/1" do
    test "successfully executes a saga" do
      correlation_id = Thunderline.UUID.v7()

      job = %Oban.Job{
        args: %{
          "saga_module" => "Elixir.Thunderline.Thunderbolt.Sagas.SagaWorkerTest.TestSaga",
          "inputs" => %{"value" => "success"},
          "correlation_id" => correlation_id,
          "timeout_ms" => 5000
        },
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = SagaWorker.perform(job)

      # Check saga state was created and completed
      assert {:ok, state} = Ash.get(SagaState, correlation_id)
      assert state.status == :completed
      assert state.output != nil
    end

    test "handles saga failure" do
      correlation_id = Thunderline.UUID.v7()

      job = %Oban.Job{
        args: %{
          "saga_module" => "Elixir.Thunderline.Thunderbolt.Sagas.SagaWorkerTest.TestSaga",
          "inputs" => %{"value" => "fail"},
          "correlation_id" => correlation_id,
          "timeout_ms" => 5000
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:error, :test_failure} = SagaWorker.perform(job)

      # Check saga state was created and marked as retrying
      assert {:ok, state} = Ash.get(SagaState, correlation_id)
      assert state.status == :retrying
      assert state.error != nil
    end

    test "marks saga as failed after max attempts" do
      correlation_id = Thunderline.UUID.v7()

      job = %Oban.Job{
        args: %{
          "saga_module" => "Elixir.Thunderline.Thunderbolt.Sagas.SagaWorkerTest.TestSaga",
          "inputs" => %{"value" => "fail"},
          "correlation_id" => correlation_id,
          "timeout_ms" => 5000
        },
        attempt: 3,
        max_attempts: 3
      }

      assert {:error, :test_failure} = SagaWorker.perform(job)

      # Check saga state is marked as failed (not retrying)
      assert {:ok, state} = Ash.get(SagaState, correlation_id)
      assert state.status == :failed
    end

    test "handles timeout" do
      correlation_id = Thunderline.UUID.v7()

      job = %Oban.Job{
        args: %{
          "saga_module" => "Elixir.Thunderline.Thunderbolt.Sagas.SagaWorkerTest.SlowSaga",
          "inputs" => %{"delay_ms" => "5000"},
          "correlation_id" => correlation_id,
          "timeout_ms" => 100
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:error, :timeout} = SagaWorker.perform(job)

      # Check saga state was marked as retrying with timeout error
      assert {:ok, state} = Ash.get(SagaState, correlation_id)
      assert state.status == :retrying
    end
  end

  describe "timeout/1" do
    test "returns saga-specific timeout" do
      job = %Oban.Job{
        args: %{
          "timeout_ms" => 10_000
        }
      }

      assert SagaWorker.timeout(job) == 10_000
    end

    test "returns default timeout when not specified" do
      job = %Oban.Job{args: %{}}

      assert SagaWorker.timeout(job) == 60_000
    end
  end
end
