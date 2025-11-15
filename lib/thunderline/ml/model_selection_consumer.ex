defmodule Thunderline.Thunderbolt.ML.ModelSelectionConsumer do
  @moduledoc """
  Broadway consumer that processes model evaluation events through the ML Controller.

  ## Event Flow

  Input:  `ml.model.evaluation_ready` - Model outputs ready for selection
  Output: `ml.model.selected` - Chosen model + metadata

  ## Responsibilities

  - Batch model outputs from multiple models
  - Process through ML Controller for adaptive selection
  - Execute chosen model for final prediction
  - Emit selection results with telemetry

  ## Event Schema

  ### Input Event

      %Event{
        name: "ml.model.evaluation_ready",
        source: "ml.orchestrator",
        payload: %{
          features: %Nx.Tensor{},        # Input features for models
          model_outputs: %{               # Outputs from candidate models
            model_a: %Nx.Tensor{},
            model_b: %Nx.Tensor{}
          },
          target_dist: %Nx.Tensor{},      # Expected output distribution
          context: %{                     # Additional metadata
            correlation_id: "...",
            request_id: "..."
          }
        }
      }

  ### Output Event

      %Event{
        name: "ml.model.selected",
        source: "ml.controller",
        payload: %{
          chosen_model: :model_a,
          probabilities: %{model_a: 0.65, model_b: 0.35},
          distances: %{model_a: 0.023, model_b: 0.045},
          iteration: 42,
          reward_model: :model_a
        },
        correlation_id: "...",
        causation_id: "..."
      }

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.ML.ModelSelectionConsumer,
        controller_pid: :ml_controller,
        batch_size: 10,
        batch_timeout: 1_000,
        concurrency: 2

  ## Supervision

  Add to application supervision tree:

      {Thunderline.Thunderbolt.ML.ModelSelectionConsumer, controller_pid: controller_pid}
  """

  use Broadway

  alias Broadway.Message
  alias Thunderline.Event
  alias Thunderline.Thunderbolt.ML.Controller

  require Logger

  @default_config [
    batch_size: 10,
    batch_timeout: 1_000,
    concurrency: 2,
    max_demand: 10
  ]

  def start_link(opts) do
    config = Application.get_env(:thunderline, __MODULE__, @default_config)
    controller_pid = Keyword.get(opts, :controller_pid) || Process.whereis(:ml_controller)

    unless controller_pid do
      raise ArgumentError, "ML Controller process not found. Ensure it's started before ModelSelectionConsumer."
    end

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {Thunderflow.MnesiaProducer,
           table: Thunderflow.MnesiaProducer,
           poll_interval: 1_000,
           max_batch_size: Keyword.get(config, :batch_size, 10),
           broadway_name: __MODULE__},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: Keyword.get(config, :concurrency, 2),
          max_demand: Keyword.get(config, :max_demand, 10)
        ]
      ],
      batchers: [
        model_selection: [
          batch_size: Keyword.get(config, :batch_size, 10),
          batch_timeout: Keyword.get(config, :batch_timeout, 1_000)
        ]
      ],
      context: %{controller_pid: controller_pid}
    )
  end

  @impl true
  def handle_message(_processor, message, context) do
    case validate_and_process(message.data, context) do
      {:ok, result} ->
        message
        |> Message.put_data(result)
        |> Message.put_batch_key(:model_selection)

      {:error, reason} ->
        Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:model_selection, messages, _batch_info, context) do
    # Process batch of model evaluations through Controller
    Enum.map(messages, fn message ->
      emit_selection_event(message.data, context)
      message
    end)
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn message ->
      route_to_dlq(message)
    end)

    messages
  end

  # Private functions

  defp validate_and_process(event, %{controller_pid: controller_pid}) do
    with {:ok, validated} <- validate_event(event),
         {:ok, result} <- process_through_controller(validated, controller_pid) do
      {:ok, result}
    end
  end

  defp validate_event(%Event{name: name} = event)
       when name in ["ml.model.evaluation_ready", "ml.model.eval"] do
    case event.payload do
      %{model_outputs: outputs, target_dist: target} = payload
      when is_map(outputs) ->
        # Validate tensor shapes
        with :ok <- validate_tensors(outputs),
             :ok <- validate_target(target) do
          correlation_id = event.correlation_id || event.id
          causation_id = event.id

          {:ok,
           %{
             model_outputs: outputs,
             target_dist: target,
             features: Map.get(payload, :features),
             context: Map.get(payload, :context, %{}),
             correlation_id: correlation_id,
             causation_id: causation_id
           }}
        end

      _other ->
        {:error, :invalid_event_payload}
    end
  end

  defp validate_event(%Event{} = event) do
    {:error, {:unexpected_event_type, event.name || event.type}}
  end

  defp validate_event(other) do
    {:error, {:invalid_event, other}}
  end

  defp validate_tensors(outputs) when is_map(outputs) do
    # Check that all outputs are Nx tensors
    if Enum.all?(outputs, fn {_k, v} -> is_struct(v, Nx.Tensor) end) do
      :ok
    else
      {:error, :invalid_tensor_outputs}
    end
  end

  defp validate_target(target) do
    if is_struct(target, Nx.Tensor) do
      :ok
    else
      {:error, :invalid_target_tensor}
    end
  end

  defp process_through_controller(validated, controller_pid) do
    batch_data = %{
      model_outputs: validated.model_outputs,
      target_dist: validated.target_dist
    }

    case Controller.process_batch(controller_pid, batch_data) do
      {:ok, result} ->
        # Enrich result with original context
        enriched =
          Map.merge(result, %{
            correlation_id: validated.correlation_id,
            causation_id: validated.causation_id,
            context: validated.context
          })

        {:ok, enriched}

      {:error, reason} ->
        {:error, {:controller_error, reason}}
    end
  end

  defp emit_selection_event(result, _context) do
    event_attrs = %{
      name: "ml.model.selected",
      source: "ml.controller",
      payload: %{
        chosen_model: result.chosen_model,
        probabilities: result.probabilities,
        distances: result.distances,
        iteration: result.iteration,
        reward_model: result.reward_model
      },
      correlation_id: result.correlation_id,
      causation_id: result.causation_id
    }

    case Event.new(event_attrs) do
      {:ok, event} ->
        Thunderline.EventBus.publish_event(event)

        Logger.info("Model selected",
          model: result.chosen_model,
          iteration: result.iteration,
          probabilities: result.probabilities
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to create selection event", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp route_to_dlq(message) do
    error_metadata = %{
      reason: message.status,
      original_event: message.data,
      timestamp: DateTime.utc_now(),
      processor: __MODULE__
    }

    dlq_event_attrs = %{
      name: "ml.dlq.selection_failed",
      source: "ml.controller",
      payload: %{
        error: inspect(message.status),
        event_id: extract_event_id(message.data)
      },
      metadata: error_metadata
    }

    case Event.new(dlq_event_attrs) do
      {:ok, dlq_event} ->
        Thunderline.EventBus.publish_event(dlq_event)

        Logger.warning("Model selection failed, routed to DLQ",
          error: inspect(message.status),
          event: extract_event_id(message.data)
        )

      {:error, reason} ->
        Logger.error("Failed to create DLQ event", reason: inspect(reason))
    end
  end

  defp extract_event_id(%Event{id: id}), do: id
  defp extract_event_id(_), do: nil
end
