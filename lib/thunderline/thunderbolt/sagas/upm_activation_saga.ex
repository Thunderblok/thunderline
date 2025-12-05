defmodule Thunderline.Thunderbolt.Sagas.UPMActivationSaga do
  @moduledoc """
  Reactor saga for Unified Persistent Model (UPM) promotion workflow.

  This saga manages the complex multi-step process of promoting a shadow-trained
  UPM snapshot to active status, including:
  - Drift validation
  - ThunderCrown policy evaluation
  - Snapshot activation
  - Adapter synchronization
  - Rollback on failure

  ## Workflow Steps

  1. **Load Shadow Snapshot** - Retrieve candidate snapshot from ThunderBlock
  2. **Validate Drift** - Check drift metrics against thresholds
  3. **Policy Check** - ThunderCrown evaluates activation eligibility
  4. **Activate Snapshot** - Promote to active status
  5. **Sync Adapters** - Update ThunderBlock agents with new embeddings
  6. **Emit Activation Event** - Publish success to EventBus

  ## Compensation Strategy

  If activation fails after snapshot promotion:
  - Revert snapshot to shadow status
  - Rollback adapter configurations
  - Restore previous active snapshot
  - Log incident for audit

  ## Usage

      alias Thunderline.Thunderbolt.Sagas.UPMActivationSaga

      inputs = %{
        snapshot_id: "snap_123",
        correlation_id: Thunderline.UUID.v7(),
        max_drift_score: 0.15
      }

      case Reactor.run(UPMActivationSaga, inputs) do
        {:ok, %{snapshot: snapshot, adapters: adapters}} ->
          {:ok, snapshot}

        {:error, reason} ->
          Logger.error("UPM activation failed: \#{inspect(reason)}")
          {:error, :activation_failed}
      end
  """

  use Reactor, extensions: [Reactor.Dsl]

  require Logger
  alias Thunderline.Thunderbolt.Resources.UpmSnapshot
  alias Thunderline.Thunderbolt.Resources.UpmAdapter
  alias Thunderline.Thunderbolt.Resources.UpmDriftWindow

  middlewares do
    middleware Thunderline.Thunderbolt.Sagas.TelemetryMiddleware
    middleware Reactor.Middleware.Telemetry
  end

  input :snapshot_id
  input :correlation_id
  input :causation_id
  input :max_drift_score

  step :load_snapshot do
    argument :snapshot_id, input(:snapshot_id)

    run fn %{snapshot_id: snapshot_id}, _ ->
      case Ash.get(UpmSnapshot, snapshot_id) do
        {:ok, snapshot} ->
          if snapshot.status == :shadow do
            {:ok, snapshot}
          else
            {:error, {:invalid_status, snapshot.status}}
          end

        {:error, reason} ->
          {:error, {:snapshot_not_found, reason}}
      end
    end
  end

  step :validate_drift do
    argument :snapshot, result(:load_snapshot)
    argument :max_drift, input(:max_drift_score)

    run fn %{snapshot: snapshot, max_drift: max_drift}, _ ->
      require Ash.Query
      # Query recent drift window
      query =
        UpmDriftWindow
        |> Ash.Query.filter(snapshot_id == ^snapshot.id)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(1)

      case Ash.read(query) do
        {:ok, [drift_window | _]} ->
          drift_score = drift_window.drift_score || 0.0

          if Decimal.compare(drift_score, Decimal.from_float(max_drift)) == :lt do
            Logger.info("Drift validation passed: #{drift_score} < #{max_drift}")
            {:ok, %{snapshot: snapshot, drift_score: drift_score}}
          else
            Logger.warning("Drift validation failed: #{drift_score} >= #{max_drift}")
            {:error, {:drift_threshold_exceeded, drift_score}}
          end

        {:ok, []} ->
          Logger.warning("No drift window found for snapshot #{snapshot.id}")
          {:error, :no_drift_data}

        {:error, reason} ->
          {:error, {:drift_query_failed, reason}}
      end
    end
  end

  step :policy_check do
    argument :validation_result, result(:validate_drift)

    run fn %{validation_result: %{snapshot: snapshot, drift_score: drift_score}}, context ->
      # Check ThunderCrown for policy evaluation if available
      policy_decision =
        case evaluate_crown_policy(snapshot, drift_score, context) do
          {:ok, decision} ->
            decision

          {:error, _reason} ->
            # Fallback to auto-approval when Crown unavailable
            %{
              approved: true,
              reason: "Auto-approved (drift: #{drift_score}) - Crown unavailable",
              policy_id: Thunderline.UUID.v7()
            }
        end

      if policy_decision.approved do
        Logger.info("Policy check passed for snapshot #{snapshot.id}")
        {:ok, %{snapshot: snapshot, policy: policy_decision}}
      else
        Logger.warning("Policy check rejected snapshot #{snapshot.id}")
        {:error, {:policy_rejected, policy_decision.reason}}
      end
    end
  end

  step :deactivate_previous do
    argument :policy_result, result(:policy_check)

    run fn %{policy_result: %{snapshot: _snapshot}}, _ ->
      require Ash.Query
      # Find currently active snapshot and demote it
      query = UpmSnapshot |> Ash.Query.filter(status == :active)

      case Ash.read(query) do
        {:ok, [active_snapshot | _]} ->
          case Ash.update(active_snapshot, %{status: :archived}) do
            {:ok, archived} ->
              Logger.info("Previous snapshot #{archived.id} archived")
              {:ok, %{previous: archived}}

            {:error, reason} ->
              {:error, {:archive_failed, reason}}
          end

        {:ok, []} ->
          Logger.info("No previous active snapshot to archive")
          {:ok, %{previous: nil}}

        {:error, reason} ->
          {:error, {:query_active_failed, reason}}
      end
    end

    compensate fn %{previous: previous}, _ ->
      if previous do
        Logger.warning("Compensating: restoring previous snapshot #{previous.id}")

        case Ash.update(previous, %{status: :active}) do
          {:ok, _} -> {:ok, :compensated}
          {:error, reason} -> {:error, {:restore_failed, reason}}
        end
      else
        {:ok, :no_compensation_needed}
      end
    end
  end

  step :activate_snapshot do
    argument :policy_result, result(:policy_check)

    run fn %{policy_result: %{snapshot: snapshot}}, _ ->
      case Ash.update(snapshot, %{status: :active, activated_at: DateTime.utc_now()}) do
        {:ok, activated} ->
          Logger.info("Snapshot #{activated.id} activated")
          {:ok, activated}

        {:error, reason} ->
          {:error, {:activation_failed, reason}}
      end
    end

    compensate fn snapshot, _ ->
      Logger.warning("Compensating: reverting snapshot #{snapshot.id} to shadow")

      case Ash.update(snapshot, %{status: :shadow, activated_at: nil}) do
        {:ok, _} -> {:ok, :compensated}
        {:error, reason} -> {:error, {:revert_failed, reason}}
      end
    end
  end

  step :sync_adapters do
    argument :snapshot, result(:activate_snapshot)

    run fn %{snapshot: snapshot}, _ ->
      # Query all adapters and update their snapshot reference
      case Ash.read(UpmAdapter) do
        {:ok, adapters} ->
          results =
            Enum.map(adapters, fn adapter ->
              Ash.update(adapter, %{active_snapshot_id: snapshot.id})
            end)

          failures = Enum.filter(results, &match?({:error, _}, &1))

          if Enum.empty?(failures) do
            Logger.info("Synced #{length(adapters)} adapters to snapshot #{snapshot.id}")
            {:ok, %{adapters: adapters, count: length(adapters)}}
          else
            Logger.error("Adapter sync had #{length(failures)} failures")
            {:error, {:adapter_sync_partial_failure, failures}}
          end

        {:error, reason} ->
          {:error, {:adapter_query_failed, reason}}
      end
    end

    compensate fn _adapters, _ ->
      # Restore previous adapter configurations by reverting snapshot references
      Logger.warning("Compensating: rolling back adapter sync")

      # Find adapters and restore their previous snapshot reference
      case Ash.read(UpmAdapter) do
        {:ok, adapters} ->
          # For each adapter, we need to restore its previous state
          # Since we don't have the previous snapshot_id stored,
          # we mark them as needing resync
          Enum.each(adapters, fn adapter ->
            case Ash.update(adapter, %{active_snapshot_id: nil, needs_resync: true}) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                Logger.error("Failed to reset adapter #{adapter.id}: #{inspect(reason)}")
            end
          end)

          {:ok, :compensated}

        {:error, reason} ->
          Logger.error("Failed to query adapters for compensation: #{inspect(reason)}")
          {:error, {:compensation_failed, reason}}
      end
    end
  end

  step :emit_activation_event do
    argument :snapshot, result(:activate_snapshot)
    argument :adapters, result(:sync_adapters)
    argument :correlation_id, input(:correlation_id)
    argument :causation_id, input(:causation_id)

    run fn %{
             snapshot: snapshot,
             adapters: adapters,
             correlation_id: correlation_id,
             causation_id: causation_id
           },
           _ ->
      event_attrs = %{
        name: "ai.upm.snapshot.activated",
        type: :upm_lifecycle,
        domain: :bolt,
        source: "UPMActivationSaga",
        correlation_id: correlation_id,
        causation_id: causation_id,
        payload: %{
          snapshot_id: snapshot.id,
          activated_at: snapshot.activated_at,
          adapter_count: adapters.count
        },
        meta: %{
          pipeline: :realtime
        }
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, event} ->
          Thunderline.Thunderflow.EventBus.publish_event(event)
          {:ok, %{snapshot: snapshot, adapters: adapters}}

        {:error, reason} ->
          Logger.warning("Failed to emit activation event: #{inspect(reason)}")
          {:ok, %{snapshot: snapshot, adapters: adapters}}
      end
    end
  end

  return :emit_activation_event

  # Private helpers

  defp evaluate_crown_policy(snapshot, drift_score, context) do
    # Attempt to call ThunderCrown policy evaluation
    correlation_id = Map.get(context, :correlation_id, Thunderline.UUID.v7())

    policy_request = %{
      policy_type: :upm_activation,
      subject: %{
        snapshot_id: snapshot.id,
        drift_score: drift_score,
        status: snapshot.status
      },
      context: %{
        correlation_id: correlation_id,
        timestamp: DateTime.utc_now()
      }
    }

    # Check if ThunderCrown PolicyEngine is available
    if Code.ensure_loaded?(Thunderline.Thundercrown.PolicyEngine) do
      case Thunderline.Thundercrown.PolicyEngine.evaluate(policy_request) do
        {:ok, %{decision: :allow, reason: reason}} ->
          {:ok, %{approved: true, reason: reason, policy_id: Thunderline.UUID.v7()}}

        {:ok, %{decision: :deny, reason: reason}} ->
          {:ok, %{approved: false, reason: reason, policy_id: Thunderline.UUID.v7()}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # ThunderCrown not available, return error to trigger fallback
      {:error, :crown_unavailable}
    end
  end
end
