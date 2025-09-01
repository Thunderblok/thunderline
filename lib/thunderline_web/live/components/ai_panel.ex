defmodule ThunderlineWeb.Live.Components.AIPanel do
  use ThunderlineWeb, :live_component

  alias Thunderline.Thundercrown.Resources.AgentRunner

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
    socket.assigns[:current_user] || Ash.get_actor()
  end

  defp emit(name, payload) do
    with {:ok, ev} <- Thunderline.Event.new(name: name, source: :crown, payload: payload) do
      _ = Task.start(fn -> Thunderline.EventBus.publish_event(ev) end)
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
