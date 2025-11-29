defmodule Thunderline.Thunderbolt.ML.ModelServer do
  @moduledoc """
  GenServer for persistent ONNX model session management.

  Keeps loaded models in memory for fast inference without reloading.
  Supports preloading, on-demand loading, and automatic cache management.

  ## Features

  - **Persistent Sessions**: Models stay loaded across requests
  - **On-Demand Loading**: Load models when first requested
  - **Preloading**: Load models at startup from config or UPM snapshots
  - **Cache Eviction**: LRU eviction when max_models limit reached
  - **Health Checks**: Periodic validation of loaded models
  - **Telemetry**: Comprehensive metrics and logging

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.ML.ModelServer,
        max_models: 10,
        preload: ["cerebros_trained.onnx"],
        model_dir: "priv/models",
        health_check_interval: :timer.minutes(5)

  ## Usage

      # Get or load a model session (cached)
      {:ok, session} = ModelServer.get_session("cerebros_trained.onnx")

      # Run inference (session is persistent)
      {:ok, output} = KerasONNX.infer(session, input)

      # Preload a model explicitly
      :ok = ModelServer.preload("new_model.onnx")

      # Evict a model from cache
      :ok = ModelServer.evict("old_model.onnx")

      # List loaded models
      models = ModelServer.list_models()

  ## Telemetry

  Emits:
  - `[:thunderbolt, :model_server, :load]` - Model loaded
  - `[:thunderbolt, :model_server, :hit]` - Cache hit
  - `[:thunderbolt, :model_server, :evict]` - Model evicted
  - `[:thunderbolt, :model_server, :health]` - Health check
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.ML.KerasONNX

  @default_max_models 10
  @default_model_dir "priv/models"
  @default_health_interval :timer.minutes(5)

  # State structure
  defstruct [
    :max_models,
    :model_dir,
    :health_timer,
    sessions: %{},        # model_name => session
    access_times: %{},    # model_name => last_access_time
    load_times: %{}       # model_name => load_duration_ms
  ]

  # ─────────────────────────────────────────────────────────────
  # Client API
  # ─────────────────────────────────────────────────────────────

  @doc """
  Starts the ModelServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets a loaded model session, loading on-demand if not cached.

  Returns `{:ok, session}` or `{:error, reason}`.
  """
  @spec get_session(String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def get_session(model_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:get_session, model_name}, :timer.seconds(30))
  end

  @doc """
  Preloads a model into the cache.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec preload(String.t(), keyword()) :: :ok | {:error, term()}
  def preload(model_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:preload, model_name}, :timer.seconds(30))
  end

  @doc """
  Evicts a model from the cache.
  """
  @spec evict(String.t(), keyword()) :: :ok
  def evict(model_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:evict, model_name})
  end

  @doc """
  Lists all currently loaded models with metadata.
  """
  @spec list_models(keyword()) :: [map()]
  def list_models(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, :list_models)
  end

  @doc """
  Gets server stats.
  """
  @spec stats(keyword()) :: map()
  def stats(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, :stats)
  end

  @doc """
  Runs inference directly through the server (for convenience).

  Loads model if needed, runs inference, returns output.
  """
  @spec infer(String.t(), Nx.Tensor.t() | list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def infer(model_name, input, opts \\ []) do
    with {:ok, session} <- get_session(model_name, opts) do
      do_infer(session, input)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ─────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    config = Application.get_env(:thunderline, __MODULE__, [])
    opts = Keyword.merge(config, opts)

    max_models = Keyword.get(opts, :max_models, @default_max_models)
    model_dir = Keyword.get(opts, :model_dir, @default_model_dir)
    preload_models = Keyword.get(opts, :preload, [])
    health_interval = Keyword.get(opts, :health_check_interval, @default_health_interval)

    state = %__MODULE__{
      max_models: max_models,
      model_dir: model_dir,
      sessions: %{},
      access_times: %{},
      load_times: %{}
    }

    # Schedule health check
    health_timer = if health_interval > 0 do
      Process.send_after(self(), :health_check, health_interval)
    end

    state = %{state | health_timer: health_timer}

    # Preload models asynchronously
    if preload_models != [] do
      Logger.info("[ModelServer] Preloading #{length(preload_models)} model(s)...")
      spawn_link(fn -> do_preload_models(preload_models, self()) end)
    end

    Logger.info("[ModelServer] Started (max_models=#{max_models}, model_dir=#{model_dir})")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_session, model_name}, _from, state) do
    case Map.get(state.sessions, model_name) do
      nil ->
        # Cache miss - load the model
        case load_model(model_name, state.model_dir) do
          {:ok, session, load_ms} ->
            state = cache_model(state, model_name, session, load_ms)

            :telemetry.execute(
              [:thunderbolt, :model_server, :load],
              %{duration_ms: load_ms},
              %{model: model_name}
            )

            {:reply, {:ok, session}, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end

      session ->
        # Cache hit - update access time
        :telemetry.execute(
          [:thunderbolt, :model_server, :hit],
          %{},
          %{model: model_name}
        )

        state = touch_model(state, model_name)
        {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:preload, model_name}, _from, state) do
    if Map.has_key?(state.sessions, model_name) do
      {:reply, :ok, state}
    else
      case load_model(model_name, state.model_dir) do
        {:ok, session, load_ms} ->
          state = cache_model(state, model_name, session, load_ms)
          Logger.info("[ModelServer] Preloaded: #{model_name} (#{load_ms}ms)")
          {:reply, :ok, state}

        {:error, reason} = error ->
          Logger.warning("[ModelServer] Failed to preload #{model_name}: #{inspect(reason)}")
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call({:evict, model_name}, _from, state) do
    state = evict_model(state, model_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:list_models, _from, state) do
    models =
      state.sessions
      |> Map.keys()
      |> Enum.map(fn name ->
        %{
          name: name,
          last_access: Map.get(state.access_times, name),
          load_time_ms: Map.get(state.load_times, name)
        }
      end)

    {:reply, models, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      loaded_models: map_size(state.sessions),
      max_models: state.max_models,
      model_dir: state.model_dir,
      models: Map.keys(state.sessions)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Verify all loaded models are still valid
    healthy_count =
      state.sessions
      |> Enum.count(fn {_name, session} ->
        # Try a simple operation to verify session is alive
        try do
          _ = Ortex.run(session, Nx.tensor([[0]], type: :s64))
          true
        rescue
          _ -> false
        catch
          _ -> false
        end
      end)

    :telemetry.execute(
      [:thunderbolt, :model_server, :health],
      %{healthy: healthy_count, total: map_size(state.sessions)},
      %{}
    )

    # Reschedule
    health_interval = Application.get_env(:thunderline, __MODULE__)[:health_check_interval]
                      || @default_health_interval

    if health_interval > 0 do
      Process.send_after(self(), :health_check, health_interval)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:preloaded, model_name, result}, state) do
    case result do
      {:ok, session, load_ms} ->
        state = cache_model(state, model_name, session, load_ms)
        Logger.info("[ModelServer] Preloaded: #{model_name} (#{load_ms}ms)")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[ModelServer] Preload failed for #{model_name}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions
  # ─────────────────────────────────────────────────────────────

  defp load_model(model_name, model_dir) do
    path = resolve_path(model_name, model_dir)
    start = System.monotonic_time(:millisecond)

    case KerasONNX.load!(path) do
      {:ok, session} ->
        load_ms = System.monotonic_time(:millisecond) - start
        {:ok, session, load_ms}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_path(model_name, model_dir) do
    cond do
      Path.type(model_name) == :absolute -> model_name
      String.starts_with?(model_name, "priv/") -> model_name
      String.starts_with?(model_name, model_dir) -> model_name
      true -> Path.join(model_dir, model_name)
    end
  end

  defp cache_model(state, model_name, session, load_ms) do
    now = System.monotonic_time(:millisecond)

    # Evict LRU if at capacity
    state =
      if map_size(state.sessions) >= state.max_models do
        lru_model =
          state.access_times
          |> Enum.min_by(fn {_name, time} -> time end)
          |> elem(0)

        Logger.debug("[ModelServer] Evicting LRU model: #{lru_model}")
        evict_model(state, lru_model)
      else
        state
      end

    %{state |
      sessions: Map.put(state.sessions, model_name, session),
      access_times: Map.put(state.access_times, model_name, now),
      load_times: Map.put(state.load_times, model_name, load_ms)
    }
  end

  defp touch_model(state, model_name) do
    now = System.monotonic_time(:millisecond)
    %{state | access_times: Map.put(state.access_times, model_name, now)}
  end

  defp evict_model(state, model_name) do
    :telemetry.execute(
      [:thunderbolt, :model_server, :evict],
      %{},
      %{model: model_name}
    )

    %{state |
      sessions: Map.delete(state.sessions, model_name),
      access_times: Map.delete(state.access_times, model_name),
      load_times: Map.delete(state.load_times, model_name)
    }
  end

  defp do_preload_models(models, server_pid) do
    model_dir = Application.get_env(:thunderline, __MODULE__)[:model_dir] || @default_model_dir

    Enum.each(models, fn model_name ->
      result = load_model(model_name, model_dir)
      send(server_pid, {:preloaded, model_name, result})
    end)
  end

  defp do_infer(session, input) when is_list(input) do
    tensor = Nx.tensor(input, type: :s64, backend: Nx.BinaryBackend)
    do_infer(session, tensor)
  end

  defp do_infer(session, %Nx.Tensor{} = tensor) do
    tensor = Nx.backend_transfer(tensor, Nx.BinaryBackend)

    case Ortex.run(session, tensor) do
      {output} ->
        {:ok, Nx.backend_transfer(output, Nx.BinaryBackend)}

      outputs when is_tuple(outputs) ->
        {:ok, outputs |> elem(0) |> Nx.backend_transfer(Nx.BinaryBackend)}
    end
  rescue
    error -> {:error, {:inference_failed, error}}
  end
end
