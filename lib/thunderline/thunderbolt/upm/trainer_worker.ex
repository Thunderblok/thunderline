defmodule Thunderline.Thunderbolt.UPM.TrainerWorker do
  @moduledoc """
  Unified Persistent Model online trainer GenServer.

  Consumes ThunderFlow feature windows, performs incremental SGD updates,
  and emits telemetry for observability. Coordinates with ReplayBuffer
  for out-of-order event handling and SnapshotManager for persistence.

  ## Responsibilities

  - Subscribe to `system.feature_window.created` events from ThunderFlow
  - Consume feature windows via ReplayBuffer (handles deduplication)
  - Perform online SGD updates (incremental learning)
  - Track training metrics (loss, drift, window count)
  - Emit telemetry [:upm, :trainer, :update]
  - Coordinate snapshot creation on boundaries (e.g., every 1000 windows)
  - Update UpmTrainer resource with latest metrics

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.TrainerWorker,
        trainer_name: "default",
        tenant_id: nil,
        mode: :shadow,
        snapshot_interval: 1000,
        learning_rate: 0.001,
        batch_size: 32

  ## Telemetry Events

  - `[:upm, :trainer, :update]` - Emitted after processing each window
    - Measurements: `%{loss: float, duration_ms: integer, window_count: integer}`
    - Metadata: `%{trainer_id: uuid, mode: atom, window_id: uuid}`

  - `[:upm, :trainer, :snapshot]` - Emitted when creating snapshots
    - Measurements: `%{snapshot_size_bytes: integer, version: integer}`
    - Metadata: `%{trainer_id: uuid, snapshot_id: uuid}`

  ## Supervision

  This worker is supervised by UPM.Supervisor and automatically restarts
  on failure with exponential backoff.
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Resources.{UpmTrainer, UpmSnapshot}
  alias Thunderline.Thunderbolt.UPM.{ReplayBuffer, SnapshotManager, SGD}
  alias Thunderline.Features.FeatureWindow
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.UUID

  @type state :: %{
          trainer_id: binary(),
          trainer_name: String.t(),
          tenant_id: binary() | nil,
          mode: :shadow | :canary | :active,
          model_params: map(),
          window_count: non_neg_integer(),
          total_loss: float(),
          snapshot_interval: pos_integer(),
          learning_rate: float(),
          batch_size: pos_integer(),
          last_window_id: binary() | nil,
          replay_buffer: pid() | nil,
          status: :idle | :training | :paused | :errored
        }

  # Client API

  @doc """
  Starts the UPM trainer worker with the given configuration.

  ## Options

  - `:name` - Registered name for the GenServer (default: `__MODULE__`)
  - `:trainer_name` - Logical name for the trainer (default: "default")
  - `:tenant_id` - Optional tenant scope
  - `:mode` - Rollout mode (:shadow | :canary | :active)
  - `:snapshot_interval` - Windows between snapshots (default: 1000)
  - `:learning_rate` - SGD learning rate (default: 0.001)
  - `:batch_size` - Batch size for updates (default: 32)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Processes a feature window (called by EventBus subscription).
  """
  @spec process_window(GenServer.server(), binary()) :: :ok
  def process_window(server \\ __MODULE__, window_id) do
    GenServer.cast(server, {:process_window, window_id})
  end

  @doc """
  Pauses training (for maintenance or debugging).
  """
  @spec pause(GenServer.server()) :: :ok
  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  @doc """
  Resumes training after pause.
  """
  @spec resume(GenServer.server()) :: :ok
  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  @doc """
  Gets current trainer metrics.
  """
  @spec get_metrics(GenServer.server()) :: map()
  def get_metrics(server \\ __MODULE__) do
    GenServer.call(server, :get_metrics)
  end

  @doc """
  Forces snapshot creation (for testing or manual intervention).
  """
  @spec create_snapshot(GenServer.server()) :: {:ok, binary()} | {:error, term()}
  def create_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :create_snapshot)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    trainer_name = Keyword.get(opts, :trainer_name, "default")
    tenant_id = Keyword.get(opts, :tenant_id)
    mode = Keyword.get(opts, :mode, :shadow)
    snapshot_interval = Keyword.get(opts, :snapshot_interval, 1000)
    learning_rate = Keyword.get(opts, :learning_rate, 0.001)
    batch_size = Keyword.get(opts, :batch_size, 32)

    # Initialize or load existing trainer
    case ensure_trainer(trainer_name, tenant_id, mode) do
      {:ok, trainer} ->
        # Start replay buffer
        {:ok, buffer_pid} = ReplayBuffer.start_link(trainer_id: trainer.id)

        # Subscribe to feature window events
        subscribe_to_windows()

        state = %{
          trainer_id: trainer.id,
          trainer_name: trainer_name,
          tenant_id: tenant_id,
          mode: mode,
          model_params: initialize_model_params(),
          window_count: 0,
          total_loss: 0.0,
          snapshot_interval: snapshot_interval,
          learning_rate: learning_rate,
          batch_size: batch_size,
          last_window_id: trainer.last_window_id,
          replay_buffer: buffer_pid,
          status: :idle
        }

        Logger.info("""
        [UPM.TrainerWorker] Initialized trainer
          trainer_id: #{trainer.id}
          name: #{trainer_name}
          mode: #{mode}
          tenant_id: #{inspect(tenant_id)}
        """)

        {:ok, state}

      {:error, reason} ->
        Logger.error("[UPM.TrainerWorker] Failed to initialize trainer: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:process_window, window_id}, %{status: :paused} = state) do
    Logger.debug("[UPM.TrainerWorker] Skipping window (paused): #{window_id}")
    {:noreply, state}
  end

  def handle_cast({:process_window, window_id}, state) do
    start_time = System.monotonic_time(:millisecond)

    case do_process_window(window_id, state) do
      {:ok, new_state} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        avg_loss = new_state.total_loss / max(new_state.window_count, 1)

        # Emit telemetry
        :telemetry.execute(
          [:upm, :trainer, :update],
          %{
            loss: avg_loss,
            duration_ms: duration_ms,
            window_count: new_state.window_count
          },
          %{
            trainer_id: state.trainer_id,
            mode: state.mode,
            window_id: window_id
          }
        )

        # Update trainer resource
        update_trainer_metrics(new_state)

        # Check if snapshot boundary reached
        new_state = maybe_create_snapshot(new_state)

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[UPM.TrainerWorker] Failed to process window: #{inspect(reason)}")

        # Update status to errored
        update_trainer_status(state.trainer_id, :errored)

        {:noreply, %{state | status: :errored}}
    end
  end

  @impl true
  def handle_call(:pause, _from, state) do
    Logger.info("[UPM.TrainerWorker] Pausing trainer #{state.trainer_id}")
    update_trainer_status(state.trainer_id, :paused)
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:resume, _from, state) do
    Logger.info("[UPM.TrainerWorker] Resuming trainer #{state.trainer_id}")
    update_trainer_status(state.trainer_id, :training)
    {:reply, :ok, %{state | status: :training}}
  end

  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      trainer_id: state.trainer_id,
      mode: state.mode,
      status: state.status,
      window_count: state.window_count,
      avg_loss: state.total_loss / max(state.window_count, 1),
      last_window_id: state.last_window_id
    }

    {:reply, metrics, state}
  end

  def handle_call(:create_snapshot, _from, state) do
    case do_create_snapshot(state) do
      {:ok, snapshot_id} ->
        {:reply, {:ok, snapshot_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(%Thunderline.Event{name: "system.feature_window.created"} = event, state) do
    # Extract window ID from event payload
    window_id = event.payload["window_id"] || event.payload[:window_id]

    if window_id do
      # Add to replay buffer for ordered processing
      ReplayBuffer.add(state.replay_buffer, window_id, event.payload)

      :telemetry.execute(
        [:upm, :trainer, :event_received],
        %{count: 1},
        %{trainer_id: state.trainer_id, window_id: window_id, event_name: event.name}
      )

      Logger.debug("[UPM.TrainerWorker] Received feature window event: #{window_id}")
    else
      Logger.warning("[UPM.TrainerWorker] Received feature window event without window_id: #{inspect(event)}")
    end

    {:noreply, state}
  end

  # Handle legacy event format for backward compatibility
  def handle_info({:event_bus, %{name: "system.feature_window.created", payload: payload}}, state) do
    window_id = payload["window_id"] || payload[:window_id]

    if window_id do
      ReplayBuffer.add(state.replay_buffer, window_id, payload)

      :telemetry.execute(
        [:upm, :trainer, :event_received],
        %{count: 1},
        %{trainer_id: state.trainer_id, window_id: window_id}
      )
    end

    {:noreply, state}
  end

  def handle_info({:replay_buffer, :ready, window_id}, state) do
    # Replay buffer signals this window is ready for processing
    handle_cast({:process_window, window_id}, state)
  end

  def handle_info(msg, state) do
    Logger.debug("[UPM.TrainerWorker] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp ensure_trainer(name, tenant_id, mode) do
    require Ash.Query

    UpmTrainer
    |> Ash.Query.filter(name == ^name and tenant_id == ^tenant_id)
    |> Ash.read(tenant: tenant_id)
    |> case do
      {:ok, [trainer]} ->
        {:ok, trainer}

      {:ok, []} ->
        # Create new trainer
        UpmTrainer
        |> Ash.Changeset.for_create(:register, %{name: name, tenant_id: tenant_id, mode: mode})
        |> Ash.create(tenant: tenant_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp subscribe_to_windows do
    # Subscribe to ThunderFlow feature window events via PubSub
    # EventBus publishes to Mnesia tables, but also broadcasts via PubSub as fallback
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:feature_window")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system.feature_window.created")
    Logger.info("[UPM.TrainerWorker] Subscribed to feature window events")
    :ok
  end

  defp initialize_model_params do
    # Initialize model parameters using real Nx-based SGD
    SGD.initialize_params(
      feature_dim: 64,
      hidden_dim: 128,
      output_dim: 32
    )
  end

  defp do_process_window(window_id, state) do
    # Fetch feature window from ThunderFlow
    case Ash.get(FeatureWindow, window_id, tenant: state.tenant_id) do
      {:ok, window} ->
        # Extract features and labels from window
        features = window.features || %{}
        labels = window.labels

        # Only train on filled windows with labels
        if window.status == :filled and labels do
          # Perform SGD update
          {loss, updated_params} = sgd_update(window, state.model_params, state.learning_rate)

          new_state = %{
            state
            | model_params: updated_params,
              window_count: state.window_count + 1,
              total_loss: state.total_loss + loss,
              last_window_id: window_id,
              status: :training
          }

          {:ok, new_state}
        else
          # Skip unfilled windows
          Logger.debug("[UPM.TrainerWorker] Skipping unfilled window: #{window_id} (status: #{window.status})")
          {:ok, state}
        end

      {:error, reason} ->
        {:error, {:window_fetch_failed, reason}}
    end
  end

  defp sgd_update(window, params, learning_rate) do
    # Real SGD update using Nx tensors
    # Extract features and labels from the window
    features = window.features || %{}
    labels = window.labels || %{}

    # Perform actual gradient descent update
    SGD.update(features, labels, params, learning_rate: learning_rate)
  end

  defp update_trainer_metrics(state) do
    avg_loss = state.total_loss / max(state.window_count, 1)

    %{
      status: state.status,
      last_window_id: state.last_window_id,
      last_window_fetched_at: DateTime.utc_now(),
      last_loss: avg_loss,
      metadata: %{
        window_count: state.window_count,
        model_version: state.model_params.version
      }
    }
    |> then(&UpmTrainer.update_metrics(state.trainer_id, &1))
    |> case do
      {:ok, _trainer} ->
        :ok

      {:error, reason} ->
        Logger.error("[UPM.TrainerWorker] Failed to update metrics: #{inspect(reason)}")
    end
  end

  defp update_trainer_status(trainer_id, status) do
    %{status: status}
    |> then(&UpmTrainer.update_metrics(trainer_id, &1))
    |> case do
      {:ok, _trainer} ->
        :ok

      {:error, reason} ->
        Logger.error("[UPM.TrainerWorker] Failed to update status: #{inspect(reason)}")
    end
  end

  defp maybe_create_snapshot(state) do
    if rem(state.window_count, state.snapshot_interval) == 0 do
      case do_create_snapshot(state) do
        {:ok, _snapshot_id} ->
          state

        {:error, reason} ->
          Logger.error("[UPM.TrainerWorker] Snapshot creation failed: #{inspect(reason)}")
          state
      end
    else
      state
    end
  end

  defp do_create_snapshot(state) do
    version = div(state.window_count, state.snapshot_interval)
    snapshot_id = UUID.v7()

    # Serialize model parameters
    model_data = :erlang.term_to_binary(state.model_params)
    checksum = :crypto.hash(:sha256, model_data) |> Base.encode16(case: :lower)

    snapshot_params = %{
      trainer_id: state.trainer_id,
      tenant_id: state.tenant_id,
      version: version,
      mode: state.mode,
      status: :shadow,
      checksum: checksum,
      size_bytes: byte_size(model_data),
      metadata: %{
        window_count: state.window_count,
        avg_loss: state.total_loss / max(state.window_count, 1),
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    # Persist snapshot via SnapshotManager
    case SnapshotManager.create_snapshot(snapshot_params, model_data) do
      {:ok, snapshot} ->
        # Emit telemetry
        :telemetry.execute(
          [:upm, :trainer, :snapshot],
          %{
            snapshot_size_bytes: snapshot.size_bytes,
            version: version
          },
          %{
            trainer_id: state.trainer_id,
            snapshot_id: snapshot.id
          }
        )

        # Publish event
        EventBus.publish_event(%{
          name: "ai.upm.snapshot.created",
          source: :bolt,
          payload: %{
            snapshot_id: snapshot.id,
            trainer_id: state.trainer_id,
            version: version,
            mode: state.mode,
            checksum: checksum
          },
          correlation_id: UUID.v7()
        })

        Logger.info("[UPM.TrainerWorker] Created snapshot #{snapshot.id} (version #{version})")
        {:ok, snapshot.id}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
