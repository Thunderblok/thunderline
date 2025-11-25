defmodule Thunderline.Telemetry.LoopMonitor do
  @moduledoc """
  Monitors domain health and near-critical dynamics using observables.

  Implements the Cinderforge Lab paper concepts:
  - PLV (Phase Locking Value): Synchrony across activations
  - σ (Token Entropy Ratio): Signal propagation balance
  - λ̂ (Local FTLE Estimate): Stability/chaos detection
  - Rτ (Resonance Index): Cross-layer energy transfer

  ## Usage

  Start the monitor in your supervision tree:

      children = [
        {Thunderline.Telemetry.LoopMonitor, name: :ml_loop_monitor}
      ]

  Then observe domain states:

      LoopMonitor.observe(:ml_pipeline, %{
        tick: 42,
        activations: tensor,
        entropy_prev: 2.3,
        entropy_next: 2.1,
        jvp_matrix: jacobian
      })

  ## Events Emitted

  - `[:thunderline, :loop_monitor, :observed]` - Every observation
  - `[:thunderline, :loop_monitor, :loop_detected]` - PLV > 0.9
  - `[:thunderline, :loop_monitor, :degenerate_signal]` - σ outside bounds
  - `[:thunderline, :loop_monitor, :chaotic_drift]` - λ̂ > 0.1
  - `[:thunderline, :loop_monitor, :resonance_spike]` - Rτ sudden increase

  ## iRoPE-style Intervention

  When loops are detected, the monitor can trigger phase bias adjustments
  via the `:intervention` callback. See `register_intervention/2`.
  """

  use GenServer
  require Logger

  alias Thunderline.Utils.Stats

  @type domain :: atom()
  @type tick :: non_neg_integer()

  # How many observations to keep per domain for trend analysis
  @history_size 100

  # Thresholds for alerts
  @plv_loop_threshold 0.9
  @sigma_degenerate_high 1.5
  @sigma_degenerate_low 0.5
  @lambda_chaotic_threshold 0.1
  @rtau_spike_factor 2.0

  # Target bands (from paper)
  @plv_band {0.3, 0.6}
  @sigma_band {0.8, 1.2}

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  @doc """
  Start the LoopMonitor.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Observe a domain's state and emit telemetry.

  ## Parameters

  - `domain`: Atom identifying the domain (e.g., :ml_pipeline, :crown, :flow)
  - `state`: Map containing:
    - `:tick` - Current tick number
    - `:activations` - Nx tensor of activations
    - `:entropy_prev` - Entropy at t-1
    - `:entropy_next` - Entropy at t
    - `:jvp_matrix` - Jacobian-vector product matrix (optional)

  ## Returns

  `:ok` or `{:intervention, action}` if corrective action needed
  """
  @spec observe(domain(), map()) :: :ok | {:intervention, atom()}
  def observe(domain, state, server \\ __MODULE__) do
    GenServer.call(server, {:observe, domain, state})
  end

  @doc """
  Get current health status for a domain.
  """
  @spec get_status(domain()) :: map()
  def get_status(domain, server \\ __MODULE__) do
    GenServer.call(server, {:get_status, domain})
  end

  @doc """
  Get observation history for a domain.
  """
  @spec get_history(domain()) :: [map()]
  def get_history(domain, server \\ __MODULE__) do
    GenServer.call(server, {:get_history, domain})
  end

  @doc """
  Register an intervention callback for a domain.

  The callback will be invoked when corrective action is needed.

  ## Example

      LoopMonitor.register_intervention(:ml_pipeline, fn action, state ->
        case action do
          :apply_phase_bias -> apply_irope_stern_mode(state)
          :throttle -> reduce_batch_size(state)
          _ -> :ok
        end
      end)
  """
  @spec register_intervention(domain(), (atom(), map() -> any())) :: :ok
  def register_intervention(domain, callback, server \\ __MODULE__)
      when is_function(callback, 2) do
    GenServer.cast(server, {:register_intervention, domain, callback})
  end

  @doc """
  Get summary statistics across all monitored domains.
  """
  @spec summary() :: map()
  def summary(server \\ __MODULE__) do
    GenServer.call(server, :summary)
  end

  # -------------------------------------------------------------------
  # Server Callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(_opts) do
    state = %{
      domains: %{},
      interventions: %{},
      started_at: DateTime.utc_now()
    }

    Logger.info("[LoopMonitor] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:observe, domain, observation}, _from, state) do
    {result, new_state} = do_observe(domain, observation, state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:get_status, domain}, _from, state) do
    status = get_domain_status(domain, state)
    {:reply, status, state}
  end

  @impl true
  def handle_call({:get_history, domain}, _from, state) do
    history = get_in(state, [:domains, domain, :history]) || []
    {:reply, history, state}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    summary = build_summary(state)
    {:reply, summary, state}
  end

  @impl true
  def handle_cast({:register_intervention, domain, callback}, state) do
    new_interventions = Map.put(state.interventions, domain, callback)
    {:noreply, %{state | interventions: new_interventions}}
  end

  # -------------------------------------------------------------------
  # Private Implementation
  # -------------------------------------------------------------------

  defp do_observe(domain, observation, state) do
    tick = Map.get(observation, :tick, 0)

    # Compute observables
    observables = compute_observables(observation)

    # Create observation record
    record = %{
      tick: tick,
      timestamp: DateTime.utc_now(),
      plv: observables.plv,
      sigma: observables.sigma,
      lambda: observables.lambda,
      rtau: observables.rtau,
      bands: observables.bands
    }

    # Emit base telemetry
    emit_telemetry(:observed, domain, record)

    # Check for alerts and interventions
    {alerts, intervention} = check_alerts(domain, record, state)

    # Emit alert telemetry
    Enum.each(alerts, fn {alert_type, metadata} ->
      emit_telemetry(alert_type, domain, metadata)
    end)

    # Update state
    new_state = update_domain_state(domain, record, state)

    # Trigger intervention if needed
    result =
      if intervention do
        trigger_intervention(domain, intervention, observation, new_state)
      else
        :ok
      end

    {result, new_state}
  end

  defp compute_observables(observation) do
    activations = Map.get(observation, :activations, Nx.tensor([[0.0]]))
    entropy_prev = Map.get(observation, :entropy_prev, 1.0)
    entropy_next = Map.get(observation, :entropy_next, 1.0)
    jvp_matrix = Map.get(observation, :jvp_matrix, Nx.tensor([[1.0]]))

    Stats.observe(%{
      activations: activations,
      entropy_prev: entropy_prev,
      entropy_next: entropy_next,
      jvp_matrix: jvp_matrix
    })
  end

  defp check_alerts(domain, record, state) do
    alerts = []
    intervention = nil

    # Check PLV (loop detection)
    {alerts, intervention} =
      if record.plv > @plv_loop_threshold do
        {
          [{:loop_detected, %{plv: record.plv, threshold: @plv_loop_threshold}} | alerts],
          :apply_phase_bias
        }
      else
        {alerts, intervention}
      end

    # Check sigma (signal degeneration)
    {alerts, intervention} =
      cond do
        record.sigma > @sigma_degenerate_high ->
          {
            [{:degenerate_signal, %{sigma: record.sigma, type: :amplifying}} | alerts],
            intervention || :throttle
          }

        record.sigma < @sigma_degenerate_low ->
          {
            [{:degenerate_signal, %{sigma: record.sigma, type: :decaying}} | alerts],
            intervention || :boost
          }

        true ->
          {alerts, intervention}
      end

    # Check lambda (chaotic drift)
    {alerts, intervention} =
      if record.lambda > @lambda_chaotic_threshold do
        {
          [{:chaotic_drift, %{lambda: record.lambda, threshold: @lambda_chaotic_threshold}} | alerts],
          intervention || :stabilize
        }
      else
        {alerts, intervention}
      end

    # Check for resonance spikes
    alerts =
      if rtau_spiking?(domain, record.rtau, state) do
        [{:resonance_spike, %{rtau: record.rtau}} | alerts]
      else
        alerts
      end

    {alerts, intervention}
  end

  defp rtau_spiking?(domain, current_rtau, state) do
    case get_in(state, [:domains, domain, :history]) do
      [prev | _] when is_map(prev) ->
        prev_rtau = Map.get(prev, :rtau, current_rtau)
        current_rtau > prev_rtau * @rtau_spike_factor

      _ ->
        false
    end
  end

  defp trigger_intervention(domain, action, observation, state) do
    case Map.get(state.interventions, domain) do
      nil ->
        Logger.warning(
          "[LoopMonitor] No intervention registered for #{domain}, action: #{action}"
        )
        {:intervention, action}

      callback ->
        Logger.info("[LoopMonitor] Triggering intervention #{action} for #{domain}")
        callback.(action, observation)
        {:intervention, action}
    end
  end

  defp update_domain_state(domain, record, state) do
    domain_state = Map.get(state.domains, domain, %{history: [], last_healthy: nil})

    new_history =
      [record | domain_state.history]
      |> Enum.take(@history_size)

    new_domain_state =
      domain_state
      |> Map.put(:history, new_history)
      |> Map.put(:last_observation, record)
      |> maybe_update_last_healthy(record)

    put_in(state, [:domains, domain], new_domain_state)
  end

  defp maybe_update_last_healthy(domain_state, record) do
    if record.bands.overall == :healthy do
      Map.put(domain_state, :last_healthy, record.timestamp)
    else
      domain_state
    end
  end

  defp get_domain_status(domain, state) do
    case get_in(state, [:domains, domain]) do
      nil ->
        %{status: :unknown, message: "No observations for domain"}

      domain_state ->
        last = domain_state.last_observation

        %{
          status: last.bands.overall,
          plv: last.plv,
          sigma: last.sigma,
          lambda: last.lambda,
          rtau: last.rtau,
          last_healthy: domain_state.last_healthy,
          observations_count: length(domain_state.history),
          time_in_band: compute_time_in_band(domain_state.history)
        }
    end
  end

  defp compute_time_in_band(history) do
    total = length(history)

    if total > 0 do
      healthy = Enum.count(history, &(&1.bands.overall == :healthy))
      Float.round(healthy / total * 100, 1)
    else
      0.0
    end
  end

  defp build_summary(state) do
    domains =
      state.domains
      |> Enum.map(fn {domain, domain_state} ->
        last = domain_state.last_observation

        {domain,
         %{
           status: last.bands.overall,
           plv: last.plv,
           sigma: last.sigma,
           time_in_band: compute_time_in_band(domain_state.history)
         }}
      end)
      |> Map.new()

    healthy_count = Enum.count(domains, fn {_, d} -> d.status == :healthy end)
    total_count = map_size(domains)

    %{
      domains: domains,
      healthy_count: healthy_count,
      total_count: total_count,
      health_ratio: if(total_count > 0, do: healthy_count / total_count, else: 1.0),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at)
    }
  end

  defp emit_telemetry(event, domain, metadata) do
    :telemetry.execute(
      [:thunderline, :loop_monitor, event],
      %{timestamp: System.monotonic_time()},
      Map.merge(metadata, %{domain: domain})
    )
  end
end
