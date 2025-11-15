defmodule ThunderlineWeb.AutomataLiveTest do
  use ThunderlineWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @moduletag :automata
  @moduletag :skip

  # Helper to extract assigns safely from a LiveView pid
  defp view_assigns(view) do
    # Using :sys.get_state is a bit internal, but acceptable here until we extract logic
    state = :sys.get_state(view.pid)
    state.socket.assigns
  end

  test "automata initializes and evolves one generation under rule 30", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ThunderlineWeb.AutomataLive)

    assigns = view_assigns(view)
    assert assigns.pattern_buffer == []
    assert assigns.generation == 0
    assert assigns.active_rule == :rule_30

    # Start simulation
    view |> element("button[phx-click=toggle_simulation]") |> render_click()

    # Manually trigger the generation tick (we don't want to wait for Process.send_after in tests)
    send(view.pid, :next_generation)
    # Allow the handle_info to run
    Process.sleep(10)

    assigns = view_assigns(view)

    # After first generation there should be exactly 1 row
    assert length(assigns.pattern_buffer) == 1
    row = hd(assigns.pattern_buffer)
    assert length(row) == 80

    center = div(80, 2)
    # Initial row should have a single 1 in the center, others 0
    ones_positions =
      Enum.with_index(row) |> Enum.filter(fn {v, _i} -> v == 1 end) |> Enum.map(&elem(&1, 1))

    assert ones_positions == [center]

    # Trigger a second generation
    send(view.pid, :next_generation)
    Process.sleep(10)

    assigns = view_assigns(view)
    assert length(assigns.pattern_buffer) == 2
    [first_row, second_row] = assigns.pattern_buffer

    # First row unchanged
    assert first_row == row

    # Rule 30 applied to a single center 1 should produce three adjacent 1s centered (positions center-1, center, center+1)
    ones_positions_second =
      Enum.with_index(second_row)
      |> Enum.filter(fn {v, _i} -> v == 1 end)
      |> Enum.map(&elem(&1, 1))

    assert ones_positions_second == [center - 1, center, center + 1]
  end
end
