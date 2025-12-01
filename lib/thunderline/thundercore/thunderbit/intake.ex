defmodule Thunderline.Thundercore.Thunderbit.Intake do
  @moduledoc """
  Thunderbit Intake - Handles the capture → parse → spawn → broadcast pipeline.

  This module is the main entry point for converting user input (text or voice)
  into Thunderbits and broadcasting them to the UI and other subsystems.

  ## Pipeline

  1. **Capture** - Receive text or voice input
  2. **Parse** - Segment into semantic chunks via Builder
  3. **Spawn** - Create Thunderbit structs with IDs and positions
  4. **Broadcast** - Emit events via PubSub for UI and subsystems

  ## Events

  Events are broadcast on the `thunderbits:lobby` topic:
  - `thunderbit:created` - New bit spawned
  - `thunderbit:updated` - Existing bit modified
  - `thunderbit:archived` - Bit removed from active field

  ## Usage

      # From chat input handler
      {:ok, bits} = Intake.process_text(text, owner: current_user.id)

      # From voice handler
      {:ok, bits} = Intake.process_voice(transcript, confidence: 0.92)

      # Subscribe in LiveView
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thunderbits:lobby")

      # Handle in handle_info
      def handle_info({:thunderbit_created, bit}, socket) do
        {:noreply, update(socket, :bits, &[bit | &1])}
      end
  """

  alias Thunderline.Thundercore.Thunderbit
  alias Thunderline.Thundercore.Thunderbit.Builder

  @pubsub Thunderline.PubSub
  @topic "thunderbits:lobby"

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Processes text input and broadcasts resulting Thunderbits.

  ## Options
  - `:owner` - Agent responsible for these bits
  - `:context` - Additional context for tag extraction
  - `:broadcast` - Whether to broadcast (default: true)

  ## Returns
  `{:ok, [%Thunderbit{}]}` on success

  ## Example

      {:ok, bits} = Intake.process_text("Navigate to zone 4", owner: "user_123")
  """
  def process_text(text, opts \\ []) do
    with {:ok, bits} <- Builder.from_text(text, opts) do
      bits = Builder.link_related(bits)

      if Keyword.get(opts, :broadcast, true) do
        broadcast_created(bits)
      end

      {:ok, bits}
    end
  end

  @doc """
  Processes voice transcript and broadcasts resulting Thunderbits.

  ## Options
  - `:confidence` - ASR confidence score (affects energy)
  - `:owner` - Agent responsible
  - `:broadcast` - Whether to broadcast (default: true)

  ## Example

      {:ok, bits} = Intake.process_voice(transcript, confidence: 0.85, owner: "user_123")
  """
  def process_voice(transcript, opts \\ []) do
    with {:ok, bits} <- Builder.from_voice(transcript, opts) do
      bits = Builder.link_related(bits)

      if Keyword.get(opts, :broadcast, true) do
        broadcast_created(bits)
      end

      {:ok, bits}
    end
  end

  @doc """
  Creates and broadcasts a single system-generated Thunderbit.

  Useful for internal notifications, status updates, etc.

  ## Example

      Intake.spawn_system_bit(:world_update, "Zone 4 boundary crossed", tags: ["zone:4"])
  """
  def spawn_system_bit(kind, content, opts \\ []) do
    opts = Keyword.merge(opts, kind: kind, content: content, source: :system)

    with {:ok, bit} <- Thunderbit.new(opts) do
      if Keyword.get(opts, :broadcast, true) do
        broadcast_created([bit])
      end

      {:ok, bit}
    end
  end

  @doc """
  Creates and broadcasts a PAC-generated Thunderbit.

  PACs externalize their internal state (suspicion, curiosity, plans)
  as Thunderbits for human visibility.

  ## Example

      Intake.spawn_pac_bit(:intent, "Investigating anomaly", pac_id: "ezra", tags: ["zone:crash_site"])
  """
  def spawn_pac_bit(kind, content, opts \\ []) do
    pac_id = Keyword.fetch!(opts, :pac_id)
    tags = ["PAC:#{pac_id}" | Keyword.get(opts, :tags, [])]

    opts =
      opts
      |> Keyword.put(:kind, kind)
      |> Keyword.put(:content, content)
      |> Keyword.put(:source, :pac)
      |> Keyword.put(:owner, pac_id)
      |> Keyword.put(:tags, tags)

    with {:ok, bit} <- Thunderbit.new(opts) do
      if Keyword.get(opts, :broadcast, true) do
        broadcast_created([bit])
      end

      {:ok, bit}
    end
  end

  # ===========================================================================
  # Lifecycle Operations
  # ===========================================================================

  @doc """
  Updates a Thunderbit and broadcasts the change.
  """
  def update_bit(%Thunderbit{} = bit, updates) do
    updated_bit =
      Enum.reduce(updates, bit, fn
        {:energy, val}, acc -> Thunderbit.set_energy(acc, val)
        {:salience, val}, acc -> Thunderbit.set_salience(acc, val)
        {:status, :active}, acc -> Thunderbit.activate(acc)
        {:status, :fading}, acc -> Thunderbit.fade(acc)
        {:status, :archived}, acc -> Thunderbit.archive(acc)
        {:tags, tags}, acc -> Thunderbit.add_tags(acc, tags)
        {:link, id}, acc -> Thunderbit.add_link(acc, id)
        {:position, pos}, acc -> Thunderbit.set_position(acc, pos)
        _, acc -> acc
      end)

    broadcast_updated(updated_bit)
    {:ok, updated_bit}
  end

  @doc """
  Archives a Thunderbit (marks for fade-out).
  """
  def archive_bit(%Thunderbit{} = bit) do
    archived = Thunderbit.archive(bit)
    broadcast_archived(archived)
    {:ok, archived}
  end

  @doc """
  Archives multiple Thunderbits by ID.
  """
  def archive_bits(bit_ids) when is_list(bit_ids) do
    Enum.each(bit_ids, fn id ->
      broadcast(@topic, {:thunderbit_archived, %{id: id}})
    end)

    :ok
  end

  # ===========================================================================
  # Broadcasting
  # ===========================================================================

  @doc """
  Returns the PubSub topic for Thunderbit events.
  """
  def topic, do: @topic

  @doc """
  Subscribes the current process to Thunderbit events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Subscribes to a specific subset of Thunderbit events.

  ## Topics
  - `"thunderbits:lobby"` - All events
  - `"thunderbits:pac:{pac_id}"` - Events from specific PAC
  - `"thunderbits:zone:{zone_id}"` - Events tagged with zone
  """
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  defp broadcast_created(bits) when is_list(bits) do
    Enum.each(bits, fn bit ->
      broadcast(@topic, {:thunderbit_created, bit})

      # Also broadcast to PAC-specific topic if from PAC
      if bit.source == :pac and bit.owner do
        broadcast("thunderbits:pac:#{bit.owner}", {:thunderbit_created, bit})
      end

      # Broadcast to zone topics
      Enum.each(bit.tags, fn
        "zone:" <> zone_id ->
          broadcast("thunderbits:zone:#{zone_id}", {:thunderbit_created, bit})

        _ ->
          :ok
      end)
    end)
  end

  defp broadcast_updated(bit) do
    broadcast(@topic, {:thunderbit_updated, bit})
  end

  defp broadcast_archived(bit) do
    broadcast(@topic, {:thunderbit_archived, bit})
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end

  # ===========================================================================
  # Integration Helpers
  # ===========================================================================

  @doc """
  Converts a Thunderflow event into a Thunderbit.

  This bridges the existing event system with the new Thunderbit visualization.
  """
  def from_thunderflow_event(%{type: type, domain: domain, payload: payload} = event) do
    kind = map_event_type_to_kind(type)
    content = summarize_event_payload(type, payload)
    tags = extract_event_tags(domain, payload)

    spawn_system_bit(kind, content,
      tags: tags,
      metadata: %{event_id: event[:id], event_type: type}
    )
  end

  defp map_event_type_to_kind(type) do
    case type do
      t when t in [:pac_created, :pac_evolved, :pac_action] -> :world_update
      t when t in [:policy_violation, :policy_check] -> :assertion
      t when t in [:error, :failure, :timeout] -> :error
      t when t in [:query, :search] -> :question
      t when t in [:command, :action, :execute] -> :command
      _ -> :system
    end
  end

  defp summarize_event_payload(type, payload) do
    case {type, payload} do
      {:pac_created, %{name: name}} -> "PAC #{name} created"
      {:pac_evolved, %{pac_id: id}} -> "PAC #{id} evolved"
      {:policy_violation, %{policy: p}} -> "Policy violation: #{p}"
      {:error, %{message: msg}} -> "Error: #{msg}"
      _ -> "#{type} event"
    end
  end

  defp extract_event_tags(domain, payload) do
    base = ["domain:#{domain}"]

    pac_tags =
      case payload do
        %{pac_id: id} -> ["PAC:#{id}"]
        %{pac: %{id: id}} -> ["PAC:#{id}"]
        _ -> []
      end

    zone_tags =
      case payload do
        %{zone_id: id} -> ["zone:#{id}"]
        %{zone: z} when is_binary(z) -> ["zone:#{z}"]
        _ -> []
      end

    base ++ pac_tags ++ zone_tags
  end
end
