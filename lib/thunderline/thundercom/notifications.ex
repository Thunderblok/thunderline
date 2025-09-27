defmodule Thunderline.Thundercom.Notifications do
  @moduledoc """
  Real-time notification system for Thunderline using Ash Notifications and Phoenix PubSub.
  Based on: https://medium.com/@lambert.kamaro/part-7-ash-framework-for-phoenix-developers-go-real-time-with-ash-notifications-and-pubsub-c89aa9104370

  Handles real-time updates for:
  - Community changes (members, channels, messages)
  - Agent state changes (spawning, status updates, termination)
  - Chunk updates (health, optimization, scaling)
  - Federation events (socket connections, cross-realm messages)
  - System health monitoring
  """

  @behaviour Ash.Notifier
  require Logger

  # @pubsub_name Thunderline.PubSub (unused)

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{} = notification) do
    Logger.debug("Processing Ash notification: #{inspect(notification)}")

    case notification.resource do
      # Community-related notifications
      Thunderblock.Resources.Community ->
        handle_community_notification(notification)

      Thunderblock.Resources.Channel ->
        handle_channel_notification(notification)

      Thunderblock.Resources.Message ->
        handle_message_notification(notification)

      Thunderblock.Resources.Member ->
        handle_member_notification(notification)

      Thunderblock.Resources.Role ->
        handle_role_notification(notification)

      # Agent and automation notifications
      Thunderbolt.Resources.Chunk ->
        handle_chunk_notification(notification)

      Thunderbolt.Resources.ChunkHealth ->
        handle_chunk_health_notification(notification)

      Thunderbit.Resources.Agent ->
        handle_agent_notification(notification)

      # Federation notifications
      Thunderblock.Resources.FederationSocket ->
        handle_federation_notification(notification)

      # Grid and spatial notifications
      Thunderline.Thundergrid.Resources.GridZone ->
        handle_grid_notification(notification)

      Thunderline.Thundergrid.Resources.GridResource ->
        handle_resource_notification(notification)

      _ ->
        Logger.debug("Unhandled notification for resource: #{notification.resource}")
        :ok
    end
  rescue
    error ->
      Logger.error("Error processing notification: #{inspect(error)}")
      :ok
  end

  @impl Ash.Notifier
  def requires_original_data?(_resource, _action), do: false

  # ===== COMMUNITY NOTIFICATIONS =====

  defp handle_community_notification(%{action: %{name: action}, data: community} = notification) do
    community_id = community.id

    case action do
      :create ->
        broadcast_to_topic("communities", "community_created", %{
          community: serialize_community(community),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("community:#{community_id}", "community_updated", %{
          community: serialize_community(community),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      :destroy ->
        broadcast_to_topic("communities", "community_deleted", %{
          community_id: community_id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        Logger.debug("Unhandled community action: #{action}")
    end

    :ok
  end

  defp handle_channel_notification(%{action: %{name: action}, data: channel} = notification) do
    community_id = channel.community_id
    channel_id = channel.id

    case action do
      :create ->
        broadcast_to_topic("community:#{community_id}", "channel_created", %{
          channel: serialize_channel(channel),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("community:#{community_id}", "channel_updated", %{
          channel: serialize_channel(channel),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      :destroy ->
        broadcast_to_topic("community:#{community_id}", "channel_deleted", %{
          channel_id: channel_id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  defp handle_message_notification(%{action: %{name: action}, data: message} = notification) do
    channel_id = message.channel_id

    case action do
      :create ->
        # Get community_id through channel relationship if available
        community_id = get_community_id_from_channel(channel_id)

        broadcast_to_topic("channel:#{channel_id}", "message_created", %{
          message: serialize_message(message),
          timestamp: DateTime.utc_now()
        })

        if community_id do
          broadcast_to_topic("community:#{community_id}", "new_message", %{
            channel_id: channel_id,
            message: serialize_message(message),
            timestamp: DateTime.utc_now()
          })
        end

      :update ->
        broadcast_to_topic("channel:#{channel_id}", "message_updated", %{
          message: serialize_message(message),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      :destroy ->
        broadcast_to_topic("channel:#{channel_id}", "message_deleted", %{
          message_id: message.id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  defp handle_member_notification(%{action: %{name: action}, data: member} = notification) do
    community_id = member.community_id

    case action do
      :create ->
        broadcast_to_topic("community:#{community_id}", "member_joined", %{
          member: serialize_member(member),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("community:#{community_id}", "member_updated", %{
          member: serialize_member(member),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      :destroy ->
        broadcast_to_topic("community:#{community_id}", "member_left", %{
          user_id: member.user_id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  defp handle_role_notification(%{action: %{name: action}, data: role} = notification) do
    community_id = role.community_id

    case action do
      :create ->
        broadcast_to_topic("community:#{community_id}", "role_created", %{
          role: serialize_role(role),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("community:#{community_id}", "role_updated", %{
          role: serialize_role(role),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      :destroy ->
        broadcast_to_topic("community:#{community_id}", "role_deleted", %{
          role_id: role.id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  # ===== AGENT AND AUTOMATION NOTIFICATIONS =====

  defp handle_chunk_notification(%{action: %{name: action}, data: chunk} = notification) do
    chunk_id = chunk.id

    case action do
      :create ->
        broadcast_to_topic("chunks", "chunk_created", %{
          chunk: serialize_chunk(chunk),
          timestamp: DateTime.utc_now()
        })

      :update ->
        # Broadcast to both general chunks topic and specific chunk
        broadcast_to_topic("chunks", "chunk_updated", %{
          chunk: serialize_chunk(chunk),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        broadcast_to_topic("chunk:#{chunk_id}", "chunk_updated", %{
          chunk: serialize_chunk(chunk),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        # Special handling for status changes
        if Map.has_key?(notification.changeset.changes, :status) do
          broadcast_to_topic("automata:status", "chunk_status_changed", %{
            chunk_id: chunk_id,
            old_status: notification.changeset.original.status,
            new_status: chunk.status,
            timestamp: DateTime.utc_now()
          })
        end

      :destroy ->
        broadcast_to_topic("chunks", "chunk_destroyed", %{
          chunk_id: chunk_id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  defp handle_chunk_health_notification(%{action: %{name: action}, data: health} = notification) do
    chunk_id = health.chunk_id

    case action do
      :create ->
        broadcast_to_topic("chunk:#{chunk_id}", "health_created", %{
          health: serialize_chunk_health(health),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("chunk:#{chunk_id}", "health_updated", %{
          health: serialize_chunk_health(health),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        # Alert if health score drops below threshold
        if health.health_score && Decimal.lt?(health.health_score, Decimal.new("0.3")) do
          broadcast_to_topic("automata:alerts", "low_health_alert", %{
            chunk_id: chunk_id,
            health_score: health.health_score,
            timestamp: DateTime.utc_now()
          })
        end

      _ ->
        :ok
    end

    :ok
  end

  defp handle_agent_notification(%{action: %{name: action}, data: agent} = notification) do
    agent_id = agent.id

    case action do
      :create ->
        broadcast_to_topic("agents", "agent_spawned", %{
          agent: serialize_agent(agent),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("agents", "agent_updated", %{
          agent: serialize_agent(agent),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        broadcast_to_topic("agent:#{agent_id}", "agent_updated", %{
          agent: serialize_agent(agent),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        # Special handling for state transitions
        if Map.has_key?(notification.changeset.changes, :state) do
          broadcast_to_topic("automata:status", "agent_state_changed", %{
            agent_id: agent_id,
            old_state: notification.changeset.original.state,
            new_state: agent.state,
            timestamp: DateTime.utc_now()
          })
        end

      :destroy ->
        broadcast_to_topic("agents", "agent_terminated", %{
          agent_id: agent_id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  # ===== FEDERATION NOTIFICATIONS =====

  defp handle_federation_notification(%{action: %{name: action}, data: socket} = notification) do
    socket_id = socket.id

    case action do
      :create ->
        broadcast_to_topic("federation", "socket_created", %{
          socket: serialize_federation_socket(socket),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("federation", "socket_updated", %{
          socket: serialize_federation_socket(socket),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        # Special handling for connection status changes
        if Map.has_key?(notification.changeset.changes, :connection_status) do
          broadcast_to_topic("federation:status", "connection_status_changed", %{
            socket_id: socket_id,
            old_status: notification.changeset.original.connection_status,
            new_status: socket.connection_status,
            timestamp: DateTime.utc_now()
          })
        end

      :destroy ->
        broadcast_to_topic("federation", "socket_disconnected", %{
          socket_id: socket_id,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  # ===== GRID AND SPATIAL NOTIFICATIONS =====

  defp handle_grid_notification(%{action: %{name: action}, data: zone} = notification) do
    zone_id = zone.id

    case action do
      :create ->
        broadcast_to_topic("grid", "zone_created", %{
          zone: serialize_grid_zone(zone),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("grid", "zone_updated", %{
          zone: serialize_grid_zone(zone),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

        broadcast_to_topic("zone:#{zone_id}", "zone_updated", %{
          zone: serialize_grid_zone(zone),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  defp handle_resource_notification(%{action: %{name: action}, data: resource} = notification) do
    _resource_id = resource.id

    case action do
      :create ->
        broadcast_to_topic("grid:resources", "resource_created", %{
          resource: serialize_grid_resource(resource),
          timestamp: DateTime.utc_now()
        })

      :update ->
        broadcast_to_topic("grid:resources", "resource_updated", %{
          resource: serialize_grid_resource(resource),
          changes: notification.changeset.changes,
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end

    :ok
  end

  # ===== UTILITY FUNCTIONS =====

  defp broadcast_to_topic(topic, event, payload) do
    pipeline = infer_pipeline_from_topic(topic)

    attrs = %{
      name: "system.notifications." <> event,
      type: String.to_atom(event),
      # or a dedicated :notifications atom if added to taxonomy
      source: :link,
      payload: %{
        topic: topic,
        payload: payload,
        timestamp: DateTime.utc_now()
      },
      meta: %{pipeline: pipeline}
    }

    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      case Thunderline.EventBus.publish_event(ev) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[Notifications] publish failed: #{inspect(reason)} attrs=#{inspect(Map.take(attrs, [:name, :type]))}"
          )
      end
    end
  end

  defp infer_pipeline_from_topic(topic) do
    cond do
      String.contains?(topic, ":status") or String.contains?(topic, "agents") -> :realtime
      String.contains?(topic, "federation") -> :cross_domain
      true -> :general
    end
  end

  defp get_community_id_from_channel(channel_id) do
    try do
      case Ash.get(Thunderblock.Resources.Channel, channel_id, domain: Thunderblock.Domain) do
        {:ok, channel} -> channel.community_id
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  # ===== SERIALIZATION FUNCTIONS =====

  defp serialize_community(community) do
    %{
      id: community.id,
      community_name: community.community_name,
      community_slug: community.community_slug,
      community_type: community.community_type,
      member_count: community.member_count || 0,
      channel_count: community.channel_count || 0,
      created_at: community.created_at,
      updated_at: community.updated_at
    }
  end

  defp serialize_channel(channel) do
    %{
      id: channel.id,
      channel_name: channel.channel_name,
      channel_type: channel.channel_type,
      community_id: channel.community_id,
      topic: channel.topic,
      created_at: channel.created_at,
      updated_at: channel.updated_at
    }
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      content: message.content,
      channel_id: message.channel_id,
      author_id: message.author_id,
      message_type: message.message_type,
      created_at: message.created_at,
      updated_at: message.updated_at
    }
  end

  defp serialize_member(member) do
    %{
      id: member.id,
      user_id: member.user_id,
      community_id: member.community_id,
      role: member.role,
      joined_at: member.joined_at
    }
  end

  defp serialize_role(role) do
    %{
      id: role.id,
      role_name: role.role_name,
      community_id: role.community_id,
      permissions: role.permissions,
      color: role.color,
      position: role.position,
      created_at: role.created_at
    }
  end

  defp serialize_chunk(chunk) do
    %{
      id: chunk.id,
      chunk_identifier: chunk.chunk_identifier,
      status: chunk.status,
      size: chunk.size,
      agent_count: chunk.agent_count || 0,
      health_score: chunk.health_score,
      created_at: chunk.created_at,
      updated_at: chunk.updated_at
    }
  end

  defp serialize_chunk_health(health) do
    %{
      id: health.id,
      chunk_id: health.chunk_id,
      health_score: health.health_score,
      cpu_usage: health.cpu_usage,
      memory_usage: health.memory_usage,
      last_check_at: health.last_check_at,
      created_at: health.created_at
    }
  end

  defp serialize_agent(agent) do
    %{
      id: agent.id,
      agent_identifier: agent.agent_identifier,
      state: agent.state,
      chunk_id: agent.chunk_id,
      position: agent.position,
      created_at: agent.created_at,
      updated_at: agent.updated_at
    }
  end

  defp serialize_federation_socket(socket) do
    %{
      id: socket.id,
      connection_status: socket.connection_status,
      remote_realm: socket.remote_realm,
      community_id: socket.community_id,
      connected_at: socket.connected_at,
      last_heartbeat: socket.last_heartbeat
    }
  end

  defp serialize_grid_zone(zone) do
    %{
      id: zone.id,
      zone_identifier: zone.zone_identifier,
      boundaries: zone.boundaries,
      zone_type: zone.zone_type,
      resource_count: zone.resource_count || 0,
      created_at: zone.created_at,
      updated_at: zone.updated_at
    }
  end

  defp serialize_grid_resource(resource) do
    %{
      id: resource.id,
      resource_identifier: resource.resource_identifier,
      resource_type: resource.resource_type,
      position: resource.position,
      zone_id: resource.zone_id,
      created_at: resource.created_at,
      updated_at: resource.updated_at
    }
  end
end
