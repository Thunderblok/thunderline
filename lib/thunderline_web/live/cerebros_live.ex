if System.get_env("ENABLE_CEREBROS") == "true" do
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
    @tick_interval 1_000

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket) do
        :timer.send_interval(@tick_interval, :tick)
        PubSub.subscribe(Thunderline.PubSub, "drift:demo")
      end

      {:ok,
       socket
       |> assign(:page_title, "Cerebros & Drift Lab")
       |> assign(:running_nas, false)
       |> assign(:nas_results, [])
       |> assign(:status_msg, "Idle")
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
       |> assign(:positronic, nil)}
    end

    @impl true
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

    @impl true
    def render(assigns) do
      ~H"""
      <div class="cerebros-lab space-y-8">
        <h1 class="text-3xl font-bold text-gray-900">Cerebros & Drift Lab</h1>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Cerebros Actions -->
          <div class="bg-white rounded-lg shadow p-6 space-y-4">
            <h2 class="text-xl font-semibold">Neural Architecture Search</h2>
            <div class="flex space-x-2">
              <button
                phx-click="start_haus"
                class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded"
              >
                Run haus demo
              </button>
              <button
                phx-click="demo_positronic"
                class="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded"
              >
                Positronic
              </button>
            </div>
            <div class="text-sm text-gray-600">Status: {@status_msg}</div>
            <%= if @positronic do %>
              <div class="mt-2 text-xs font-mono bg-gray-50 p-2 rounded">
                <div>Params: {@positronic.params}</div>
                <div>Spec: {@positronic.summary}</div>
              </div>
            <% end %>
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
  end
end
