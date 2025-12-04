defmodule Thunderline.Thundervine.FieldChannels.Base do
  @moduledoc """
  Base implementation for FieldChannels using ETS for storage.

  This module provides common functionality for all field channels:
  - ETS-backed coordinate → value storage
  - Decay application (values fade over time)
  - Diffusion application (values spread to neighbors)
  - Write combination (merging multiple writes)

  ## Usage

  Individual channel modules `use` this and override specific callbacks:

      defmodule MyChannel do
        use Thunderline.Thundervine.FieldChannels.Base,
          name: :my_channel,
          default: 0.0,
          decay_rate: 0.1,
          diffusion_rate: 0.05
      end
  """

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    default = Keyword.get(opts, :default, 0.0)
    decay_rate = Keyword.get(opts, :decay_rate, 0.1)
    diffusion_rate = Keyword.get(opts, :diffusion_rate, 0.05)

    quote do
      @behaviour Thunderline.Thundervine.FieldChannel

      @channel_name unquote(name)
      @default_value unquote(default)
      @decay_rate unquote(decay_rate)
      @diffusion_rate unquote(diffusion_rate)

      @doc """
      Initialize the ETS table for this channel.

      Call this during application startup.
      """
      def init do
        table_name = table_name()

        if :ets.whereis(table_name) == :undefined do
          :ets.new(table_name, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        end

        :ok
      end

      @doc """
      Get the ETS table name for this channel.
      """
      def table_name do
        :"thundervine_field_#{@channel_name}"
      end

      @impl Thunderline.Thundervine.FieldChannel
      def read(coord, _ctx) do
        key = coord_to_key(coord)

        case :ets.lookup(table_name(), key) do
          [{^key, value}] -> {:ok, value}
          [] -> {:ok, @default_value}
        end
      end

      @impl Thunderline.Thundervine.FieldChannel
      def write(coord, value, _ctx) do
        key = coord_to_key(coord)

        # Buffer writes for later combination
        buffer_table = :"#{table_name()}_buffer"
        ensure_buffer_table(buffer_table)

        case :ets.lookup(buffer_table, key) do
          [{^key, existing}] ->
            :ets.insert(buffer_table, {key, [value | existing]})

          [] ->
            :ets.insert(buffer_table, {key, [value]})
        end

        :ok
      end

      @impl Thunderline.Thundervine.FieldChannel
      def default_value, do: @default_value

      @impl Thunderline.Thundervine.FieldChannel
      def apply_decay(_ctx) do
        table = table_name()

        :ets.foldl(
          fn {key, value}, _acc ->
            decayed = apply_decay_to_value(value)

            if significant?(decayed) do
              :ets.insert(table, {key, decayed})
            else
              :ets.delete(table, key)
            end

            :ok
          end,
          :ok,
          table
        )

        :ok
      end

      @impl Thunderline.Thundervine.FieldChannel
      def apply_diffusion(_ctx) do
        # Process buffered writes first
        process_write_buffer()

        # Then apply diffusion to spread values
        apply_diffusion_step()

        :ok
      end

      @impl Thunderline.Thundervine.FieldChannel
      def combine_writes(values) when is_list(values) do
        # Default: sum all values, clamp to [-1, 1] for most channels
        sum = Enum.sum(values)
        clamp(sum, -1.0, 1.0)
      end

      # ========================================================================
      # Overridable helpers
      # ========================================================================

      @doc """
      Apply decay to a single value.
      Override for custom decay curves.
      """
      def apply_decay_to_value(value) when is_number(value) do
        value * (1.0 - @decay_rate)
      end

      def apply_decay_to_value(value), do: value

      @doc """
      Check if a value is significant enough to keep.
      Override for custom thresholds.
      """
      def significant?(value) when is_number(value), do: abs(value) > 0.001
      def significant?(_value), do: true

      @doc """
      Get neighbor offsets for diffusion.
      Override for different topologies.
      """
      def neighbor_offsets do
        # Von Neumann neighborhood (6 neighbors)
        [{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}]
      end

      # ========================================================================
      # Private helpers
      # ========================================================================

      defp coord_to_key(%{x: x, y: y, z: z}), do: {x, y, z}
      defp coord_to_key({x, y, z}), do: {x, y, z}

      defp key_to_coord({x, y, z}), do: %{x: x, y: y, z: z}

      defp ensure_buffer_table(buffer_table) do
        if :ets.whereis(buffer_table) == :undefined do
          :ets.new(buffer_table, [
            :named_table,
            :public,
            :set,
            write_concurrency: true
          ])
        end
      end

      defp process_write_buffer do
        buffer_table = :"#{table_name()}_buffer"
        main_table = table_name()

        if :ets.whereis(buffer_table) != :undefined do
          :ets.foldl(
            fn {key, writes}, _acc ->
              combined = combine_writes(writes)

              # Merge with existing value
              current =
                case :ets.lookup(main_table, key) do
                  [{^key, val}] -> val
                  [] -> @default_value
                end

              new_value = merge_with_current(current, combined)
              :ets.insert(main_table, {key, new_value})

              :ok
            end,
            :ok,
            buffer_table
          )

          # Clear buffer
          :ets.delete_all_objects(buffer_table)
        end
      end

      defp merge_with_current(current, new) when is_number(current) and is_number(new) do
        clamp(current + new, -1.0, 1.0)
      end

      defp merge_with_current(_current, new), do: new

      defp apply_diffusion_step do
        table = table_name()

        # Collect current values
        entries = :ets.tab2list(table)

        # Calculate diffusion contributions
        contributions =
          Enum.flat_map(entries, fn {{x, y, z} = key, value} ->
            diffusion_amount = value * @diffusion_rate

            neighbor_offsets()
            |> Enum.map(fn {dx, dy, dz} ->
              neighbor_key = {x + dx, y + dy, z + dz}
              {neighbor_key, diffusion_amount / length(neighbor_offsets())}
            end)
          end)

        # Group and sum contributions per coordinate
        grouped = Enum.group_by(contributions, &elem(&1, 0), &elem(&1, 1))

        # Apply contributions
        Enum.each(grouped, fn {key, amounts} ->
          contribution = Enum.sum(amounts)

          current =
            case :ets.lookup(table, key) do
              [{^key, val}] -> val
              [] -> 0.0
            end

          new_value = clamp(current + contribution, -1.0, 1.0)

          if significant?(new_value) do
            :ets.insert(table, {key, new_value})
          end
        end)
      end

      defp clamp(value, min, max) when is_number(value) do
        value |> max(min) |> min(max)
      end

      defp clamp(value, _min, _max), do: value

      defoverridable apply_decay_to_value: 1,
                     significant?: 1,
                     neighbor_offsets: 0,
                     combine_writes: 1
    end
  end
end
