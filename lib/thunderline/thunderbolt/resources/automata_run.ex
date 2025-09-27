defmodule Thunderline.Thunderbolt.Resources.AutomataRun do
  @moduledoc "Embedded control resource for Thunderbolt Automata runs. Provides start/stop/snapshot/restore actions."
  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  alias Thunderline.Thunderbolt.CA.RunnerSupervisor

  resource do
    description "Automata run control surface (non-persistent)"
  end

  code_interface do
    define :start, args: [:size, :tick_ms]
    define :stop, args: [:run_id]
    define :snapshot, args: [:run_id]
    define :restore, args: [:run_id, :snapshot_id]
  end

  actions do
    defaults []

    action :start do
      argument :size, :integer, allow_nil?: true, default: 64
      argument :tick_ms, :integer, allow_nil?: true, default: 50

      run fn _input, %{arguments: args} ->
        run_id = Thunderline.UUID.v7()
        _ = RunnerSupervisor.start_run(run_id, size: args.size, tick_ms: args.tick_ms)

        emit_event("system.ca.run.started", %{
          run_id: run_id,
          size: args.size,
          tick_ms: args.tick_ms
        })

        {:ok, %{run_id: run_id}}
      end
    end

    action :stop do
      argument :run_id, :string, allow_nil?: false

      run fn _input, %{arguments: %{run_id: run_id}} ->
        _ = RunnerSupervisor.stop_run(run_id)
        emit_event("system.ca.run.stopped", %{run_id: run_id})
        {:ok, %{run_id: run_id}}
      end
    end

    action :snapshot do
      argument :run_id, :string, allow_nil?: false

      run fn _input, %{arguments: %{run_id: run_id}} ->
        snapshot_id = "snap-" <> String.slice(Thunderline.UUID.v7(), 0, 8)
        emit_event("system.ca.snapshot.created", %{run_id: run_id, snapshot_id: snapshot_id})
        {:ok, %{run_id: run_id, snapshot_id: snapshot_id}}
      end
    end

    action :restore do
      argument :run_id, :string, allow_nil?: false
      argument :snapshot_id, :string, allow_nil?: false

      run fn _input, %{arguments: %{run_id: run_id, snapshot_id: sid}} ->
        emit_event("system.ca.snapshot.restore_requested", %{run_id: run_id, snapshot_id: sid})
        {:ok, %{run_id: run_id, snapshot_id: sid}}
      end
    end
  end

  policies do
    policy action(:*) do
      authorize_if expr(actor(:role) in [:owner, :steward, :system])
      authorize_if expr(not is_nil(actor(:tenant_id)))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :run_id, :string, public?: true
    attribute :snapshot_id, :string, public?: true
  end

  defp emit_event(name, payload) do
    with {:ok, ev} <- Thunderline.Event.new(name: name, source: :bolt, payload: payload) do
      _ =
        Task.start(fn ->
          case Thunderline.EventBus.publish_event(ev) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning("[AutomataRun] publish failed: #{inspect(reason)} name=#{name}")
          end
        end)
    end
  end
end
