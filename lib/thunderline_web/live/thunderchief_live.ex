defmodule ThunderlineWeb.ThunderchiefLive do
  @moduledoc """
  ThunderChief - The AI Orchestrator Interface

  A glassmorphic chat interface that serves as the primary user interaction point
  with Thunderline's hierarchical agent system. Users communicate with the Prism Chief,
  which delegates to domain-specific ThunderChiefs as needed.

  ## Architecture

      User Input (NLP)
          ↓
      Prism Chief (UI Orchestrator)
          ↓
      Domain Chiefs (Crown, Bolt, Flow, etc.)
          ↓
      Execution & Feedback
          ↓
      Real-time Event Stream to UI

  ## Design Philosophy

  - Child-simple UX: Type naturally, watch magic happen
  - Real-time feedback: See events flow through domains
  - Progressive disclosure: Simple by default, power when needed
  """

  use ThunderlineWeb, :live_view

  # EventBus and Event are available for future real-time integrations
  # alias Thunderline.Thunderflow.EventBus
  # alias Thunderline.Event

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to relevant event streams for real-time updates
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:ai")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:crown")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:prism")
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderchief:responses")
    end

    socket =
      socket
      |> assign(:page_title, "ThunderChief")
      |> assign(:input_value, "")
      |> assign(:is_typing, false)
      |> assign(:active_chief, "prism")
      |> assign(:processing_domains, [])
      |> assign(:show_event_flow, false)
      |> assign(:connection_status, :connected)
      |> assign(:messages_empty?, true)
      |> stream(:messages, [])
      |> stream(:events, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="tl-chat-container" data-theme="thunderline">
      <%!-- Animated Background Grid --%>
      <div class="absolute inset-0 tl-scanlines pointer-events-none z-0"></div>

      <%!-- Header --%>
      <header class="tl-chat-header">
        <div class="tl-chat-header__avatar">
          <svg class="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
            <path d="M13 3L4 14h7l-2 7 9-11h-7l2-7z" />
          </svg>
        </div>

        <div class="flex-1">
          <h1 class="tl-chat-header__title tl-gradient-text">ThunderChief</h1>
          <div class="tl-chat-header__status">
            <span class="tl-chat-header__status-dot"></span>
            <span class="text-sm text-gray-400">
              <%= if @active_chief == "prism" do %>
                Prism Chief Active
              <% else %>
                Delegating to {String.capitalize(@active_chief)} Chief
              <% end %>
            </span>
          </div>
        </div>

        <%!-- Domain Activity Indicators --%>
        <div class="flex items-center gap-2">
          <%= for domain <- @processing_domains do %>
            <.domain_indicator domain={domain} />
          <% end %>
        </div>

        <%!-- Event Flow Toggle --%>
        <button
          phx-click="toggle_event_flow"
          class="tl-btn tl-btn--cyan"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 10V3L4 14h7v7l9-11h-7z"
            />
          </svg>
        </button>
      </header>

      <%!-- Messages Area --%>
      <div
        class="tl-chat-messages"
        id="messages"
        phx-hook="AutoScroll"
        phx-update="stream"
      >
        <%!-- Welcome Message (shows only when stream is empty) --%>
        <div class={"hidden #{if @messages_empty?, do: "!block"}"}>
          <.welcome_message />
        </div>

        <%!-- Message Stream --%>
        <%= for {id, message} <- @streams.messages do %>
          <.message_bubble id={id} message={message} />
        <% end %>

        <%!-- Typing Indicator --%>
        <%= if @is_typing do %>
          <.typing_indicator chief={@active_chief} />
        <% end %>
      </div>

      <%!-- Input Area --%>
      <div class="tl-chat-input">
        <%!-- Active Chief Indicator --%>
        <div class="flex items-center gap-2 mb-2">
          <.chief_indicator chief={@active_chief} domains={@processing_domains} />
        </div>

        <form phx-submit="send_message" class="tl-chat-input__wrapper">
          <input
            type="text"
            name="message"
            value={@input_value}
            placeholder="Ask ThunderChief anything..."
            autocomplete="off"
            phx-change="update_input"
            class="tl-chat-input__field"
          />
          <button type="submit" class="tl-chat-input__send" aria-label="Send message">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"
              />
            </svg>
          </button>
        </form>
      </div>

      <%!-- Event Flow Sidebar --%>
      <aside class={"tl-event-flow #{if @show_event_flow, do: "tl-event-flow--open"}"}>
        <div class="tl-event-flow__header">
          <h2 class="tl-event-flow__title">Event Flow</h2>
          <button phx-click="toggle_event_flow" class="text-gray-400 hover:text-white">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        <div id="event-flow-items" phx-update="stream">
          <%= for {id, event} <- @streams.events do %>
            <.event_item id={id} event={event} />
          <% end %>
        </div>
      </aside>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # COMPONENTS
  # ═══════════════════════════════════════════════════════════════════════════

  defp welcome_message(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center flex-1 text-center px-8 py-16">
      <div class="w-24 h-24 rounded-full bg-gradient-to-br from-purple-500 to-cyan-400 flex items-center justify-center mb-6 shadow-lg shadow-purple-500/30 animate-pulse">
        <svg class="w-12 h-12 text-black" viewBox="0 0 24 24" fill="currentColor">
          <path d="M13 3L4 14h7l-2 7 9-11h-7l2-7z" />
        </svg>
      </div>

      <h2 class="text-3xl font-bold tl-gradient-text mb-4">
        Welcome to ThunderChief
      </h2>

      <p class="text-gray-400 max-w-md mb-8">
        I'm your AI orchestrator. Ask me anything and I'll coordinate
        with the domain chiefs to get things done.
      </p>

      <div class="flex flex-wrap justify-center gap-2">
        <.suggestion_chip text="What can you do?" />
        <.suggestion_chip text="Show system status" />
        <.suggestion_chip text="Train a new model" />
        <.suggestion_chip text="Run an experiment" />
      </div>
    </div>
    """
  end

  defp suggestion_chip(assigns) do
    ~H"""
    <button
      phx-click="send_suggestion"
      phx-value-text={@text}
      class="tl-btn text-sm"
    >
      {@text}
    </button>
    """
  end

  defp message_bubble(assigns) do
    ~H"""
    <div
      id={@id}
      class={"tl-message #{if @message.role == :user, do: "tl-message--user", else: "tl-message--agent"}"}
    >
      <div class="tl-message__bubble">
        <%= if @message.chief && @message.role == :agent do %>
          <div class="flex items-center gap-2 mb-2 text-xs opacity-70">
            <span class="tl-neon-cyan font-semibold uppercase">{@message.chief}</span>
            <span>Chief</span>
          </div>
        <% end %>
        <div class="prose prose-invert prose-sm max-w-none">
          {raw(format_message(@message.content))}
        </div>
        <%= if @message.processing_time do %>
          <div class="text-xs opacity-50 mt-2">
            Processed in {@message.processing_time}ms
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp typing_indicator(assigns) do
    ~H"""
    <div class="tl-message tl-message--agent">
      <div class="tl-message__bubble">
        <div class="flex items-center gap-2 mb-2 text-xs opacity-70">
          <span class="tl-neon-cyan font-semibold uppercase">{@chief}</span>
          <span>Chief is thinking...</span>
        </div>
        <div class="tl-typing">
          <span class="tl-typing__dot"></span>
          <span class="tl-typing__dot"></span>
          <span class="tl-typing__dot"></span>
        </div>
      </div>
    </div>
    """
  end

  defp chief_indicator(assigns) do
    ~H"""
    <div class="tl-chief-indicator">
      <div class="tl-chief-indicator__icon"></div>
      <span>Active:</span>
      <span class="tl-chief-indicator__domain">{@chief}</span>
      <%= for domain <- @domains do %>
        <span class="ml-2 px-2 py-0.5 rounded-full text-xs bg-purple-500/20 text-purple-300 animate-pulse">
          {domain}
        </span>
      <% end %>
    </div>
    """
  end

  defp domain_indicator(assigns) do
    ~H"""
    <div
      class={"w-3 h-3 rounded-full animate-pulse #{domain_color(@domain)}"}
      title={"#{@domain} chief processing"}
    >
    </div>
    """
  end

  defp event_item(assigns) do
    ~H"""
    <div id={@id} class={"tl-event-item tl-event-item--#{@event.domain}"}>
      <div class="tl-event-item__domain">{@event.domain}</div>
      <div class="tl-event-item__name">{@event.name}</div>
      <div class="tl-event-item__time">{format_time(@event.timestamp)}</div>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EVENT HANDLERS
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    # Create user message
    user_message = %{
      id: generate_id(),
      role: :user,
      content: message,
      chief: nil,
      processing_time: nil,
      timestamp: DateTime.utc_now()
    }

    # Simulate ThunderChief processing
    send(self(), {:process_message, message})

    socket =
      socket
      |> stream_insert(:messages, user_message)
      |> assign(:input_value, "")
      |> assign(:is_typing, true)
      |> assign(:messages_empty?, false)

    {:noreply, socket}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("send_suggestion", %{"text" => text}, socket) do
    handle_event("send_message", %{"message" => text}, socket)
  end

  @impl true
  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input_value, value)}
  end

  @impl true
  def handle_event("toggle_event_flow", _params, socket) do
    {:noreply, assign(socket, :show_event_flow, !socket.assigns.show_event_flow)}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MESSAGE PROCESSING
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def handle_info({:process_message, message}, socket) do
    start_time = System.monotonic_time(:millisecond)

    # Determine which domain chief to delegate to
    {chief, domains} = route_to_chief(message)

    socket = assign(socket, :processing_domains, domains)

    # Simulate domain processing with realistic delay
    Process.send_after(self(), {:chief_response, message, chief, start_time}, 1500)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chief_response, _original_message, chief, start_time}, socket) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    # Generate response based on chief
    response_content = generate_chief_response(chief)

    agent_message = %{
      id: generate_id(),
      role: :agent,
      content: response_content,
      chief: chief,
      processing_time: processing_time,
      timestamp: DateTime.utc_now()
    }

    # Create event for the event flow
    event = %{
      id: generate_id(),
      domain: chief,
      name: "response_generated",
      timestamp: DateTime.utc_now()
    }

    socket =
      socket
      |> stream_insert(:messages, agent_message)
      |> stream_insert(:events, event, at: 0)
      |> assign(:is_typing, false)
      |> assign(:processing_domains, [])
      |> assign(:active_chief, "prism")

    {:noreply, socket}
  end

  # Handle EventBus broadcasts
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "events:" <> domain, payload: payload}, socket) do
    event = %{
      id: generate_id(),
      domain: domain,
      name: Map.get(payload, :name, "unknown"),
      timestamp: DateTime.utc_now()
    }

    {:noreply, stream_insert(socket, :events, event, at: 0)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ═══════════════════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  defp route_to_chief(message) do
    message_lower = String.downcase(message)

    cond do
      String.contains?(message_lower, ["train", "model", "ml", "learning"]) ->
        {"bolt", ["bolt", "flow"]}

      String.contains?(message_lower, ["policy", "govern", "orchestrat"]) ->
        {"crown", ["crown"]}

      String.contains?(message_lower, ["store", "persist", "data", "database"]) ->
        {"block", ["block"]}

      String.contains?(message_lower, ["event", "stream", "pipeline"]) ->
        {"flow", ["flow"]}

      String.contains?(message_lower, ["api", "external", "gateway"]) ->
        {"gate", ["gate"]}

      String.contains?(message_lower, ["workflow", "dag", "orchestration"]) ->
        {"vine", ["vine", "crown"]}

      String.contains?(message_lower, ["status", "system", "health"]) ->
        {"prism", ["prism", "core"]}

      true ->
        {"prism", ["prism"]}
    end
  end

  defp generate_chief_response(chief) do
    responses = %{
      "prism" => """
      I'm the Prism Chief, your primary interface to the Thunderline system.

      I can help you with:
      - **System status** and health monitoring
      - **Routing requests** to specialized domain chiefs
      - **Visualizing** event flows and data patterns
      - **Answering questions** about Thunderline capabilities

      What would you like to explore?
      """,
      "bolt" => """
      ⚡ **Bolt Chief** here - I handle ML execution, model training, and saga orchestration.

      I've got access to:
      - The **Unified Persistent Model** (UPM) for online learning
      - **Cerebros** for neural inference
      - **Saga orchestration** for complex multi-step workflows

      The UPM system is currently at 95% completion and ready for shadow deployment.
      Would you like me to start a training run or check model status?
      """,
      "crown" => """
      👑 **Crown Chief** reporting - I oversee AI governance and orchestration.

      My domain includes:
      - **Policy enforcement** for model deployments
      - **Decision architecture** and reasoning chains
      - **Multi-agent coordination** across domains

      All governance checks are currently passing. How can I assist?
      """,
      "block" => """
      🧱 **Block Chief** at your service - I manage secure data persistence.

      I handle:
      - **Ash resources** and their persistence
      - **Event sourcing** via AshEvents
      - **State reconstruction** from historical events

      Database connections are healthy. What data operation do you need?
      """,
      "flow" => """
      🌊 **Flow Chief** here - I coordinate event streaming and data pipelines.

      Active systems:
      - **EventBus** - Cross-domain event routing
      - **MnesiaProducer** - High-throughput event queuing
      - **Feature Windows** - ML training data assembly

      Event throughput is nominal. Need to trace an event or check pipeline status?
      """,
      "gate" => """
      🚪 **Gate Chief** responding - I manage external integrations and security.

      My responsibilities:
      - **API gateways** for external systems
      - **Authentication** and authorization
      - **Rate limiting** and security policies

      All external connections are secure. What integration do you need?
      """,
      "vine" => """
      🌿 **Vine Chief** here - I handle DAG workflows and orchestration edges.

      I manage:
      - **Workflow graphs** for complex operations
      - **TAK persistence** for operation history
      - **Edge coordination** between domains

      Ready to design or execute a workflow. What's the task?
      """
    }

    Map.get(responses, chief, responses["prism"])
  end

  defp format_message(content) do
    # Simple markdown-like formatting
    content
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/`(.+?)`/, "<code class=\"bg-purple-900/50 px-1 rounded\">\\1</code>")
    |> String.replace(~r/^- (.+)$/m, "<li class=\"ml-4\">\\1</li>")
    |> String.replace("\n\n", "</p><p class=\"mt-2\">")
    |> then(&"<p>#{&1}</p>")
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp domain_color(domain) do
    case domain do
      "prism" -> "bg-cyan-400 shadow-cyan-400/50"
      "bolt" -> "bg-yellow-400 shadow-yellow-400/50"
      "crown" -> "bg-purple-400 shadow-purple-400/50"
      "flow" -> "bg-blue-400 shadow-blue-400/50"
      "block" -> "bg-green-400 shadow-green-400/50"
      "gate" -> "bg-orange-400 shadow-orange-400/50"
      "vine" -> "bg-emerald-400 shadow-emerald-400/50"
      _ -> "bg-gray-400 shadow-gray-400/50"
    end
  end
end
