defmodule ThunderlineWeb.WhiteboardLive do
  @moduledoc """
  Real-time collaborative whiteboard with chat for dev team collaboration.

  Features:
  - Canvas drawing with mouse/touch support
  - Real-time stroke broadcasting via PubSub
  - Presence tracking (who's in the room)
  - Text chat sidebar
  - Color picker and drawing tools
  """
  use ThunderlineWeb, :live_view

  alias ThunderlineWeb.Presence

  @topic "whiteboard:dev"

  @impl true
  def mount(_params, _session, socket) do
    # Alias current_user as current_principal for this view
    current_principal = socket.assigns[:current_user] || generate_anonymous_user()

    if connected?(socket) do
      ThunderlineWeb.Endpoint.subscribe(@topic)

      # Track presence
      {:ok, _} =
        Presence.track_global(
          self(),
          current_principal.id,
          %{
            name: display_name(current_principal),
            joined_at: System.system_time(:second),
            cursor: nil
          }
        )
    end

    socket =
      socket
      |> assign(:page_title, "Dev Whiteboard")
      |> assign(:current_principal, current_principal)
      |> assign(:strokes, [])
      |> assign(:messages, [])
      |> assign(:current_color, "#000000")
      |> assign(:line_width, 2)
      |> assign(:tool, :pen)
      |> stream(:users, fetch_users())

    {:ok, socket}
  end

  @impl true
  def handle_event("stroke", %{"points" => points, "color" => color, "width" => width}, socket) do
    stroke = %{
      id: Ecto.UUID.generate(),
      points: points,
      color: color,
      width: width,
      user_id: socket.assigns.current_principal.id,
      timestamp: System.system_time(:millisecond)
    }

    # Broadcast to all connected users
    ThunderlineWeb.Endpoint.broadcast(@topic, "new_stroke", stroke)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_canvas", _params, socket) do
    # Broadcast clear event
    ThunderlineWeb.Endpoint.broadcast(@topic, "clear_canvas", %{
      user_id: socket.assigns.current_principal.id,
      timestamp: System.system_time(:millisecond)
    })

    socket = assign(socket, :strokes, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message_text}, socket)
      when message_text != "" do
    message = %{
      id: Ecto.UUID.generate(),
      text: String.trim(message_text),
      user_id: socket.assigns.current_principal.id,
      user_name: display_name(socket),
      timestamp: System.system_time(:millisecond)
    }

    # Broadcast message
    ThunderlineWeb.Endpoint.broadcast(@topic, "new_message", message)

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, :current_color, color)}
  end

  @impl true
  def handle_event("change_width", %{"width" => width}, socket) do
    width_int = String.to_integer(width)
    {:noreply, assign(socket, :line_width, width_int)}
  end

  @impl true
  def handle_event("change_tool", %{"tool" => tool}, socket) do
    tool_atom = String.to_existing_atom(tool)
    {:noreply, assign(socket, :tool, tool_atom)}
  end

  @impl true
  def handle_event("cursor_move", %{"x" => x, "y" => y}, socket) do
    # Update cursor position in presence
    Presence.update(
      self(),
      "presence_global",
      socket.assigns.current_principal.id,
      fn meta ->
        Map.put(meta, :cursor, %{x: x, y: y})
      end
    )

    {:noreply, socket}
  end

  # PubSub event handlers
  @impl true
  def handle_info(%{event: "new_stroke", payload: stroke}, socket) do
    # Push stroke to canvas hook
    socket =
      socket
      |> push_event("draw_stroke", stroke)
      |> update(:strokes, &[stroke | &1])

    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "clear_canvas", payload: _data}, socket) do
    socket =
      socket
      |> push_event("clear_canvas", %{})
      |> assign(:strokes, [])

    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "new_message", payload: message}, socket) do
    socket = update(socket, :messages, &[message | &1])
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    socket = stream(socket, :users, fetch_users(), reset: true)
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Helper functions
  defp display_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{email: email}) when is_binary(email), do: email
  defp display_name(_), do: "Anonymous"

  defp generate_anonymous_user do
    %{
      id: Ecto.UUID.generate(),
      name: "Anonymous-#{:rand.uniform(9999)}",
      email: nil
    }
  end

  defp fetch_users do
    Presence.list("presence_global")
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      %{
        id: user_id,
        name: meta.name,
        joined_at: meta.joined_at,
        cursor: meta[:cursor]
      }
    end)
    |> Enum.sort_by(& &1.joined_at)
  end

  defp format_time(timestamp) when is_integer(timestamp) do
    datetime = DateTime.from_unix!(timestamp, :millisecond)
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_time(_), do: ""
end
