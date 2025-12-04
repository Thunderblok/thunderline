defmodule ThunderlineWeb.CerebrosLive do
  @moduledoc """
  CerebrosLive - Unified front-end panel to:
    * Launch & monitor Cerebros NAS runs
    * Run small benchmarking demos (haus, positronic, matmul, training)
    * Observe placeholder Raincatcher-style drift metrics (λ, D2) until full integration lands
    * Cross-link with Thunderbit automata experiments (seed architectures from automata density)

  This is an initial scaffold; metrics are mocked/incremental until the Thundereye drift pipeline is wired.
  """
  use ThunderlineWeb, :live_view

  alias Phoenix.PubSub
  alias Thunderline.Thunderbolt.CerebrosBridge
  alias Thunderline.Thunderbolt.CerebrosBridge.Validator

  @tick_interval 1_000
  @run_topic "cerebros:runs"
  @trial_topic "cerebros:trials"
  @history_limit 12
  @default_spec Validator.default_spec()

  @impl true
  def mount(_params, _session, socket) do
    enabled? = cerebros_enabled?()
    spec_result = Validator.validate_spec(@default_spec)
    spec_form = build_spec_form(spec_result.json)

    socket =
      socket
      |> assign(:page_title, "Cerebros & Drift Lab")
      |> assign(:cerebros_enabled?, enabled?)
      |> assign(:running_nas, false)
      |> assign(:nas_results, [])
      |> assign(:status_msg, "Idle")
      |> assign(:spec_form, spec_form)
      |> assign(:spec_json, spec_result.json)
      |> assign(:spec_payload, spec_result.spec)
      |> assign(:spec_errors, spec_result.errors)
      |> assign(:spec_warnings, spec_result.warnings)
      |> assign(:spec_status, spec_result.status)
      |> assign(:run_history, [])
      |> assign(:trial_updates, [])
      |> assign(:current_run, nil)
      |> assign(:current_run_id, nil)
      |> assign(:drift_stats, %{
        lambda: 0.0,
        corr_dim: 0.0,
        sample: 0,
        coherence: 0.0,
        updated_at: nil
      })
      |> assign(:benchmark, nil)
      |> assign(:matmul, nil)
      |> assign(:haus_running, false)
      |> assign(:positronic, nil)

    if enabled? do
      if connected?(socket) do
        :timer.send_interval(@tick_interval, :tick)
        PubSub.subscribe(Thunderline.PubSub, "drift:demo")
        PubSub.subscribe(Thunderline.PubSub, @run_topic)
        PubSub.subscribe(Thunderline.PubSub, @trial_topic)
      end

      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(:status_msg, "Cerebros integration disabled")}
    end
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{cerebros_enabled?: false}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Cerebros integration is disabled")}
  end

  def handle_event("validate_spec", %{"nas" => %{"spec" => spec_json}}, socket) do
    result = Validator.validate_spec(spec_json || "")

    {:noreply,
     socket
     |> assign(:spec_form, build_spec_form(result.json || spec_json))
     |> assign(:spec_json, result.json || spec_json)
     |> assign(:spec_payload, result.spec)
     |> assign(:spec_errors, result.errors)
     |> assign(:spec_warnings, result.warnings)
     |> assign(:spec_status, result.status)}
  end

  def handle_event("reset_spec", _params, socket) do
    result = Validator.validate_spec(@default_spec)

    {:noreply,
     socket
     |> assign(:spec_form, build_spec_form(result.json))
     |> assign(:spec_json, result.json)
     |> assign(:spec_payload, result.spec)
     |> assign(:spec_errors, result.errors)
     |> assign(:spec_warnings, result.warnings)
     |> assign(:spec_status, result.status)}
  end

  def handle_event("launch_nas_run", params, socket) do
    spec_payload = socket.assigns[:spec_payload] || %{}

    case Thunderline.Thunderbolt.CerebrosBridge.queue_run(params, spec_payload) do
      {:ok, run_id} ->
        {:noreply, put_flash(socket, :info, "NAS run queued successfully: #{run_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue run: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_run", %{"run_id" => run_id} = _params, socket) do
    case Thunderline.Thunderbolt.CerebrosBridge.cancel_run(run_id) do
      {:ok, _result} ->
        {:noreply, put_flash(socket, :info, "Run #{run_id} cancelled successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel run: #{inspect(reason)}")}
    end
  end

  def handle_event("view_results", %{"run_id" => run_id} = _params, socket) do
    case Thunderline.Thunderbolt.CerebrosBridge.get_run_results(run_id) do
      {:ok, results} ->
        socket = assign(socket, :results, results)
        {:noreply, put_flash(socket, :info, "Results loaded successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load results: #{inspect(reason)}")}
    end
  end

  def handle_event("download_report", %{"run_id" => run_id} = _params, socket) do
    case Thunderline.Thunderbolt.CerebrosBridge.download_report(run_id) do
      {:ok, report_path} ->
        {:noreply, put_flash(socket, :info, "Report downloaded to: #{report_path}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to download report: #{inspect(reason)}")}
    end
  end

  def handle_event("start_haus", _params, socket) do
    Task.start(fn ->
      Cerebros.haus(search_profile: :conservative, epochs: 1, trial_timeout_ms: 5_000)
    end)

    {:noreply, assign(socket, haus_running: true, status_msg: "haus demo started")}
  end

  def handle_event("run_matmul", params, socket) do
    size = parse_int(params["size"], 512)
    result = Cerebros.benchmark_matmul(size: size, reps: 2, warmup: 0)
    {:noreply, assign(socket, :matmul, result)}
  end

  def handle_event("run_training", _params, socket) do
    result = Cerebros.benchmark_training(batches: 5, hidden_dims: [128, 128], batch_size: 128)
    {:noreply, assign(socket, :benchmark, result)}
  end

  def handle_event("demo_positronic", _params, socket) do
    case Cerebros.demo_positronic(min_levels: 2, max_levels: 3) do
      {:ok, m} ->
        {:noreply,
         assign(socket, positronic: %{params: m.param_count, summary: summarize_spec(m.spec)})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Positronic demo failed: #{inspect(reason)}")}
    end
  end

  def handle_event("mock_drift_spike", _params, socket) do
    # Simulate a drift spike to test UI responsiveness
    send(
      self(),
      {:drift_update,
       %{
         lambda: :rand.uniform() * 0.2,
         corr_dim: 2.0 + :rand.uniform() * 3.0,
         sample: socket.assigns.drift_stats.sample + 10
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, %{assigns: %{cerebros_enabled?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    # Lightweight periodic decay toward baseline for mock drift metrics when not updated externally
    stats = socket.assigns.drift_stats
    now = DateTime.utc_now()

    age_ms =
      case stats.updated_at do
        nil -> 0
        dt -> DateTime.diff(now, dt, :millisecond)
      end

    stats =
      if age_ms > 5_000 do
        Map.merge(stats, %{
          lambda: stats.lambda * 0.95,
          corr_dim: stats.corr_dim * 0.98,
          coherence: recompute_coherence(stats.lambda * 0.95, stats.corr_dim * 0.98),
          updated_at: now
        })
      else
        stats
      end

    {:noreply, assign(socket, :drift_stats, stats)}
  end

  def handle_info({:drift_update, payload}, socket) do
    lambda = Map.get(payload, :lambda, socket.assigns.drift_stats.lambda)
    d2 = Map.get(payload, :corr_dim, socket.assigns.drift_stats.corr_dim)
    sample = Map.get(payload, :sample, socket.assigns.drift_stats.sample)

    stats = %{
      lambda: lambda,
      corr_dim: d2,
      sample: sample,
      coherence: recompute_coherence(lambda, d2),
      updated_at: DateTime.utc_now()
    }

    {:noreply, assign(socket, :drift_stats, stats)}
  end

  def handle_info({:run_update, update}, socket) do
    history = add_history(socket.assigns.run_history, update)

    current_run =
      if update.run_id == socket.assigns.current_run_id,
        do: update,
        else: socket.assigns.current_run

    running =
      case update.stage do
        :queued -> true
        :started -> true
        _ -> false
      end

    status_msg = run_status_message(update)

    {:noreply,
     socket
     |> assign(:run_history, history)
     |> assign(:current_run, current_run)
     |> assign(:running_nas, running)
     |> assign(:status_msg, status_msg)}
  end

  def handle_info({:trial_update, update}, socket) do
    {:noreply,
     socket
     |> update(:trial_updates, fn list ->
       list
       |> List.insert_at(0, Map.put_new(update, :published_at, DateTime.utc_now()))
       |> Enum.take(@history_limit)
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="cerebros-lab space-y-8">
      <h1 class="text-3xl font-bold text-gray-900">Cerebros & Drift Lab</h1>

      <%= if @cerebros_enabled? do %>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- NAS Run Control -->
          <div class="bg-white rounded-lg shadow p-6 space-y-4">
            <h2 class="text-xl font-semibold">Neural Architecture Search</h2>
            <.form
              for={@spec_form}
              id="nas-run-form"
              phx-change="validate_spec"
              phx-submit="start_run"
              class="space-y-3"
            >
              <.input
                field={@spec_form[:spec]}
                id={@spec_form[:spec].id}
                name={@spec_form[:spec].name}
                value={@spec_form[:spec].value}
                type="textarea"
                label="Run specification (JSON)"
                rows="14"
                class="font-mono text-xs"
              />
              <%= if @spec_errors != [] do %>
                <div
                  data-role="spec-errors"
                  class="rounded border border-rose-200 bg-rose-50 p-3 text-xs text-rose-700 space-y-2"
                >
                  <div class="tracking-wide uppercase font-semibold text-rose-600 text-[0.7rem]">
                    Spec errors ({length(@spec_errors)})
                  </div>
                  <ul class="list-disc space-y-1 pl-4">
                    <li :for={msg <- Enum.reverse(@spec_errors)}>{msg}</li>
                  </ul>
                </div>
              <% end %>

              <%= if @spec_errors == [] and @spec_warnings != [] do %>
                <div
                  data-role="spec-warnings"
                  class="rounded border border-amber-200 bg-amber-50 p-3 text-xs text-amber-700 space-y-2"
                >
                  <div class="tracking-wide uppercase font-semibold text-amber-600 text-[0.7rem]">
                    Spec warnings ({length(@spec_warnings)})
                  </div>
                  <ul class="list-disc space-y-1 pl-4">
                    <li :for={msg <- Enum.reverse(@spec_warnings)}>{msg}</li>
                  </ul>
                </div>
              <% end %>
              <div class="flex items-center justify-between text-xs text-gray-500">
                <div>
                  <span class={[status_badge_class(@spec_status)]}>
                    {String.upcase(to_string(@spec_status))}
                  </span>
                  <span class="ml-2 text-gray-500">
                    {spec_feedback_summary(@spec_errors, @spec_warnings)}
                  </span>
                </div>
                <div class="flex gap-2">
                  <button
                    type="button"
                    phx-click="reset_spec"
                    class="px-3 py-1 border border-slate-300 rounded hover:bg-slate-50"
                  >
                    Reset
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded disabled:opacity-40"
                    disabled={@spec_status == :error}
                    phx-disable-with="Queueing..."
                  >
                    Queue NAS Run
                  </button>
                </div>
              </div>
            </.form>

            <div class="border-t pt-4 space-y-3 text-sm text-gray-700">
              <div class="flex items-center justify-between">
                <div class="font-medium">Status</div>
                <div class="font-mono text-xs text-gray-500">
                  {@current_run && short_id(@current_run.run_id)}
                </div>
              </div>
              <div class="rounded border border-slate-200 bg-slate-50 p-3 text-xs font-mono min-h-[3rem]">
                {@status_msg}
              </div>
              <div class="flex gap-2 text-xs">
                <button
                  phx-click="start_haus"
                  type="button"
                  class="px-3 py-1 bg-blue-600 hover:bg-blue-700 text-white rounded"
                >
                  haus demo
                </button>
                <button
                  phx-click="demo_positronic"
                  type="button"
                  class="px-3 py-1 bg-purple-600 hover:bg-purple-700 text-white rounded"
                >
                  Positronic
                </button>
              </div>
              <%= if @positronic do %>
                <div class="mt-2 text-xs font-mono bg-gray-50 border border-slate-200 p-2 rounded">
                  <div>Params: {@positronic.params}</div>
                  <div>Spec: {@positronic.summary}</div>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Benchmarks -->
          <div class="bg-white rounded-lg shadow p-6 space-y-4">
            <h2 class="text-xl font-semibold">Benchmarks</h2>
            <form phx-change="noop" phx-submit="run_matmul" class="space-y-2">
              <label class="block text-sm font-medium">Matmul Size</label>
              <input
                name="size"
                type="number"
                min="128"
                step="64"
                value="512"
                class="w-full border rounded px-2 py-1"
              />
              <button class="px-3 py-1 bg-indigo-600 text-white rounded">Run Matmul</button>
            </form>
            <button phx-click="run_training" class="px-3 py-1 bg-green-600 text-white rounded">
              Training Benchmark
            </button>
            <%= if @matmul do %>
              <div class="mt-3 text-xs font-mono bg-gray-50 p-2 rounded">
                <div>Avg ms: {Float.round(@matmul.avg_ms, 2)}</div>
                <div>GFLOP/s: {Float.round(@matmul.avg_gflops, 2)}</div>
              </div>
            <% end %>
            <%= if @benchmark do %>
              <div class="mt-3 text-xs font-mono bg-gray-50 p-2 rounded">
                <div>Steps/sec: {Float.round(@benchmark.steps_per_sec, 2)}</div>
                <div>Approx GFLOP/s: {Float.round(@benchmark.approx_gflops, 2)}</div>
              </div>
            <% end %>
          </div>
          
    <!-- Drift Metrics -->
          <div class="bg-white rounded-lg shadow p-6 space-y-4">
            <h2 class="text-xl font-semibold">Drift Metrics (Preview)</h2>
            <div class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <div class="text-gray-500">λ (Lyapunov)</div>
                <div class={lyap_color(@drift_stats.lambda)}>
                  {format_float(@drift_stats.lambda, 4)}
                </div>
              </div>
              <div>
                <div class="text-gray-500">D2 (Corr Dim)</div>
                <div class="font-mono text-blue-600">{format_float(@drift_stats.corr_dim, 3)}</div>
              </div>
              <div>
                <div class="text-gray-500">Coherence</div>
                <div class="font-mono text-purple-600">{format_float(@drift_stats.coherence, 3)}</div>
              </div>
              <div>
                <div class="text-gray-500">Samples</div>
                <div class="font-mono">{@drift_stats.sample}</div>
              </div>
            </div>
            <button
              phx-click="mock_drift_spike"
              class="px-3 py-1 bg-amber-600 text-white rounded text-xs"
            >
              Mock Spike
            </button>
            <div class="text-xs text-gray-500">
              Real streaming metrics will replace this mock once Thundereye drift server is active.
            </div>
          </div>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow p-6 text-center space-y-3">
          <p class="text-lg font-semibold text-gray-800">Cerebros integration disabled</p>
          <p class="text-sm text-gray-600">
            Enable the <code class="px-1 py-0.5 bg-gray-100 rounded">CEREBROS_ENABLED</code>
            environment toggle and <code class="px-1 py-0.5 bg-gray-100 rounded">ml_nas</code>
            feature flag to access this workspace.
          </p>
        </div>
      <% end %>

      <%= if @cerebros_enabled? do %>
        <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <div data-role="current-run-card" class="bg-white rounded-lg shadow p-6 space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-gray-800">Current Run</h2>
              <span class={[stage_badge_class((@current_run && @current_run.stage) || :idle)]}>
                {format_stage((@current_run && @current_run.stage) || :idle)}
              </span>
            </div>
            <%= if @current_run do %>
              <div class="flex items-center justify-between text-xs text-gray-500">
                <span class="font-mono text-gray-600">{short_id(@current_run.run_id)}</span>
                <span>{format_timestamp(@current_run.published_at)}</span>
              </div>
              <div class="rounded border border-slate-200 bg-slate-50 p-3 text-xs font-mono text-gray-700">
                {run_status_message(@current_run)}
              </div>
              <div
                :if={metadata_pairs(@current_run.metadata) != []}
                class="space-y-2 text-xs text-gray-600"
              >
                <div class="tracking-wide uppercase text-[0.65rem] text-gray-500">Metadata</div>
                <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1">
                  <div :for={{label, value} <- metadata_pairs(@current_run.metadata)} class="truncate">
                    <dt class="text-[0.65rem] uppercase text-gray-400">{label}</dt>
                    <dd class="font-mono text-gray-700 break-all">{value}</dd>
                  </div>
                </dl>
              </div>
              <div
                :if={measurement_pairs(@current_run.measurements) != []}
                class="space-y-2 text-xs text-gray-600"
              >
                <div class="tracking-wide uppercase text-[0.65rem] text-gray-500">Measurements</div>
                <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1">
                  <div :for={{label, value} <- measurement_pairs(@current_run.measurements)}>
                    <dt class="text-[0.65rem] uppercase text-gray-400">{label}</dt>
                    <dd class="font-mono text-gray-700">{value}</dd>
                  </div>
                </dl>
              </div>
              <div
                :if={matching_trials(@trial_updates, @current_run.run_id) != []}
                class="space-y-2 text-xs"
              >
                <div class="tracking-wide uppercase text-[0.65rem] text-gray-500">Latest trials</div>
                <ul class="space-y-1">
                  <li
                    :for={trial <- matching_trials(@trial_updates, @current_run.run_id)}
                    class="border border-slate-200 rounded px-2 py-1"
                  >
                    <div class="flex justify-between text-[0.7rem] uppercase text-gray-500">
                      <span>{trial.trial_id}</span>
                      <span>{format_stage(trial.stage)}</span>
                    </div>
                    <div class="text-xs font-mono text-gray-700">Metric: {format_metric(trial)}</div>
                  </li>
                </ul>
              </div>
            <% else %>
              <div class="text-sm text-gray-500">
                Queue a NAS run to see live telemetry updates. Specs are validated locally before dispatch.
              </div>
            <% end %>
            <div class="flex flex-wrap gap-2 text-xs text-gray-500">
              <a
                href="/api/cerebros/metrics"
                target="_blank"
                class="inline-flex items-center gap-1 px-3 py-1 border border-slate-300 rounded hover:bg-slate-50"
              >
                Metrics JSON
              </a>
              <span class="inline-flex items-center px-3 py-1 rounded bg-slate-100">
                {run_count_label(length(@run_history))}
              </span>
            </div>
          </div>

          <div data-role="run-activity" class="bg-white rounded-lg shadow p-6">
            <h2 class="text-lg font-semibold text-gray-800 mb-4">Run Activity</h2>
            <div :if={Enum.empty?(@run_history)} class="text-sm text-gray-500">
              Queue a NAS run to see lifecycle activity.
            </div>
            <div
              :for={entry <- @run_history}
              class="border border-slate-200 rounded mb-3 last:mb-0 overflow-hidden"
            >
              <div class="flex items-center justify-between bg-slate-50 px-3 py-2">
                <div class="flex items-center gap-2 text-xs uppercase tracking-wide">
                  <span class={[stage_badge_class(entry.stage)]}>{format_stage(entry.stage)}</span>
                  <span class="font-mono text-gray-500">{short_id(entry.run_id)}</span>
                </div>
                <div class="text-xs text-gray-500">{format_timestamp(entry.published_at)}</div>
              </div>
              <div class="px-3 py-2 text-xs space-y-2 text-gray-700">
                <div class="font-mono">{run_status_message(entry)}</div>
                <div
                  :if={metadata_pairs(entry.metadata) != []}
                  class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1"
                >
                  <div
                    :for={{label, value} <- metadata_pairs(entry.metadata)}
                    class="text-[0.7rem] text-gray-500"
                  >
                    <span class="font-semibold uppercase">{label}:</span>
                    <span class="font-mono text-gray-700 ml-1">{value}</span>
                  </div>
                </div>
                <div
                  :if={measurement_pairs(entry.measurements) != []}
                  class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1"
                >
                  <div
                    :for={{label, value} <- measurement_pairs(entry.measurements)}
                    class="text-[0.7rem] text-gray-500"
                  >
                    <span class="font-semibold uppercase">{label}:</span>
                    <span class="font-mono text-gray-700 ml-1">{value}</span>
                  </div>
                </div>
              </div>
            </div>

            <div :if={@trial_updates != []} class="mt-6">
              <h3 class="text-sm font-semibold text-gray-700 mb-3">Recent Trials</h3>
              <ul class="space-y-2 text-xs text-gray-600">
                <li :for={trial <- @trial_updates} class="border border-slate-200 rounded px-3 py-2">
                  <div class="flex justify-between text-[0.7rem] uppercase text-gray-500">
                    <span>{short_id(trial.run_id)} · {trial.trial_id}</span>
                    <span>{format_stage(trial.stage)}</span>
                  </div>
                  <div class="font-mono text-gray-700">Metric: {format_metric(trial)}</div>
                  <div class="text-[0.65rem] text-gray-400">
                    {format_timestamp(trial.published_at)}
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  ## Helpers
  defp format_float(v, dec) when is_number(v), do: :erlang.float_to_binary(v, decimals: dec)
  defp format_float(_, _), do: "n/a"

  defp lyap_color(v) when v < 0.0, do: "font-mono text-green-600"
  defp lyap_color(v) when v < 0.05, do: "font-mono text-emerald-500"
  defp lyap_color(v) when v < 0.12, do: "font-mono text-amber-600"
  defp lyap_color(_), do: "font-mono text-red-600"

  defp recompute_coherence(lambda, d2) do
    # Simple placeholder coherence metric: higher when lambda small & d2 moderate
    stability = 1.0 / (1.0 + :math.exp(8 * lambda))
    thickness = :math.exp(-0.05 * :math.pow(max(d2 - 3.0, 0.0), 2))
    (stability * thickness) |> min(1.0) |> max(0.0)
  end

  defp summarize_spec(spec) do
    levels = length(spec.levels)
    units = spec.levels |> Enum.map(&length(&1.units)) |> Enum.sum()
    "lv=#{levels} units=#{units}"
  rescue
    _ -> "n/a"
  end

  defp parse_int(nil, default), do: default
  defp parse_int(<<>>, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {v, _} -> v
      :error -> default
    end
  end

  defp parse_int(v, _) when is_integer(v), do: v
  defp cerebros_enabled?, do: CerebrosBridge.enabled?()

  defp build_spec_form(json) do
    to_form(%{"spec" => json}, as: :nas)
  end

  defp add_history(history, update) do
    entry = Map.put_new(update, :published_at, DateTime.utc_now())

    history
    |> Enum.reject(&(&1.run_id == entry.run_id and &1.stage == entry.stage))
    |> List.insert_at(0, entry)
    |> Enum.take(@history_limit)
  end

  defp run_status_message(%{stage: :queued, run_id: run_id, metadata: meta}) do
    "Queued #{short_id(run_id)} (priority=#{meta[:priority] || :normal})"
  end

  defp run_status_message(%{stage: :started, run_id: run_id, metadata: meta}) do
    model = meta[:model] || "unknown"
    "Run #{short_id(run_id)} started · model=#{model}"
  end

  defp run_status_message(%{stage: :stopped, run_id: run_id, metadata: meta, measurements: meas}) do
    metric = meas[:best_metric] || "n/a"
    status = meta[:status] || :ok
    "Run #{short_id(run_id)} completed (status=#{status}, metric=#{metric})"
  end

  defp run_status_message(%{stage: :failed, run_id: run_id, metadata: meta}) do
    reason = meta[:reason] || "unknown"
    "Run #{short_id(run_id)} failed: #{reason}"
  end

  defp run_status_message(_entry), do: "Awaiting signal"

  defp short_id(nil), do: "n/a"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(id), do: inspect(id)

  defp format_stage(stage) when is_atom(stage), do: stage |> Atom.to_string() |> String.upcase()
  defp format_stage(stage), do: to_string(stage)

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  rescue
    _ -> DateTime.to_iso8601(dt)
  end

  defp stage_badge_class(:queued), do: "px-2 py-0.5 bg-blue-50 text-blue-700 rounded"
  defp stage_badge_class(:started), do: "px-2 py-0.5 bg-indigo-50 text-indigo-700 rounded"
  defp stage_badge_class(:stopped), do: "px-2 py-0.5 bg-emerald-50 text-emerald-700 rounded"
  defp stage_badge_class(:failed), do: "px-2 py-0.5 bg-rose-50 text-rose-700 rounded"
  defp stage_badge_class(_), do: "px-2 py-0.5 bg-slate-100 text-slate-600 rounded"

  defp status_badge_class(:ok), do: "px-2 py-1 text-xs bg-emerald-100 text-emerald-700 rounded"
  defp status_badge_class(:warning), do: "px-2 py-1 text-xs bg-amber-100 text-amber-700 rounded"
  defp status_badge_class(:error), do: "px-2 py-1 text-xs bg-rose-100 text-rose-700 rounded"
  defp status_badge_class(_), do: "px-2 py-1 text-xs bg-slate-100 text-slate-600 rounded"

  defp spec_feedback_summary([], []), do: "Spec ready"

  defp spec_feedback_summary(errors, warnings) do
    parts = []
    parts = if errors != [], do: parts ++ [count_label(length(errors), "error")], else: parts

    parts =
      if warnings != [], do: parts ++ [count_label(length(warnings), "warning")], else: parts

    Enum.join(parts, " · ")
  end

  defp count_label(1, noun), do: "1 #{noun}"
  defp count_label(count, noun), do: "#{count} #{noun}s"

  defp metadata_pairs(nil), do: []

  defp metadata_pairs(meta) when is_map(meta) do
    meta
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {format_label(k), format_value(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp metadata_pairs(meta) when is_list(meta) do
    meta
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {format_label(k), format_value(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp metadata_pairs(_), do: []

  defp measurement_pairs(nil), do: []

  defp measurement_pairs(measurements) when is_map(measurements) do
    measurements
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {format_label(k), format_value(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp measurement_pairs(measurements) when is_list(measurements) do
    measurements
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {format_label(k), format_value(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp measurement_pairs(_), do: []

  defp format_label(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp format_label(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp format_label(key), do: inspect(key)

  defp format_value(%DateTime{} = dt), do: format_timestamp(dt)
  defp format_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp matching_trials(trials, run_id) when is_list(trials) and is_binary(run_id) do
    trials
    |> Enum.filter(&(&1.run_id == run_id))
    |> Enum.take(3)
  end

  defp matching_trials(_, _), do: []

  defp format_metric(%{measurements: measurements}) do
    metric =
      cond do
        is_map(measurements) && Map.has_key?(measurements, :metric) ->
          Map.get(measurements, :metric)

        is_map(measurements) && Map.has_key?(measurements, "metric") ->
          Map.get(measurements, "metric")

        is_list(measurements) ->
          Keyword.get(measurements, :metric) || Keyword.get(measurements, "metric")

        true ->
          nil
      end

    metric
    |> case do
      nil -> "n/a"
      value -> format_value(value)
    end
  end

  defp format_metric(_), do: "n/a"

  defp run_count_label(0), do: "No past runs"
  defp run_count_label(1), do: "1 past run"
  defp run_count_label(count) when is_integer(count), do: "#{count} past runs"
  defp run_count_label(_), do: "Past runs"
end
