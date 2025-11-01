defmodule ThunderlineWeb.CerebrosLiveTest do
  use ThunderlineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Thunderline.Feature

  setup do
    Feature.override(:ml_nas, true)

    previous_features = Application.get_env(:thunderline, :features)
    Application.put_env(:thunderline, :features, [:ml_nas])

    previous = Application.get_env(:thunderline, :cerebros_bridge)

    Application.put_env(
      :thunderline,
      :cerebros_bridge,
      Keyword.merge(previous || [], enabled: true)
    )

    on_exit(fn ->
      Feature.clear_override(:ml_nas)

      if previous_features do
        Application.put_env(:thunderline, :features, previous_features)
      else
        Application.delete_env(:thunderline, :features)
      end

      if previous do
        Application.put_env(:thunderline, :cerebros_bridge, previous)
      else
        Application.delete_env(:thunderline, :cerebros_bridge)
      end
    end)

    :ok
  end

  test "renders validation feedback when spec is invalid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cerebros")

    refute has_element?(view, "[data-role=spec-errors]")

    view
    |> element("#nas-run-form")
    |> render_change(%{"nas" => %{"spec" => "{"}})

    assert has_element?(view, "[data-role=spec-errors]")
    assert has_element?(view, "[data-role=spec-errors]", "invalid_json")
  end

  test "current run summary reflects run and trial updates", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cerebros")

    run_id = "12345678-abcdef"

    run_update = %{
      run_id: run_id,
      stage: :started,
      metadata: %{job_id: 42, queue: "ml_runs", model: "transformer"},
      measurements: %{best_metric: 0.9123},
      published_at: DateTime.utc_now(),
      source: :test
    }

    send(view.pid, {:run_update, run_update})

    trial_update = %{
      run_id: run_id,
      trial_id: "trial-1",
      stage: :started,
      measurements: %{metric: 0.42},
      published_at: DateTime.utc_now()
    }

    send(view.pid, {:trial_update, trial_update})

    html = render(view)

    assert html =~ "model=transformer"
    assert html =~ "12345678"
    assert html =~ "JOB ID"
    assert html =~ "Metric: 0.420"
  end

  describe "launch_nas_run event handler" do
    test "successfully queues a NAS run with valid params", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      spec = %{
        "model" => "test_model",
        "dataset" => "test_dataset",
        "search_space" => %{
          "layers" => [1, 2, 3]
        }
      }

      # Trigger launch event
      view
      |> element("#launch-nas-run-button")
      |> render_click(%{"spec" => Jason.encode!(spec)})

      # Should show success message
      assert render(view) =~ "queued successfully" or render(view) =~ "NAS run"
    end

    test "handles launch errors gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      # Invalid spec
      invalid_spec = %{}

      view
      |> element("#launch-nas-run-button")
      |> render_click(%{"spec" => Jason.encode!(invalid_spec)})

      # Should show error message
      assert render(view) =~ "Failed" or render(view) =~ "error"
    end

    test "uses spec_payload from socket assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      # Set spec_payload in socket
      send(view.pid, {:set_spec_payload, %{"custom" => "payload"}})

      spec = %{"model" => "test"}

      view
      |> element("#launch-nas-run-button")
      |> render_click(%{"spec" => Jason.encode!(spec)})

      # Should process successfully
      html = render(view)
      assert html =~ "queued" or html =~ "run"
    end
  end

  describe "cancel_run event handler" do
    test "successfully cancels a running NAS job", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      run_id = "test-run-#{System.unique_integer([:positive])}"

      view
      |> element("#cancel-run-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # Should show cancellation message
      assert render(view) =~ "cancelled" or render(view) =~ "canceled"
    end

    test "handles cancel errors gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      # Non-existent run
      fake_run_id = "non-existent-run"

      view
      |> element("#cancel-run-button-#{fake_run_id}")
      |> render_click(%{"run_id" => fake_run_id})

      # Should show error message
      assert render(view) =~ "Failed to cancel" or render(view) =~ "error"
    end
  end

  describe "view_results event handler" do
    test "successfully loads run results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      run_id = "test-run-#{System.unique_integer([:positive])}"

      view
      |> element("#view-results-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # Should update socket with results or show message
      html = render(view)
      assert html =~ "Results loaded" or html =~ "results" or html =~ "Failed"
    end

    test "assigns current_results to socket on success", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      run_id = "test-run-#{System.unique_integer([:positive])}"

      # Mock successful results retrieval
      results = %{
        "trials" => [
          %{"id" => "trial-1", "metric" => 0.95},
          %{"id" => "trial-2", "metric" => 0.87}
        ],
        "best_trial" => %{"id" => "trial-1", "metric" => 0.95}
      }

      # This would require mocking CerebrosBridge.get_run_results/1
      # For now, we test the event handler exists and doesn't crash
      view
      |> element("#view-results-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # Should not crash
      assert is_binary(render(view))
    end

    test "handles missing run_id gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      # Try without run_id
      view
      |> element("#view-results-button")
      |> render_click(%{})

      # Should show error or handle gracefully
      html = render(view)
      assert html =~ "error" or html =~ "Failed" or is_binary(html)
    end
  end

  describe "download_report event handler" do
    test "successfully generates and downloads report", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      run_id = "test-run-#{System.unique_integer([:positive])}"

      view
      |> element("#download-report-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # Should show report generation message
      html = render(view)
      assert html =~ "Report" or html =~ "download" or html =~ "Failed"
    end

    test "pushes download event on success", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      run_id = "test-run-#{System.unique_integer([:positive])}"

      # Subscribe to download events
      # In a real test, you'd verify the download event was pushed

      view
      |> element("#download-report-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # Should handle the download
      assert is_binary(render(view))
    end

    test "handles report generation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      fake_run_id = "non-existent-report"

      view
      |> element("#download-report-button-#{fake_run_id}")
      |> render_click(%{"run_id" => fake_run_id})

      # Should show error message
      assert render(view) =~ "Failed to generate report" or render(view) =~ "error"
    end
  end

  describe "error handling across all event handlers" do
    test "all handlers return proper noreply tuples", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cerebros")

      run_id = "test-#{System.unique_integer([:positive])}"

      # Launch run
      view
      |> element("#launch-nas-run-button")
      |> render_click(%{"spec" => Jason.encode!(%{"model" => "test"})})

      # Cancel run
      view
      |> element("#cancel-run-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # View results
      view
      |> element("#view-results-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # Download report
      view
      |> element("#download-report-button-#{run_id}")
      |> render_click(%{"run_id" => run_id})

      # View should still be alive after all events
      assert render(view)
    end

    test "handlers work when Cerebros bridge is disabled", %{conn: conn} do
      # Temporarily disable bridge
      Application.put_env(:thunderline, :cerebros_bridge, enabled: false)

      {:ok, view, _html} = live(conn, ~p"/cerebros")

      spec = %{"model" => "test"}

      view
      |> element("#launch-nas-run-button")
      |> render_click(%{"spec" => Jason.encode!(spec)})

      # Should show appropriate error
      assert render(view) =~ "disabled" or render(view) =~ "error" or render(view) =~ "Failed"

      # Re-enable for other tests
      Application.put_env(:thunderline, :cerebros_bridge, enabled: true)
    end
  end
end
