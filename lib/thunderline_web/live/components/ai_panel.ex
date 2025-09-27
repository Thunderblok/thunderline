defmodule ThunderlineWeb.Live.Components.AIPanel do
  use ThunderlineWeb, :live_component

  alias Thunderline.Thundercrown.Resources.AgentRunner
  alias ThunderlineWeb.Auth.Actor

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns) |> assign_new(:output, fn -> [] end)}
  end

  @impl true
  def handle_event("run_agent", %{"tool" => tool, "prompt" => prompt}, socket) do
    case AgentRunner.run(%{tool: tool, prompt: prompt}, actor: actor(socket)) do
      {:ok, %{stream_id: sid, correlation_id: corr}} ->
        out = socket.assigns.output ++ ["requested: #{tool} :: stream #{sid}"]
        emit("system.agent.completed", %{tool: tool, correlation_id: corr})
        {:noreply, assign(socket, :output, out)}

      {:error, reason} ->
        out = socket.assigns.output ++ ["failed: #{inspect(reason)}"]
        {:noreply, assign(socket, :output, out)}
    end
  end

  defp actor(socket) do
    cond do
      is_map(socket.assigns[:actor]) ->
        socket.assigns[:actor]

      match?(%{actor: actor_map} when is_map(actor_map), socket.assigns[:actor_ctx]) ->
        socket.assigns.actor_ctx.actor

      is_map(socket.assigns[:current_user]) ->
        Actor.build_actor(socket.assigns[:current_user], %{})

      true ->
        nil
    end
  end

  defp emit(name, payload) do
    with {:ok, ev} <- Thunderline.Event.new(name: name, source: :crown, payload: payload) do
      # We purposely isolate the publish in a Task but still pattern match result inside
      # the spawned process so failures are surfaced via telemetry and logs (no silent drop).
      _ =
        Task.start(fn ->
          case Thunderline.EventBus.publish_event(ev) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              :telemetry.execute(
                [
                  :thunderline,
                  :ui,
                  :event,
                  :publish,
                  :error
                ],
                %{count: 1},
                %{reason: reason, name: name, source: :ai_panel}
              )

              require Logger
              Logger.warning("AIPanel failed to publish event #{name}: #{inspect(reason)}")
          end
        end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <h3 class="text-lg font-semibold">AI Panel</h3>
      <form phx-target={@myself} phx-submit="run_agent" class="space-y-2">
        <select name="tool" class="input">
          <option value="agent.summary">Summary Agent</option>
          <option value="agent.search">Search Agent</option>
        </select>
        <textarea name="prompt" class="input" placeholder="Enter prompt"></textarea>
        <button class="btn">Run</button>
      </form>
      <div class="prose text-sm">
        <pre><%= Enum.join(@output, "\n") %></pre>
      </div>
    </div>
    """
  end
end
