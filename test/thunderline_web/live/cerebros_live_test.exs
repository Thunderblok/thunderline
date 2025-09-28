defmodule ThunderlineWeb.CerebrosLiveTest do
  use ThunderlineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Thunderline.Feature

  setup do
    Feature.override(:ml_nas, true)

    previous_features = Application.get_env(:thunderline, :features)
    Application.put_env(:thunderline, :features, [:ml_nas])

    previous = Application.get_env(:thunderline, :cerebros_bridge)
    Application.put_env(:thunderline, :cerebros_bridge, Keyword.merge(previous || [], enabled: true))

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
end
