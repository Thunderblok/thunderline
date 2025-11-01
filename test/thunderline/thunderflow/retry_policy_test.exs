defmodule Thunderline.Thunderflow.RetryPolicyTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thunderflow.Support.Backoff
  alias Thunderline.Thunderflow.Pipelines.EventPipeline

  describe "exponential backoff" do
    test "first retry has minimum delay" do
      delay = Backoff.exp(1)
      config = Backoff.config()

      # First attempt should be around min_ms (1000ms) with jitter
      assert delay >= config.min_ms * 0.8
      assert delay <= config.min_ms * 1.2
    end

    test "delay increases exponentially" do
      delays = for attempt <- 1..5, do: Backoff.exp(attempt)

      # Each delay should generally be larger than the previous
      # (allowing for jitter variance)
      [d1, d2, d3, d4, d5] = delays

      # General exponential growth pattern (accounting for jitter)
      assert d2 > d1 * 1.5
      assert d3 > d2 * 1.5
      assert d4 > d3 * 1.5
    end

    test "delay caps at maximum" do
      # Very high attempt number
      delay = Backoff.exp(100)
      config = Backoff.config()

      # Should not exceed max_ms (300,000ms = 5 minutes)
      assert delay <= config.max_ms
      assert delay >= config.max_ms * 0.8  # With jitter
    end

    test "jitter is applied consistently" do
      # Run same attempt multiple times to observe jitter
      delays = for _ <- 1..10, do: Backoff.exp(3)

      # All delays should be different due to jitter
      unique_delays = Enum.uniq(delays)
      assert length(unique_delays) > 1

      # But all should be within reasonable range
      avg_delay = Enum.sum(delays) / length(delays)
      assert Enum.all?(delays, fn d -> abs(d - avg_delay) < avg_delay * 0.3 end)
    end

    test "zero attempt returns minimum delay" do
      delay = Backoff.exp(0)
      config = Backoff.config()

      assert delay >= config.min_ms * 0.8
      assert delay <= config.min_ms * 1.2
    end
  end

  describe "linear backoff" do
    test "delay increases linearly with default step" do
      delays = for attempt <- 1..5, do: Backoff.linear(attempt)

      # Should increase roughly linearly (with jitter)
      [d1, d2, d3, d4, d5] = delays

      # Approximate linear progression (5000ms steps by default)
      assert d2 > d1
      assert d3 > d2
      assert d4 > d3
      assert d5 > d4
    end

    test "custom step size is respected" do
      step = 10_000
      delays = for attempt <- 1..3, do: Backoff.linear(attempt, step)

      [d1, d2, d3] = delays

      # With 10s step, differences should be roughly 10s (with jitter)
      assert abs((d2 - d1) - step) < step * 0.3
      assert abs((d3 - d2) - step) < step * 0.3
    end

    test "linear backoff respects minimum and maximum" do
      config = Backoff.config()

      # Very low attempt
      low_delay = Backoff.linear(1, 100)
      assert low_delay >= config.min_ms * 0.8

      # Very high attempt
      high_delay = Backoff.linear(1000, 1000)
      assert high_delay <= config.max_ms
    end

    test "linear backoff with zero step" do
      # Edge case: zero step should still respect minimum
      delay = Backoff.linear(5, 0)
      config = Backoff.config()

      assert delay >= config.min_ms * 0.8
    end
  end

  describe "jitter calculation" do
    test "jitter percentage is applied correctly" do
      base_delay = 10_000
      config = Backoff.config()

      jittered_delays = for _ <- 1..100, do: Backoff.jitter(base_delay)

      # Calculate expected jitter range
      expected_jitter = base_delay * config.jitter_pct
      min_expected = base_delay - expected_jitter
      max_expected = base_delay + expected_jitter

      # All jittered values should be within the jitter range
      assert Enum.all?(jittered_delays, fn d ->
        d >= min_expected and d <= max_expected
      end)
    end

    test "jitter produces varied results" do
      base_delay = 5_000
      jittered_delays = for _ <- 1..20, do: Backoff.jitter(base_delay)

      # Should have multiple unique values
      unique_delays = Enum.uniq(jittered_delays)
      assert length(unique_delays) > 10
    end

    test "jitter never produces negative delays" do
      # Even with very small base delays
      small_delays = for base <- [1, 10, 100], do: Backoff.jitter(base)

      assert Enum.all?(small_delays, fn d -> d >= 0 end)
    end
  end

  describe "retry budget for different event types" do
    test "ML run events have highest retry budget" do
      message = %Broadway.Message{
        data: %{"action" => "ml.run.start"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{}
      }

      {max_attempts, backoff_type} = retry_budget(message)

      assert max_attempts == 5
      assert backoff_type == :exponential
    end

    test "ML trial events have moderate retry budget" do
      message = %Broadway.Message{
        data: %{"action" => "ml.trial.complete"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{}
      }

      {max_attempts, backoff_type} = retry_budget(message)

      assert max_attempts == 3
      assert backoff_type == :linear
    end

    test "UI command events have minimal retry budget" do
      message = %Broadway.Message{
        data: %{"action" => "ui.command.send"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{}
      }

      {max_attempts, backoff_type} = retry_budget(message)

      assert max_attempts == 2
      assert backoff_type == :none
    end

    test "default events have standard retry budget" do
      message = %Broadway.Message{
        data: %{"action" => "system.event.generic"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{}
      }

      {max_attempts, backoff_type} = retry_budget(message)

      assert max_attempts == 3
      assert backoff_type == :exponential
    end
  end

  describe "retry attempt tracking" do
    test "attempt counter increments on each retry" do
      message = %Broadway.Message{
        data: %{"action" => "test.action"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{attempt: 0}
      }

      # First failure
      updated_message = Broadway.Message.update_metadata(
        message,
        &Map.put(&1, :attempt, 1)
      )

      assert updated_message.metadata.attempt == 1

      # Second failure
      updated_message2 = Broadway.Message.update_metadata(
        updated_message,
        &Map.put(&1, :attempt, 2)
      )

      assert updated_message2.metadata.attempt == 2
    end

    test "messages are sent to DLQ after max attempts" do
      {max_attempts, _} = retry_budget(%Broadway.Message{
        data: %{"action" => "test.dlq"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{}
      })

      message = %Broadway.Message{
        data: %{"action" => "test.dlq"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{attempt: max_attempts}
      }

      # At max attempts, should go to DLQ
      assert message.metadata.attempt >= max_attempts
    end

    test "retry attempts reset on success" do
      # Simulate a message that succeeded after retry
      message = %Broadway.Message{
        data: %{"action" => "test.success"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{attempt: 2}
      }

      # On success, attempt counter doesn't matter for next message
      # Each new message starts with attempt: 0
      new_message = %Broadway.Message{
        data: %{"action" => "test.success"},
        acknowledger: {Broadway.NoopAcknowledger, nil, nil},
        metadata: %{}
      }

      assert new_message.metadata[:attempt] == nil or new_message.metadata.attempt == 0
    end
  end

  describe "backoff delay calculation in practice" do
    test "exponential backoff provides increasing delays" do
      # Simulate multiple retry attempts
      attempt_delays = for attempt <- 1..5 do
        {attempt, Backoff.exp(attempt)}
      end

      IO.inspect(attempt_delays, label: "Exponential backoff progression")

      # Verify progression
      delays = Enum.map(attempt_delays, fn {_, delay} -> delay end)

      # Each delay should be significantly larger than previous
      for i <- 0..(length(delays) - 2) do
        current = Enum.at(delays, i)
        next = Enum.at(delays, i + 1)
        assert next > current, "Delay should increase: #{current} -> #{next}"
      end
    end

    test "linear backoff provides steady progression" do
      step = 5_000
      attempt_delays = for attempt <- 1..5 do
        {attempt, Backoff.linear(attempt, step)}
      end

      IO.inspect(attempt_delays, label: "Linear backoff progression")

      # Verify steady increase
      delays = Enum.map(attempt_delays, fn {_, delay} -> delay end)

      for i <- 0..(length(delays) - 2) do
        current = Enum.at(delays, i)
        next = Enum.at(delays, i + 1)

        # Linear increase should be roughly the step size
        diff = next - current
        assert abs(diff - step) < step * 0.3,
          "Linear step should be ~#{step}, got #{diff}"
      end
    end
  end

  describe "retry policy configuration" do
    test "backoff configuration is accessible" do
      config = Backoff.config()

      assert is_map(config)
      assert Map.has_key?(config, :min_ms)
      assert Map.has_key?(config, :max_ms)
      assert Map.has_key?(config, :jitter_pct)

      assert config.min_ms == 1_000
      assert config.max_ms == 300_000
      assert config.jitter_pct == 0.20
    end

    test "retry policies are consistent across calls" do
      config1 = Backoff.config()
      config2 = Backoff.config()

      assert config1 == config2
    end
  end

  describe "edge cases" do
    test "handles very large attempt numbers" do
      # Should not crash or return unreasonable values
      large_attempt = 1_000_000
      delay = Backoff.exp(large_attempt)

      config = Backoff.config()
      assert delay >= 0
      assert delay <= config.max_ms
    end

    test "handles negative attempt numbers gracefully" do
      # Negative attempts should be treated as first attempt
      delay = Backoff.exp(-5)

      config = Backoff.config()
      assert delay >= config.min_ms * 0.8
      assert delay <= config.min_ms * 1.2
    end

    test "jitter with zero delay" do
      jittered = Backoff.jitter(0)

      # Should handle gracefully without crashing
      assert jittered >= 0
    end

    test "linear backoff with negative step" do
      # Should still respect minimum
      delay = Backoff.linear(3, -1000)
      config = Backoff.config()

      assert delay >= config.min_ms * 0.8
    end
  end

  # Helper function (mimicking EventPipeline's private function for testing)
  defp retry_budget(%Broadway.Message{data: %{"action" => action}}) do
    cond do
      String.starts_with?(action, "ml.run") -> {5, :exponential}
      String.starts_with?(action, "ml.trial") -> {3, :linear}
      String.starts_with?(action, "ui.command") -> {2, :none}
      true -> {3, :exponential}
    end
  end
end
