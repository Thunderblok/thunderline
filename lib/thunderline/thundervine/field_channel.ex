defmodule Thunderline.Thundervine.FieldChannel do
  @moduledoc """
  Behaviour for FieldChannels - the medium through which Thunderbits interact.

  FieldChannels implement the "Spinozistic field" concept from the High Command synthesis.
  They are the ONLY way Thunderbits can influence each other - no direct bit-to-bit messaging.

  ## Available Channels

  Each channel represents a different "dimension" of influence:

  - `:gravity` - Spatial attraction/repulsion forces
  - `:mood` - Emotional/social field propagation
  - `:heat` - Activity/energy diffusion
  - `:signal` - Communication signal strength
  - `:entropy` - Local disorder measure
  - `:intent` - Directional intent vectors
  - `:reward` - Reinforcement learning signals

  ## Usage

      # Read field value at coordinate
      {:ok, value} = FieldChannel.read(:gravity, %{x: 0, y: 0, z: 0}, ctx)

      # Write to field (buffered, processed in bulk)
      :ok = FieldChannel.write(:heat, %{x: 0, y: 0, z: 0}, 0.5, ctx)

      # Process all buffered writes for a tick
      :ok = FieldChannel.flush_writes(ctx)

  ## Implementation

  Each channel can have different physics:
  - Decay rates (how fast values fade)
  - Diffusion patterns (how values spread to neighbors)
  - Combination rules (how multiple writes merge)

  ## Architecture

  ```
  Thunderbit → write_buffer → Thundervine.FieldChannel.flush_writes/1
                                          ↓
                              Channel implementations (ETS/Mnesia)
                                          ↓
  Thunderbit ← FieldChannel.read/3 ← Field state store
  ```
  """

  @type coord :: %{x: integer(), y: integer(), z: integer()}
  @type channel :: :gravity | :mood | :heat | :signal | :entropy | :intent | :reward
  @type value :: number() | atom() | map()
  @type context :: map()

  @doc """
  Read the current field value at a coordinate.

  Returns the field value for the specified channel at the given coordinate.
  If no value has been written, returns the channel's default value.
  """
  @callback read(coord(), context()) :: {:ok, value()} | {:error, term()}

  @doc """
  Write a value to the field at a coordinate.

  Writes are typically buffered and processed in bulk during the global tick.
  The actual write semantics depend on the channel implementation.
  """
  @callback write(coord(), value(), context()) :: :ok | {:error, term()}

  @doc """
  Get the default value for this channel.
  """
  @callback default_value() :: value()

  @doc """
  Apply decay to all values in the field.

  Called once per global tick to fade old values.
  """
  @callback apply_decay(context()) :: :ok

  @doc """
  Apply diffusion to spread values to neighbors.

  Called once per global tick after decay.
  """
  @callback apply_diffusion(context()) :: :ok

  @doc """
  Combine multiple writes to the same coordinate.

  When multiple Thunderbits write to the same field location,
  this determines how to merge the values.
  """
  @callback combine_writes([value()]) :: value()

  # ============================================================================
  # Public API
  # ============================================================================

  @channels %{
    gravity: Thunderline.Thundervine.FieldChannels.Gravity,
    mood: Thunderline.Thundervine.FieldChannels.Mood,
    heat: Thunderline.Thundervine.FieldChannels.Heat,
    signal: Thunderline.Thundervine.FieldChannels.Signal,
    entropy: Thunderline.Thundervine.FieldChannels.Entropy,
    intent: Thunderline.Thundervine.FieldChannels.Intent,
    reward: Thunderline.Thundervine.FieldChannels.Reward
  }

  @doc """
  Read field value from a specific channel.

  ## Examples

      {:ok, -0.3} = FieldChannel.read(:gravity, %{x: 0, y: 0, z: 0}, ctx)
      {:ok, :neutral} = FieldChannel.read(:intent, %{x: 5, y: 5, z: 0}, ctx)
  """
  @spec read(channel(), coord(), context()) :: {:ok, value()} | {:error, term()}
  def read(channel, coord, ctx) do
    case Map.get(@channels, channel) do
      nil -> {:error, {:unknown_channel, channel}}
      module -> module.read(coord, ctx)
    end
  end

  @doc """
  Write value to a specific channel.

  ## Examples

      :ok = FieldChannel.write(:heat, %{x: 0, y: 0, z: 0}, 0.5, ctx)
  """
  @spec write(channel(), coord(), value(), context()) :: :ok | {:error, term()}
  def write(channel, coord, value, ctx) do
    case Map.get(@channels, channel) do
      nil -> {:error, {:unknown_channel, channel}}
      module -> module.write(coord, value, ctx)
    end
  end

  @doc """
  Read all field values at a coordinate.

  Returns a map of channel → value for all channels.
  """
  @spec read_all(coord(), context()) :: {:ok, %{channel() => value()}}
  def read_all(coord, ctx) do
    values =
      Enum.reduce(@channels, %{}, fn {channel, module}, acc ->
        case module.read(coord, ctx) do
          {:ok, value} -> Map.put(acc, channel, value)
          {:error, _} -> Map.put(acc, channel, module.default_value())
        end
      end)

    {:ok, values}
  end

  @doc """
  Process buffered writes for all channels.

  Called once per global tick after all Thunderbits have computed their writes.
  """
  @spec flush_writes(context()) :: :ok
  def flush_writes(ctx) do
    Enum.each(@channels, fn {_channel, module} ->
      module.apply_decay(ctx)
      module.apply_diffusion(ctx)
    end)

    :ok
  end

  @doc """
  Get the default value for a channel.
  """
  @spec default_value(channel()) :: value()
  def default_value(channel) do
    case Map.get(@channels, channel) do
      nil -> 0.0
      module -> module.default_value()
    end
  end

  @doc """
  List all available channels.
  """
  @spec channels() :: [channel()]
  def channels, do: Map.keys(@channels)
end
