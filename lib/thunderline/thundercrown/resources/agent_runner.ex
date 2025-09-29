defmodule Thunderline.Thundercrown.Resources.AgentRunner do
  @moduledoc "Run approved Jido/AshAI tools under ThunderCrown governance."
  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  require Logger

  alias Jido.Error
  alias Jido.Workflow
  alias Thunderline.Thundercrown.Jido.ActionRegistry

  code_interface do
    define :run, args: [:tool, :prompt]
  end

  actions do
    defaults []

    action :run do
      argument :tool, :string, allow_nil?: false
      argument :prompt, :string, allow_nil?: false
      returns :map

      run fn %{arguments: %{tool: tool, prompt: prompt}}, context ->
        corr = Thunderline.UUID.v7()
        stream_id = build_stream_id(corr)
        actor = Map.get(context, :actor)

        emit_stage(:requested, %{
          tool: tool,
          prompt: truncate_prompt(prompt),
          correlation_id: corr,
          actor_role: actor && Map.get(actor, :role)
        })

        case run_tool(tool, prompt, actor, corr) do
          {:ok, result} ->
            emit_stage(:completed, %{
              tool: tool,
              correlation_id: corr,
              result: truncate_result(result)
            })

            {:ok, %{stream_id: stream_id, correlation_id: corr, result: result}}

          {:error, reason} ->
            emit_stage(:failed, %{
              tool: tool,
              correlation_id: corr,
              error: format_error(reason)
            })

            {:error, reason}
        end
      end
    end
  end

  policies do
    policy action(:run) do
      authorize_if expr(^actor(:role) in [:owner, :steward, :system])
      authorize_if expr(not is_nil(actor(:tenant_id)))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :stream_id, :string, public?: true
    attribute :correlation_id, :string, public?: true
  end

  defp run_tool(tool, prompt, actor, corr) do
    with {:ok, action_module} <- ActionRegistry.resolve(tool),
         {:ok, params} <- decode_prompt(prompt, action_module),
         {:ok, result} <- execute_action(action_module, params, actor, corr) do
      {:ok, Map.put_new(result, :tool, tool)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_prompt(prompt, module) when prompt in [nil, ""] do
    {:ok, %{} |> cast_params(module)}
  end

  defp decode_prompt(prompt, module) do
    case Jason.decode(prompt) do
      {:ok, %{} = params} ->
        {:ok, cast_params(params, module)}

      {:ok, value} ->
        {:error, "Expected JSON object for prompt, got: #{inspect(value)}"}

      {:error, reason} ->
        {:error, "Unable to decode prompt JSON: #{Exception.message(reason)}"}
    end
  end

  defp cast_params(params, module) do
    schema = Map.new(module.schema(), fn {field, opts} -> {field, opts} end)
    schema_lookup = Map.new(schema, fn {field, _opts} -> {to_string(field), field} end)

    Enum.reduce(params, %{}, fn {key, value}, acc ->
      cond do
        is_atom(key) and Map.has_key?(schema, key) ->
          Map.put(acc, key, normalize_value(key, value, schema))

        is_binary(key) and Map.has_key?(schema_lookup, key) ->
          field = Map.fetch!(schema_lookup, key)
          Map.put(acc, field, normalize_value(field, value, schema))

        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp normalize_value(field, value, schema) do
    case schema do
      %{^field => opts} ->
        value
        |> maybe_atomize_map(Keyword.get(opts, :type))

      _ ->
        value
    end
  end

  defp maybe_atomize_map(value, type) when type in [:map, {:map, :any}] and is_map(value) do
    atomize_keys(value)
  end

  defp maybe_atomize_map(value, {:list, :map}) when is_list(value) do
    Enum.map(value, fn
      %{} = map -> atomize_keys(map)
      other -> other
    end)
  end

  defp maybe_atomize_map(value, _type), do: value

  defp atomize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, val}, acc ->
      normalized_key = normalize_key(key)

      normalized_value =
        cond do
          is_map(val) -> atomize_keys(val)
          is_list(val) -> Enum.map(val, &normalize_nested/1)
          true -> val
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: to_existing_or_new_atom(key)
  defp normalize_key(key), do: key

  defp normalize_nested(%{} = value), do: atomize_keys(value)
  defp normalize_nested(list) when is_list(list), do: Enum.map(list, &normalize_nested/1)
  defp normalize_nested(value), do: value

  defp to_existing_or_new_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> String.to_atom(key)
  end

  defp execute_action(module, params, actor, corr) do
    context =
      %{
        actor: actor,
        correlation_id: corr
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    case Workflow.run(module, params, context, timeout: 15_000) do
      {:ok, %{} = result} ->
        {:ok, result}

      {:ok, %{} = result, extras} ->
        {:ok, Map.put(result, :extras, extras)}

      {:ok, result} ->
        {:ok, %{value: result}}

      {:ok, result, extras} ->
        {:ok, %{value: result, extras: extras}}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_stream_id(correlation_id), do: "ai-" <> String.slice(correlation_id, 0, 8)

  defp truncate_prompt(prompt) when is_binary(prompt), do: String.slice(prompt, 0, 160)
  defp truncate_prompt(_), do: nil

  defp truncate_result(%{zones: zones} = result) when is_list(zones) do
    Map.put(result, :zones, Enum.take(zones, 5))
  end

  defp truncate_result(%{} = result) do
    result
    |> Enum.take(10)
    |> Enum.into(%{})
  end

  defp truncate_result(other), do: other

  defp format_error(%Error{} = error), do: error.message
  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp emit_stage(:requested, payload), do: emit("ui.command.agent.requested", payload)
  defp emit_stage(:completed, payload), do: emit("ui.command.agent.completed", payload)
  defp emit_stage(:failed, payload), do: emit("ui.command.agent.failed", payload)

  defp emit(name, payload) do
    with {:ok, ev} <- Thunderline.Event.new(name: name, source: :crown, payload: payload) do
      _ =
        Task.start(fn ->
          case Thunderline.EventBus.publish_event(ev) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "[AgentRunner] async publish failed: #{inspect(reason)} name=#{name}"
              )
          end
        end)
    end
  end
end
