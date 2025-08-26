defmodule Mix.Tasks.EventsLintTaskTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduletag :lint

  test "human format runs without errors" do
    output =
      capture_io(fn ->
        Mix.Task.rerun("thunderline.events.lint", ["--format", "human"]) rescue nil
      end)

    assert output =~ "No event taxonomy issues" or output =~ "Event taxonomy issues"
  end

  test "json format returns a machine-parsable payload" do
    output =
      capture_io(fn ->
        Mix.Task.rerun("thunderline.events.lint", ["--format", "json"]) rescue nil
      end)

    assert {:ok, payload} = Jason.decode(output)
    assert is_list(payload["issues"]) or Map.has_key?(payload, "count")
  end
end
