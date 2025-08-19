defmodule Thunderline.Thunderflow.Observability.RingBufferTest do
  use ExUnit.Case, async: true
  alias Thunderline.Thunderflow.Observability.RingBuffer

  test "push & recent ordering respects limit" do
    {:ok, pid} = start_supervised({RingBuffer, [name: :rb_test, limit: 5]})
    Enum.each(1..10, fn i -> RingBuffer.push({:val, i}, :rb_test) end)
    # Allow casts to flush
    Process.sleep(10)
    recent = RingBuffer.recent(10, :rb_test)
    assert length(recent) == 5
    # Newest first, values 10..6
    values = Enum.map(recent, fn {_ts, {:val, v}} -> v end)
    assert values == [10,9,8,7,6]
    assert Process.alive?(pid)
  end
end
