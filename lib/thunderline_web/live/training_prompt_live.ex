defmodule ThunderlineWeb.TrainingPromptLive do
  @moduledoc """
  Interactive training job submission interface using text prompts.

  This LiveView allows users to:
  1. Enter training text/prompts directly
  2. Submit jobs to Cerebros via UPM pipeline
  3. Track training progress via MLflow integration
  4. View real-time updates on the dashboard

  Integrates with:
  - UPM (Unified Persistent Model) for continuous learning
  - Cerebros NAS for architecture search
  - MLflow for experiment tracking
  - Ash_AI for intelligent prompt processing
  """

  use ThunderlineWeb, :live_view
  on_mount ThunderlineWeb.Live.Auth

  require Logger
  alias Phoenix.PubSub
  alias Thunderline.Thunderbolt.Resources.{TrainingDataset, CerebrosTrainingJob}
  alias Thunderline.Workers.CerebrosTrainer
  alias Thunderline.Thunderbolt.Domain

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to training job updates
      PubSub.subscribe(Thunderline.PubSub, "training:jobs")
      PubSub.subscribe(Thunderline.PubSub, "cerebros:runs")
      PubSub.subscribe(Thunderline.PubSub, "mlflow:experiments")
    end

    socket =
      socket
      |> assign(:prompt_text, "")
      |> assign(:processing, false)
      |> assign(:recent_jobs, [])
      |> assign(:mlflow_tracking_uri, mlflow_uri())
      |> assign(:upm_enabled, upm_enabled?())
      |> assign(:form, to_form(%{}, as: :training))
      |> load_recent_jobs()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6">
      <header class="mb-8">
        <div class="flex items-center gap-4">
          <h1 class="text-2xl font-bold">Training Prompt Interface</h1>
          <span class="badge badge-info">
            {if @upm_enabled, do: "UPM Enabled", else: "UPM Disabled"}
          </span>
          <%= if @mlflow_tracking_uri do %>
            <a
              href={@mlflow_tracking_uri}
              target="_blank"
              class="btn btn-sm btn-ghost gap-2"
            >
              <span class="text-xs">📊 MLflow</span>
            </a>
          <% end %>
        </div>
        <p class="text-sm text-surface-muted mt-2">
          Submit training prompts that get processed through UPM, sent to Cerebros NAS,
          and tracked in MLflow for continuous model improvement.
        </p>
      </header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Training Prompt Input -->
        <section class="panel p-6">
          <div class="flex items-center gap-2 mb-4">
            <div class="w-2 h-2 rounded-full bg-emerald-400"></div>
            <h2 class="text-lg font-semibold">Submit Training Prompt</h2>
          </div>

          <.form
            for={@form}
            id="training-prompt-form"
            phx-submit="submit_training"
            class="space-y-4"
          >
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Training Text</span>
                <span class="label-text-alt text-xs text-surface-muted">
                  Enter training data, instructions, or prompts
                </span>
              </label>
              <textarea
                name="prompt_text"
                phx-debounce="300"
                rows="8"
                class="textarea textarea-bordered w-full font-mono text-sm"
                placeholder="Example:&#10;&#10;Classify customer sentiment:&#10;&#10;1. 'I love this product!' -> positive&#10;2. 'Not what I expected' -> negative&#10;3. 'It works fine' -> neutral"
                disabled={@processing}
              >{@prompt_text}</textarea>
              <label class="label">
                <span class="label-text-alt">{String.length(@prompt_text)} characters</span>
              </label>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Training Configuration</span>
              </label>
              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="label">
                    <span class="label-text-alt">Model Type</span>
                  </label>
                  <select name="model_type" class="select select-bordered select-sm w-full">
                    <option value="text_classification">Text Classification</option>
                    <option value="sentiment_analysis">Sentiment Analysis</option>
                    <option value="instruction_following">Instruction Following</option>
                    <option value="general_chat">General Chat</option>
                  </select>
                </div>
                <div>
                  <label class="label">
                    <span class="label-text-alt">Priority</span>
                  </label>
                  <select name="priority" class="select select-bordered select-sm w-full">
                    <option value="normal">Normal</option>
                    <option value="high">High</option>
                    <option value="low">Low</option>
                  </select>
                </div>
              </div>
            </div>

            <div class="form-control">
              <label class="cursor-pointer label justify-start gap-3">
                <input
                  type="checkbox"
                  name="use_upm"
                  class="checkbox checkbox-sm checkbox-primary"
                  checked={@upm_enabled}
                  disabled={!@upm_enabled}
                />
                <span class="label-text">
                  Use UPM (Unified Persistent Model) Pipeline
                </span>
              </label>
              <label class="cursor-pointer label justify-start gap-3">
                <input
                  type="checkbox"
                  name="track_mlflow"
                  class="checkbox checkbox-sm checkbox-primary"
                  checked
                />
                <span class="label-text">
                  Track in MLflow
                </span>
              </label>
            </div>

            <div class="flex gap-3">
              <button
                type="submit"
                class="btn btn-primary flex-1"
                disabled={@processing or String.length(@prompt_text) < 10}
              >
                <%= if @processing do %>
                  <span class="loading loading-spinner loading-sm"></span> Processing...
                <% else %>
                  🚀 Submit Training Job
                <% end %>
              </button>
              <button
                type="button"
                class="btn btn-ghost"
                phx-click="clear_prompt"
                disabled={@processing}
              >
                Clear
              </button>
            </div>
          </.form>

          <%= if @upm_enabled do %>
            <div class="alert alert-info mt-4 text-xs">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="stroke-current shrink-0 w-5 h-5"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                >
                </path>
              </svg>
              <span>
                UPM will continuously learn from this prompt and update all connected agents via snapshot distribution.
              </span>
            </div>
          <% end %>
        </section>
        
    <!-- Recent Training Jobs -->
        <section class="panel p-6">
          <div class="flex items-center gap-2 mb-4">
            <div class="w-2 h-2 rounded-full bg-violet-400"></div>
            <h2 class="text-lg font-semibold">Recent Training Jobs</h2>
            <button
              class="btn btn-ghost btn-xs ml-auto"
              phx-click="refresh_jobs"
            >
              Refresh
            </button>
          </div>

          <div class="space-y-3 max-h-[600px] overflow-y-auto">
            <%= if @recent_jobs == [] do %>
              <div class="text-center py-8 text-surface-muted">
                <p class="text-sm">No training jobs yet</p>
                <p class="text-xs mt-1">Submit your first prompt to get started</p>
              </div>
            <% else %>
              <%= for job <- @recent_jobs do %>
                <div class="rounded-lg border border-white/10 bg-white/5 p-4 space-y-2">
                  <div class="flex items-center justify-between">
                    <span class="font-mono text-xs text-surface-muted">
                      {short_id(job.id)}
                    </span>
                    <span class={job_status_badge(job.status)}>
                      {format_status(job.status)}
                    </span>
                  </div>

                  <%= if job.metadata["prompt_preview"] do %>
                    <p class="text-sm text-surface-strong line-clamp-2">
                      {job.metadata["prompt_preview"]}
                    </p>
                  <% end %>

                  <div class="grid grid-cols-2 gap-2 text-xs">
                    <div>
                      <span class="text-surface-soft">Model:</span>
                      <span class="text-surface-strong ml-1">
                        {job.metadata["model_type"] || "N/A"}
                      </span>
                    </div>
                    <div>
                      <span class="text-surface-soft">Started:</span>
                      <span class="text-surface-strong ml-1">
                        {format_timestamp(job.started_at)}
                      </span>
                    </div>
                  </div>

                  <%= if job.status == :running do %>
                    <div class="progress-container">
                      <progress class="progress progress-primary w-full" value="70" max="100">
                      </progress>
                      <span class="text-xs text-surface-muted mt-1">Phase {job.phase || 1}/4</span>
                    </div>
                  <% end %>

                  <%= if job.metrics do %>
                    <div class="grid grid-cols-3 gap-2 text-xs">
                      <%= for {key, value} <- Enum.take(job.metrics, 3) do %>
                        <div class="bg-black/20 rounded px-2 py-1">
                          <div class="text-surface-soft">{format_metric_key(key)}</div>
                          <div class="text-surface-strong">{format_metric_value(value)}</div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="flex gap-2 pt-2">
                    <%= if job.metadata["mlflow_run_id"] do %>
                      <a
                        href={mlflow_run_url(@mlflow_tracking_uri, job.metadata["mlflow_run_id"])}
                        target="_blank"
                        class="btn btn-xs btn-ghost"
                      >
                        📊 MLflow
                      </a>
                    <% end %>
                    <button class="btn btn-xs btn-ghost" phx-click="view_job" phx-value-id={job.id}>
                      Details
                    </button>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>
      </div>
      
    <!-- UPM Status Panel -->
      <%= if @upm_enabled do %>
        <section class="panel p-6 mt-6">
          <div class="flex items-center gap-2 mb-4">
            <div class="w-2 h-2 rounded-full bg-amber-400"></div>
            <h2 class="text-lg font-semibold">UPM Pipeline Status</h2>
          </div>

          <div class="grid grid-cols-4 gap-4">
            <div class="stat bg-white/5 rounded-lg">
              <div class="stat-title text-xs">Active Trainers</div>
              <div class="stat-value text-2xl text-emerald-400">
                {count_active_trainers()}
              </div>
              <div class="stat-desc">shadow mode</div>
            </div>

            <div class="stat bg-white/5 rounded-lg">
              <div class="stat-title text-xs">Snapshots</div>
              <div class="stat-value text-2xl text-sky-400">
                {count_snapshots()}
              </div>
              <div class="stat-desc">last 24h</div>
            </div>

            <div class="stat bg-white/5 rounded-lg">
              <div class="stat-title text-xs">Drift Score</div>
              <div class="stat-value text-2xl text-violet-400">
                {format_drift_score()}
              </div>
              <div class="stat-desc">p95</div>
            </div>

            <div class="stat bg-white/5 rounded-lg">
              <div class="stat-title text-xs">Adapters Synced</div>
              <div class="stat-value text-2xl text-cyan-400">
                {count_synced_adapters()}
              </div>
              <div class="stat-desc">agents updated</div>
            </div>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("submit_training", params, socket) do
    prompt_text = Map.get(params, "prompt_text", "")
    model_type = Map.get(params, "model_type", "text_classification")
    priority = Map.get(params, "priority", "normal")
    use_upm = Map.get(params, "use_upm") == "true"
    track_mlflow = Map.get(params, "track_mlflow") == "true"

    if String.length(prompt_text) < 10 do
      {:noreply, put_flash(socket, :error, "Prompt must be at least 10 characters")}
    else
      socket = assign(socket, :processing, true)

      # Create training dataset from prompt
      dataset_result =
        create_dataset_from_prompt(prompt_text, model_type, socket.assigns.current_user)

      case dataset_result do
        {:ok, dataset} ->
          # Enqueue training job
          job_opts = [
            metadata: %{
              "prompt_preview" => String.slice(prompt_text, 0, 100),
              "model_type" => model_type,
              "priority" => priority,
              "use_upm" => use_upm,
              "track_mlflow" => track_mlflow,
              "submitted_by" => user_identifier(socket.assigns.current_user)
            }
          ]

          case CerebrosTrainer.enqueue_training(dataset.id, job_opts) do
            {:ok, _oban_job} ->
              {:noreply,
               socket
               |> assign(:processing, false)
               |> assign(:prompt_text, "")
               |> put_flash(:info, "Training job submitted successfully!")
               |> load_recent_jobs()}

            {:error, reason} ->
              {:noreply,
               socket
               |> assign(:processing, false)
               |> put_flash(:error, "Failed to submit job: #{inspect(reason)}")}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Failed to create dataset: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("clear_prompt", _params, socket) do
    {:noreply, assign(socket, :prompt_text, "")}
  end

  @impl true
  def handle_event("refresh_jobs", _params, socket) do
    {:noreply, load_recent_jobs(socket)}
  end

  @impl true
  def handle_event("view_job", %{"id" => job_id}, socket) do
    # TODO: Navigate to job detail view or open modal
    {:noreply, put_flash(socket, :info, "Job details: #{job_id}")}
  end

  # PubSub Message Handlers

  @impl true
  def handle_info({:job_update, job_data}, socket) do
    Logger.info("Training job update received: #{inspect(job_data)}")
    {:noreply, load_recent_jobs(socket)}
  end

  @impl true
  def handle_info({:run_update, _update}, socket) do
    {:noreply, load_recent_jobs(socket)}
  end

  @impl true
  def handle_info({:mlflow_update, _update}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Private Helper Functions

  defp create_dataset_from_prompt(prompt_text, model_type, current_user) do
    # Create a training dataset and write prompt to temp file
    dataset_name = "prompt_#{System.unique_integer([:positive])}_#{model_type}"

    case TrainingDataset.create(
           %{
             name: dataset_name,
             description: "Training dataset from prompt submission",
             metadata: %{
               "source" => "prompt_interface",
               "model_type" => model_type,
               "created_by" => user_identifier(current_user)
             }
           },
           domain: Domain
         ) do
      {:ok, dataset} ->
        # Write prompt to corpus file
        corpus_path = Path.join(["/tmp/thunderline/training", dataset.id])
        File.mkdir_p!(corpus_path)

        csv_path = Path.join(corpus_path, "prompt_data.csv")

        csv_content = """
        text,label
        "#{String.replace(prompt_text, "\"", "\"\"")}","training_sample"
        """

        File.write!(csv_path, csv_content)

        # Update dataset with corpus path and freeze it
        {:ok, dataset} = TrainingDataset.set_corpus_path(dataset, corpus_path, domain: Domain)
        {:ok, dataset} = TrainingDataset.freeze(dataset, domain: Domain)

        {:ok, dataset}

      error ->
        error
    end
  end

  defp load_recent_jobs(socket) do
    # Load recent training jobs
    jobs =
      CerebrosTrainingJob.read!(domain: Domain)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(10)

    assign(socket, :recent_jobs, jobs)
  rescue
    _ -> assign(socket, :recent_jobs, [])
  end

  defp mlflow_uri do
    Application.get_env(:thunderline, :mlflow_tracking_uri, "http://localhost:5000")
  end

  defp upm_enabled? do
    Application.get_env(:thunderline, :features, [])
    |> Keyword.get(:unified_model, false)
  end

  defp user_identifier(%{email: email}) when is_binary(email), do: email
  defp user_identifier(%{name: name}) when is_binary(name), do: name
  defp user_identifier(_), do: "anonymous"

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(id), do: to_string(id)

  defp job_status_badge(:queued), do: "badge badge-outline badge-sm"
  defp job_status_badge(:running), do: "badge badge-info badge-sm"
  defp job_status_badge(:completed), do: "badge badge-success badge-sm"
  defp job_status_badge(:failed), do: "badge badge-error badge-sm"
  defp job_status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_status(status) when is_atom(status) do
    status |> Atom.to_string() |> String.upcase()
  end

  defp format_status(status), do: to_string(status)

  defp format_timestamp(nil), do: "N/A"

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_timestamp(_), do: "N/A"

  defp format_metric_key(key) when is_atom(key),
    do: key |> Atom.to_string() |> String.replace("_", " ")

  defp format_metric_key(key), do: to_string(key)

  defp format_metric_value(value) when is_float(value), do: Float.round(value, 4)
  defp format_metric_value(value), do: value

  defp mlflow_run_url(base_uri, run_id) do
    "#{base_uri}/#/experiments/1/runs/#{run_id}"
  end

  # UPM Stats (stub implementations - replace with actual queries)
  defp count_active_trainers, do: 2
  defp count_snapshots, do: 15
  defp format_drift_score, do: "0.18"
  defp count_synced_adapters, do: 8
end
