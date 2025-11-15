defmodule Thunderline.Thunderflow.RetryPolicyTest do
  use Thunderline.DataCase, async: true

  alias Broadway.Message
  alias Thunderline.Thunderflow.RetryPolicy
  alias Thunderline.Thunderflow.Support.Backoff

  @ml_run_event %{"action" => "ml.run.start"}
  @ml_trial_event %{"action" => "ml.trial.complete"}
  @ui_command_event %{"action" => "ui.command.send"}
  @default_event %{"action" => "system.health.ok"}

  defp build_message(data) do
    %Message{
      data: data,
      acknowledger: {Broadway.NoopAcknowledger, :ok, :ok},
      metadata: %{}
    }
  end

  describe "for_event/1" do
    test "returns exponential policy with five attempts for ml.run.* events" do
      policy = RetryPolicy.for_event(@ml_run_event)

      assert %RetryPolicy{
               category: :ml_run,
               max_attempts: 5,
               strategy: :exponential
             } = policy
    end

    test "returns exponential policy with three attempts for ml.trial.* events" do
      policy = RetryPolicy.for_event(@ml_trial_event)

      assert %RetryPolicy{
               category: :ml_trial,
               max_attempts: 3,
               strategy: :exponential
             } = policy
    end

    test "returns none strategy for ui.command.* events" do
      policy = RetryPolicy.for_event(@ui_command_event)

      assert %RetryPolicy{
               category: :ui_command,
               max_attempts: 2,
               strategy: :none
             } = policy
    end

    test "returns default exponential policy for other events" do
      policy = RetryPolicy.for_event(@default_event)

      assert %RetryPolicy{
               category: :default,
               max_attempts: 3,
               strategy: :exponential
             } = policy
    end

    test "accepts atom names and message structs" do
      message = build_message(%{"action" => "ml.run.finished"})

      assert %RetryPolicy{category: :ml_run} = RetryPolicy.for_event("ml.run.finished")
      assert %RetryPolicy{category: :ml_run} = RetryPolicy.for_message(message)
    end
  end

  describe "budget/1" do
    test "returns tuple for compatibility" do
      assert {5, :exponential} = RetryPolicy.budget("ml.run.completed")
      assert {3, :exponential} = RetryPolicy.budget(%{"name" => "ml.trial.succeeded"})
      assert {2, :none} = RetryPolicy.budget(@ui_command_event)
      assert {3, :exponential} = RetryPolicy.budget(%{})
    end
  end

  describe "next_delay/2" do
    test "returns exponential delay within jitter bounds" do
      attempt = 3
      policy = RetryPolicy.for_event(@ml_run_event)
      delay = RetryPolicy.next_delay(policy, attempt)

      config = Backoff.config()
      base =
        config.min_ms
        |> Kernel.*(:math.pow(2, attempt - 1))
        |> min(config.max_ms)

      jitter = base * config.jitter_pct
      lower = max(0, floor(base - jitter))
      upper = ceil(base + jitter)

      assert delay >= lower
      assert delay <= upper
    end

    test "returns zero for none strategy" do
      policy = RetryPolicy.for_event(@ui_command_event)

      assert RetryPolicy.next_delay(policy, 1) == 0
      assert RetryPolicy.next_delay(policy, 10) == 0
    end
  end

  describe "exhausted?/2 and retry_allowed?/2" do
    test "exhausted when attempts reach budget" do
      policy = RetryPolicy.for_event(@ml_trial_event)

      refute RetryPolicy.exhausted?(policy, 1)
      refute RetryPolicy.exhausted?(policy, 2)
      assert RetryPolicy.exhausted?(policy, 3)
      refute RetryPolicy.retry_allowed?(policy, 3)
    end

    test "UI command policy exhausts after two attempts" do
      policy = RetryPolicy.for_event(@ui_command_event)

      refute RetryPolicy.exhausted?(policy, 1)
      assert RetryPolicy.exhausted?(policy, 2)
    end
  end

  describe "strategy/1" do
    test "returns strategy for policy struct and raw events" do
      policy = RetryPolicy.for_event(@ml_run_event)

      assert RetryPolicy.strategy(policy) == :exponential
      assert RetryPolicy.strategy(@ui_command_event) == :none
    end
  end
end
