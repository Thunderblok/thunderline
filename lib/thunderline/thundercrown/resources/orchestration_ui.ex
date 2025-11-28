defmodule Thunderline.Thundercrown.Resources.OrchestrationUI do
  @moduledoc """
  AshPyro-powered declarative UI for Thunderline orchestration dashboard.

  Provides real-time job monitoring, health checks, and cross-domain coordination
  interfaces using AshPyro's declarative UI DSL.
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thundercrown.Domain

  # Actions for UI interactions
  actions do
    defaults [:read, :create, :update, :destroy]

    action :trigger_cross_domain_operation do
      argument :source_domain, :atom, allow_nil?: false
      argument :target_domain, :atom, allow_nil?: false
      argument :operation_type, :atom, allow_nil?: false
      argument :priority, :atom, default: :normal
      argument :payload, :map, default: %{}

      run fn input, _context ->
        # Trigger cross-domain orchestration via Oban
        params = %{
          source_domain: input.arguments.source_domain,
          target_domain: input.arguments.target_domain,
          operation_type: input.arguments.operation_type,
          priority: input.arguments.priority,
          payload: input.arguments.payload
        }

        case Thunderline.Thundercrown.Orchestrator.enqueue_cross_domain_job(params) do
          {:ok, job} ->
            {:ok, %{job_id: job.id, status: :enqueued}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    action :update_dashboard_config do
      argument :config_updates, :map, allow_nil?: false

      run fn input, _context ->
        current_config = input.resource.dashboard_config || %{}
        new_config = Map.merge(current_config, input.arguments.config_updates)

        case Ash.Changeset.for_update(input.resource, :update, %{dashboard_config: new_config})
             |> Ash.update() do
          {:ok, updated_resource} -> {:ok, updated_resource}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  # extensions: [AshPyro]  # Commented out until AshPyro is available

  #  # AshPyro declarative UI configuration
  #  # pyro do
  #  # (Commented out until AshPyro is available)
  #    # Job Queue Dashboard
  #    component :job_queue_dashboard do
  #      title "Thunderchief Orchestration Control"
  #
  #      section :active_jobs do
  #        title "Active Job Queues"
  #
  #        table :jobs_table do
  #          data_source Thunderchief.Resources.Job, :read
  #          columns [
  #            {:id, "ID"},
  #            {:queue, "Queue"},
  #            {:worker, "Worker"},
  #            {:priority, "Priority"},
  #            {:status, "Status"},
  #            {:domain_context, "Domain"}
  #          ]
  #
  #          actions [
  #            {:retry, "Retry Job"},
  #            {:cancel, "Cancel Job"},
  #            {:priority_boost, "Priority Boost"}
  #          ]
  #
  #          filters [
  #            {:queue, :select, ["default", "thunderbit", "thunderwave", "thunderblock"]},
  #            {:status, :select, ["executing", "scheduled", "retrying", "failed"]},
  #            {:domain_context, :select, ["thunderbit", "thunderwave", "thunderblock", "thundermag"]}
  #          ]
  #        end
  #      end
  #
  #      section :health_monitoring do
  #        title "Cross-Domain Health Status"
  #
  #        grid :health_grid do
  #          data_source Thunderchief.Resources.Health, :read
  #
  #          card_layout do
  #            title_field :domain_name
  #            status_field :health_status
  #            metrics [
  #              {:response_time, "Response Time"},
  #              {:success_rate, "Success Rate"},
  #              {:error_count, "Errors (24h)"}
  #            ]
  #
  #            actions [
  #              {:trigger_health_check, "Health Check"},
  #              {:restart_domain, "Restart Domain"},
  #              {:escalate_alert, "Escalate Alert"}
  #            ]
  #          end
  #        end
  #      end
  #
  #      section :stream_processing do
  #        title "Broadway Stream Processing"
  #
  #        metrics :stream_metrics do
  #          data_source Thunderchief.Resources.Pipeline, :read
  #
  #          chart :throughput_chart do
  #            type :line
  #            x_axis :timestamp
  #            y_axis :events_per_second
  #            title "Stream Throughput (Events/sec)"
  #          end
  #
  #          chart :backpressure_chart do
  #            type :gauge
  #            value_field :backpressure_level
  #            title "System Backpressure"
  #            thresholds [
  #              {0..30, :green, "Healthy"},
  #              {31..70, :yellow, "Warning"},
  #              {71..100, :red, "Critical"}
  #            ]
  #          end
  #        end
  #      end
  #
  #      section :orchestration_controls do
  #        title "Cross-Domain Orchestration"
  #
  #        form :trigger_orchestration do
  #          title "Manual Orchestration Trigger"
  #
  #          fields [
  #            {:source_domain, :select, required: true, options: ["thunderbit", "thunderwave", "thunderblock", "thundermag"]},
  #            {:target_domain, :select, required: true, options: ["thunderbit", "thunderwave", "thunderblock", "thundermag"]},
  #            {:operation_type, :select, required: true, options: ["data_sync", "health_check", "deployment", "backup"]},
  #            {:priority, :select, default: "normal", options: ["low", "normal", "high", "critical"]},
  #            {:payload, :json, required: false}
  #          ]
  #
  #          submit_action :trigger_cross_domain_operation
  #        end
  #
  #        live_updates :orchestration_log do
  #          data_source Thunderchief.Resources.OrchestrationEvent, :read
  #          auto_refresh 5000
  #
  #          timeline_layout do
  #            timestamp_field :occurred_at
  #            title_field :operation_type
  #            description_field :description
  #            status_field :status
  #
  #            filters [
  #              {:status, ["success", "failed", "in_progress"]},
  #              {:operation_type, ["data_sync", "health_check", "deployment"]}
  #            ]
  #          end
  #        end
  #      end
  #    end
  #
  #    # AI Agent Control Panel (for ThunderCrown integration)
  #    component :ai_control_panel do
  #      title "AI Agent Orchestration Control"
  #
  #      section :active_agents do
  #        title "Active AI Agents"
  #
  #        grid :agents_grid do
  #          data_source Thunderchief.Resources.AIAgent, :read
  #
  #          card_layout do
  #            title_field :agent_name
  #            status_field :status
  #            metrics [
  #              {:jobs_completed, "Jobs Completed"},
  #              {:success_rate, "Success Rate"},
  #              {:last_activity, "Last Activity"}
  #            ]
  #
  #            actions [
  #              {:pause_agent, "Pause Agent"},
  #              {:resume_agent, "Resume Agent"},
  #              {:assign_priority_job, "Priority Assignment"}
  #            ]
  #          end
  #        end
  #      end
  #
  #      section :tool_exposure do
  #        title "Exposed Orchestration Tools"
  #
  #        table :tools_table do
  #          data_source Thunderchief.Resources.ExposedTool, :read
  #          columns [
  #            {:tool_name, "Tool Name"},
  #            {:description, "Description"},
  #            {:usage_count, "Usage Count"},
  #            {:last_used, "Last Used"},
  #            {:success_rate, "Success Rate"}
  #          ]
  #
  #          actions [
  #            {:enable_tool, "Enable"},
  #            {:disable_tool, "Disable"},
  #            {:view_usage_logs, "View Logs"}
  #          ]
  #        end
  #      end
  #    end
  #  end

  # Resource attributes for UI state management
  attributes do
    uuid_primary_key :id
    attribute :dashboard_config, :map, default: %{}
    attribute :user_preferences, :map, default: %{}
    attribute :active_filters, :map, default: %{}
    attribute :refresh_interval, :integer, default: 5000

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # Helper functions
  defp priority_to_int(:low), do: 1
  defp priority_to_int(:normal), do: 5
  defp priority_to_int(:high), do: 8
  defp priority_to_int(:critical), do: 10
end
