defmodule Thunderline.Thunderbolt.CerebrosBridge.Contracts do
  @moduledoc """
  Versioned contract structs exchanged between the Cerebros bridge translator and the rest
  of the ThunderBolt domain. These payloads are embedded inside canonical `%Thunderline.Event{}`
  emissions and persisted alongside run/trial metadata.

  Each contract module exposes a simple typed struct so downstream code can rely on explicit
  shape/version guarantees when interacting with bridge results.
  """

  alias __MODULE__.{RunStartedV1, TrialReportedV1, RunFinalizedV1}

  defmodule RunStartedV1 do
    @moduledoc """
    Contract emitted when a Cerebros NAS pulse run is initiated.

    * `run_id` – canonical Ash ModelRun id / correlation id
    * `dataset_id` – identifier for the dataset to use for training
    * `search_space` – architecture search space configuration (layers, activations, etc.)
    * `objective` – optimization objective (e.g. 'accuracy', 'loss', 'f1')
    * `pulse_id` – optional pulse identifier for incremental NAS loops
    * `budget` – map describing trial/time/resource limits
    * `parameters` – initial search parameters / priors
    * `tau` – exploration temperature (Pulse-NAS / GDAS)
    * `correlation_id` – telemetry correlation (defaults to run id)
    * `timestamp` – UTC timestamp of the start event
    * `extra` – bag for future extensibility (kept small for canonical events)
    """
    @enforce_keys [:run_id, :timestamp]
    defstruct run_id: nil,
              dataset_id: nil,
              search_space: %{},
              objective: "accuracy",
              pulse_id: nil,
              budget: %{},
              parameters: %{},
              tau: nil,
              correlation_id: nil,
              timestamp: nil,
              extra: %{}

    @type t :: %__MODULE__{
            run_id: String.t(),
            pulse_id: String.t() | nil,
            budget: map(),
            parameters: map(),
            tau: number() | nil,
            correlation_id: String.t() | nil,
            timestamp: DateTime.t(),
            extra: map()
          }
  end

  defmodule TrialReportedV1 do
    @moduledoc """
    Contract emitted for every trial evaluated inside a pulse.

    * `trial_id` – unique trial identifier
    * `run_id` – parent ModelRun id
    * `pulse_id` – originating pulse identifier (if applicable)
    * `candidate_id` – identifier of the sampled architecture/candidate
    * `status` – :succeeded | :failed | :skipped | :cancelled
    * `metrics` – map of evaluation metrics (validation accuracy, loss, etc.)
    * `parameters` – hyper-parameters / architecture choices used for the trial
    * `artifact_uri` – optional URI of produced artifact (object storage)
    * `duration_ms` – wall clock time spent evaluating the trial
    * `rank` – optional ranking within the pulse
    * `warnings` – array of non-fatal warning strings
    * `spectral_norm` – boolean flag indicating if spectral normalization was used
    * `mlflow_run_id` – optional MLflow run identifier for tracking
    """
    @enforce_keys [:trial_id, :run_id, :status]
    defstruct trial_id: nil,
              run_id: nil,
              pulse_id: nil,
              candidate_id: nil,
              status: :succeeded,
              metrics: %{},
              parameters: %{},
              artifact_uri: nil,
              duration_ms: nil,
              rank: nil,
              warnings: [],
              spectral_norm: false,
              mlflow_run_id: nil

    @type status :: :succeeded | :failed | :skipped | :cancelled

    @type t :: %__MODULE__{
            trial_id: String.t(),
            run_id: String.t(),
            pulse_id: String.t() | nil,
            candidate_id: String.t() | nil,
            status: status(),
            metrics: map(),
            parameters: map(),
            artifact_uri: String.t() | nil,
            duration_ms: non_neg_integer() | nil,
            rank: non_neg_integer() | nil,
            warnings: [String.t()],
            spectral_norm: boolean(),
            mlflow_run_id: String.t() | nil
          }
  end

  defmodule RunFinalizedV1 do
    @moduledoc """
    Contract emitted when a Cerebros NAS pulse run completes or fails.

    * `run_id` – canonical run id
    * `pulse_id` – pulse identifier (if applicable)
    * `status` – :succeeded | :failed | :cancelled | :timeout
    * `metrics` – aggregated/best metrics for the run
    * `best_trial_id` – identifier of the promoted/best-performing trial
    * `duration_ms` – wall clock duration of the pulse
    * `returncode` – exit status from external execution (if available)
    * `artifact_refs` – list of artifact descriptors persisted in ledger/object store
    * `warnings` – array of warning strings encountered during execution
    * `stdout_excerpt` – bounded excerpt of captured stdout for observability
    * `payload` – optional raw payload returned by Cerebros (kept small)
    """
    @enforce_keys [:run_id, :status]
    defstruct run_id: nil,
              pulse_id: nil,
              status: :succeeded,
              metrics: %{},
              best_trial_id: nil,
              duration_ms: nil,
              returncode: nil,
              artifact_refs: [],
              warnings: [],
              stdout_excerpt: nil,
              payload: %{}

    @type status :: :succeeded | :failed | :cancelled | :timeout

    @type t :: %__MODULE__{
            run_id: String.t(),
            pulse_id: String.t() | nil,
            status: status(),
            metrics: map(),
            best_trial_id: String.t() | nil,
            duration_ms: non_neg_integer() | nil,
            returncode: integer() | nil,
            artifact_refs: [map()],
            warnings: [String.t()],
            stdout_excerpt: String.t() | nil,
            payload: map()
          }
  end

  @type run_started :: RunStartedV1.t()
  @type trial_reported :: TrialReportedV1.t()
  @type run_finalized :: RunFinalizedV1.t()
end
