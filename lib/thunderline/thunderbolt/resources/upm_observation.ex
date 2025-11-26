defmodule Thunderline.Thunderbolt.Resources.UpmObservation do
  @moduledoc """
  Unified Persistent Model observation record.

  Stores LoopMonitor observables (PLV, σ, λ̂, Rτ) alongside pac_id/domain/tick
  references for cross-domain health tracking. This is the **single source of truth**
  for UPM health metrics in the system.

  ## Observables (from Cinderforge Lab paper)

  - **PLV** (Phase Locking Value): Synchrony across activations [0.0-1.0]
    - Target: 0.3-0.6 (edge of chaos)
    - High (>0.9) = potential loop

  - **σ (sigma)**: Token entropy ratio (propagation balance)
    - Target: ~1.0 ± 0.2
    - High (>1.2) = amplification, Low (<0.8) = decay

  - **λ̂ (lambda)**: Local FTLE estimate (stability indicator)
    - Target: ≤0 (stable)
    - High (>0.1) = chaotic drift

  - **Rτ (rtau)**: Resonance index (cross-layer energy transfer)
    - Monitored for spikes

  - **entropy**: Shannon entropy of activation distribution

  ## Multi-Manifold Clustering (HC-22A)

  - **manifold_id**: Cluster assignment from UMAP/HDBSCAN analysis
  - **cluster_stability**: Stability score [0.0-1.0] of current assignment
  - **manifold_distance**: Distance to manifold centroid in embedding space
  - **simplex_degree**: Degree in simplex graph (connectivity measure)

  ## Usage

      # Created by LoopMonitor after each observation
      UpmObservation.record(%{
        pac_id: agent_id,
        domain: :ml_pipeline,
        tick: 42,
        plv: 0.45,
        sigma: 1.02,
        lambda: -0.05,
        rtau: 0.8,
        entropy: 2.3,
        manifold_id: 3,
        cluster_stability: 0.87,
        band_status: :healthy
      })

  ## Event Emission

  Creates `ai.upm.observation.recorded` event on each record.

  ## Querying

      # Get latest observation for a PAC/domain
      UpmObservation
      |> Ash.Query.filter(pac_id == ^pac_id and domain == ^domain)
      |> Ash.Query.sort(tick: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read()

      # Get observations in unhealthy bands
      UpmObservation
      |> Ash.Query.filter(band_status != :healthy)
      |> Ash.Query.sort(tick: :desc)
      |> Ash.read()
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  alias Thunderline.UUID

  postgres do
    table "upm_observations"
    repo Thunderline.Repo

    custom_indexes do
      index [:pac_id, :domain, :tick], name: "upm_observations_pac_domain_tick_idx"
      index [:band_status], name: "upm_observations_band_status_idx"
      index [:inserted_at], name: "upm_observations_inserted_at_idx"
      index [:manifold_id], name: "upm_observations_manifold_id_idx"
    end
  end

  json_api do
    type "upm_observations"
  end

  code_interface do
    define :record, action: :record
    define :get_latest, action: :get_latest
    define :list_unhealthy, action: :list_unhealthy
    define :list_for_pac, action: :list_for_pac
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :pac_id,
        :domain,
        :tick,
        :plv,
        :sigma,
        :lambda,
        :rtau,
        :entropy,
        :manifold_id,
        :cluster_stability,
        :manifold_distance,
        :simplex_degree,
        :band_status,
        :intervention_triggered,
        :intervention_type,
        :activations_shape,
        :metadata
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:id, UUID.v7())
        |> maybe_compute_band_status()
      end
    end

    read :get_latest do
      argument :pac_id, :uuid, allow_nil?: false
      argument :domain, :atom, allow_nil?: false

      filter expr(pac_id == ^arg(:pac_id) and domain == ^arg(:domain))
      prepare build(sort: [tick: :desc], limit: 1)
    end

    read :list_unhealthy do
      argument :since, :utc_datetime_usec, allow_nil?: true

      filter expr(
               band_status != :healthy and
                 (is_nil(^arg(:since)) or inserted_at >= ^arg(:since))
             )

      prepare build(sort: [inserted_at: :desc], limit: 100)
    end

    read :list_for_pac do
      argument :pac_id, :uuid, allow_nil?: false
      argument :limit, :integer, allow_nil?: true, default: 50

      filter expr(pac_id == ^arg(:pac_id))
      prepare build(sort: [tick: :desc])
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    # --- Identity/Context ---

    attribute :pac_id, :uuid do
      description "PAC (Persistent Agent Context) identifier - links to agent/entity being monitored"
    end

    attribute :domain, :atom do
      allow_nil? false
      constraints one_of: [:ml_pipeline, :crown, :flow, :bolt, :gate, :grid, :link, :block, :cerebros]
      description "Domain being observed"
    end

    attribute :tick, :integer do
      allow_nil? false
      default 0
      description "Monotonic tick counter for this domain"
    end

    # --- Cinderforge Observables ---

    attribute :plv, :float do
      description "Phase Locking Value [0.0-1.0] - synchrony measure"
      constraints min: 0.0, max: 1.0
    end

    attribute :sigma, :float do
      description "Token entropy ratio (σ) - propagation balance"
      constraints min: 0.0
    end

    attribute :lambda, :float do
      description "Local FTLE estimate (λ̂) - stability indicator"
    end

    attribute :rtau, :float do
      description "Resonance index (Rτ) - cross-layer energy transfer"
      constraints min: 0.0
    end

    attribute :entropy, :float do
      description "Shannon entropy of activation distribution"
      constraints min: 0.0
    end

    # --- Multi-Manifold Clustering (HC-22A) ---

    attribute :manifold_id, :integer do
      description "Cluster/manifold assignment from UMAP/HDBSCAN analysis"
    end

    attribute :cluster_stability, :float do
      description "Stability score for current cluster assignment [0.0-1.0]"
      constraints min: 0.0, max: 1.0
    end

    attribute :manifold_distance, :float do
      description "Distance to nearest manifold centroid (embedding space)"
      constraints min: 0.0
    end

    attribute :simplex_degree, :integer do
      description "Degree in simplex graph (number of connected neighbors)"
      constraints min: 0
    end

    # --- Health Status ---

    attribute :band_status, :atom do
      allow_nil? false
      default :unknown
      constraints one_of: [:healthy, :loop_detected, :degenerate, :chaotic_drift, :resonance_spike, :unknown]
      description "Overall health classification based on observables"
    end

    attribute :intervention_triggered, :boolean do
      default false
      description "Whether this observation triggered an intervention"
    end

    attribute :intervention_type, :atom do
      constraints one_of: [:apply_phase_bias, :throttle, :boost, :stabilize, nil]
      description "Type of intervention triggered (if any)"
    end

    # --- Additional Context ---

    attribute :activations_shape, :map do
      default %{}
      description "Shape of activations tensor observed (for debugging)"
    end

    attribute :metadata, :map do
      default %{}
      description "Additional observation metadata"
    end

    timestamps()
  end

  relationships do
    belongs_to :snapshot, Thunderline.Thunderbolt.Resources.UpmSnapshot do
      attribute_type :uuid
      allow_nil? true
      description "Optional link to UPM snapshot active at observation time"
    end
  end

  identities do
    identity :unique_observation, [:pac_id, :domain, :tick]
  end

  # --- Private Helpers ---

  # Compute band_status from observables if not explicitly set
  defp maybe_compute_band_status(changeset) do
    case Ash.Changeset.get_attribute(changeset, :band_status) do
      :unknown ->
        plv = Ash.Changeset.get_attribute(changeset, :plv) || 0.0
        sigma = Ash.Changeset.get_attribute(changeset, :sigma) || 1.0
        lambda = Ash.Changeset.get_attribute(changeset, :lambda) || 0.0

        status =
          cond do
            plv > 0.9 -> :loop_detected
            lambda > 0.1 -> :chaotic_drift
            sigma > 1.5 or sigma < 0.5 -> :degenerate
            true -> :healthy
          end

        Ash.Changeset.change_attribute(changeset, :band_status, status)

      _ ->
        changeset
    end
  end
end
