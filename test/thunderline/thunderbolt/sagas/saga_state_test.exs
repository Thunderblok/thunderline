defmodule Thunderline.Thunderbolt.Sagas.SagaStateTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thunderbolt.Sagas.SagaState

  describe "create/1" do
    test "creates saga state with required fields" do
      correlation_id = Thunderline.UUID.v7()

      attrs = %{
        id: correlation_id,
        saga_module: "Elixir.Thunderline.Thunderbolt.Sagas.TestSaga",
        status: :pending,
        inputs: %{email: "test@example.com"},
        attempt_count: 0
      }

      assert {:ok, state} = Ash.create(SagaState, attrs)
      assert state.id == correlation_id
      assert state.saga_module == "Elixir.Thunderline.Thunderbolt.Sagas.TestSaga"
      assert state.status == :pending
      assert state.inputs == %{email: "test@example.com"}
    end

    test "defaults status to pending" do
      attrs = %{
        id: Thunderline.UUID.v7(),
        saga_module: "Elixir.TestSaga",
        inputs: %{}
      }

      assert {:ok, state} = Ash.create(SagaState, attrs)
      assert state.status == :pending
    end
  end

  describe "status transitions" do
    setup do
      {:ok, state} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Elixir.TestSaga",
          status: :pending,
          inputs: %{}
        })

      {:ok, state: state}
    end

    test "mark_running increments attempt_count", %{state: state} do
      assert {:ok, updated} = Ash.update(state, %{}, action: :mark_running)
      assert updated.status == :running
      assert updated.attempt_count == 1
      assert updated.last_attempt_at != nil
    end

    test "mark_completed sets output and timestamp", %{state: state} do
      output = Jason.encode!(%{result: "success"})

      assert {:ok, updated} = Ash.update(state, %{output: output}, action: :mark_completed)
      assert updated.status == :completed
      assert updated.output == output
      assert updated.completed_at != nil
    end

    test "mark_failed sets error", %{state: state} do
      assert {:ok, updated} = Ash.update(state, %{error: "test error"}, action: :mark_failed)
      assert updated.status == :failed
      assert updated.error == "test error"
    end

    test "mark_halted sets checkpoint", %{state: state} do
      checkpoint = Jason.encode!(%{step: :validate})

      assert {:ok, updated} = Ash.update(state, %{checkpoint: checkpoint}, action: :mark_halted)
      assert updated.status == :halted
      assert updated.checkpoint == checkpoint
    end

    test "cancel sets status to cancelled", %{state: state} do
      assert {:ok, updated} = Ash.update(state, %{}, action: :cancel)
      assert updated.status == :cancelled
    end
  end

  describe "list_by_status/1" do
    test "filters sagas by status" do
      # Create sagas with different statuses
      {:ok, _pending} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Test",
          status: :pending,
          inputs: %{}
        })

      {:ok, _running} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Test",
          status: :running,
          inputs: %{}
        })

      {:ok, _failed} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Test",
          status: :failed,
          inputs: %{}
        })

      assert {:ok, pending_list} = SagaState.list_by_status(:pending)
      assert length(pending_list) == 1
      assert hd(pending_list).status == :pending

      assert {:ok, failed_list} = SagaState.list_by_status(:failed)
      assert length(failed_list) == 1
      assert hd(failed_list).status == :failed
    end
  end

  describe "list_by_module/1" do
    test "filters sagas by module name" do
      {:ok, _state1} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Elixir.UserSaga",
          status: :pending,
          inputs: %{}
        })

      {:ok, _state2} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Elixir.UserSaga",
          status: :completed,
          inputs: %{}
        })

      {:ok, _state3} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Elixir.OtherSaga",
          status: :pending,
          inputs: %{}
        })

      assert {:ok, user_sagas} = SagaState.list_by_module("Elixir.UserSaga")
      assert length(user_sagas) == 2
      assert Enum.all?(user_sagas, &(&1.saga_module == "Elixir.UserSaga"))
    end
  end

  describe "stale_sagas/1" do
    test "finds running sagas older than threshold" do
      # Create a "stale" saga with old timestamp
      old_time = DateTime.add(DateTime.utc_now(), -7200, :second)

      {:ok, stale_saga} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Test",
          status: :running,
          inputs: %{},
          last_attempt_at: old_time
        })

      # Create a fresh running saga
      {:ok, _fresh_saga} =
        Ash.create(SagaState, %{
          id: Thunderline.UUID.v7(),
          saga_module: "Test",
          status: :running,
          inputs: %{},
          last_attempt_at: DateTime.utc_now()
        })

      # Find sagas older than 1 hour (3600 seconds)
      assert {:ok, stale_list} = SagaState.find_stale(3600)
      assert length(stale_list) == 1
      assert hd(stale_list).id == stale_saga.id
    end
  end
end
