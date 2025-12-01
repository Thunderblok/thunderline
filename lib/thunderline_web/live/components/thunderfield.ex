defmodule ThunderlineWeb.Live.Components.Thunderfield do
  @moduledoc """
  Thunderfield - Visual Thunderbit Field Component

  Renders an animated 2D field of Thunderbits. Each bit appears as a glowing glyph
  whose shape, color, and size encode its ontological type, energy, and salience.

  ## Features
  - Animated spawn/drift/fade lifecycle
  - Energy-based sizing
  - Kind-based coloring and shapes
  - Hover tooltips with content and tags
  - Click to expand details panel
  - Relation lines between linked bits

  ## Usage

      <.thunderfield
        bits={@thunderbits}
        selected={@selected_bit}
        on_select="select_bit"
        class="h-96"
      />

  ## JS Hook

  This component requires the `Thunderfield` JS hook to be registered in app.js:

      Hooks.Thunderfield = {
        mounted() { ... },
        updated() { ... }
      }
  """

  use Phoenix.Component

  import ThunderlineWeb.CoreComponents, only: [icon: 1]

  alias Thunderline.Thundercore.Thunderbit

  # ===========================================================================
  # Main Component
  # ===========================================================================

  attr :bits, :list, default: []
  attr :selected, :any, default: nil
  attr :on_select, :string, default: nil
  attr :show_relations, :boolean, default: true
  attr :class, :string, default: ""
  attr :id, :string, default: "thunderfield"

  def thunderfield(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "relative overflow-hidden rounded-2xl",
        "bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950",
        "border border-cyan-500/20",
        @class
      ]}
      phx-hook="Thunderfield"
      data-bits={Jason.encode!(Enum.map(@bits, &Thunderbit.to_map/1))}
      data-selected={@selected && @selected.id}
      data-show-relations={to_string(@show_relations)}
    >
      <%!-- Background Grid --%>
      <div class="absolute inset-0 thunderfield-grid opacity-20"></div>

      <%!-- Central Anchor (Being) --%>
      <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
        <div class="w-8 h-8 rounded-full bg-gradient-to-br from-amber-400/30 to-amber-600/30 animate-pulse-slow flex items-center justify-center">
          <div class="w-4 h-4 rounded-full bg-amber-400/60"></div>
        </div>
      </div>

      <%!-- Bits Container (rendered by JS hook) --%>
      <div id={"#{@id}-bits"} class="absolute inset-0 thunderfield-bits"></div>

      <%!-- Fallback Static Render --%>
      <noscript>
        <div class="absolute inset-0 p-4">
          <%= for bit <- @bits do %>
            <.thunderbit_static bit={bit} selected={@selected && @selected.id == bit.id} />
          <% end %>
        </div>
      </noscript>

      <%!-- Legend --%>
      <div class="absolute bottom-2 left-2 flex flex-wrap gap-2 text-xs">
        <.legend_item color="#F97316" label="Question" />
        <.legend_item color="#22C55E" label="Command" />
        <.legend_item color="#8B5CF6" label="Intent" />
        <.legend_item color="#6366F1" label="Memory" />
      </div>

      <%!-- Count Badge --%>
      <div class="absolute top-2 right-2 px-2 py-1 bg-black/50 rounded-lg text-xs text-cyan-300 border border-cyan-500/30">
        {length(@bits)} bits
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Static Thunderbit (No-JS Fallback)
  # ===========================================================================

  attr :bit, :map, required: true
  attr :selected, :boolean, default: false

  defp thunderbit_static(assigns) do
    bit = assigns.bit
    color = Thunderbit.color(bit)
    shape = Thunderbit.shape(bit)
    energy = Map.get(bit, :energy) || Map.get(bit, "energy") || 0.5
    size = round(24 + energy * 24)
    position = extract_position(bit)

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:shape, shape)
      |> assign(:size, size)
      |> assign(:position, position)
      |> assign(:energy, energy)

    ~H"""
    <div
      class={[
        "absolute transition-all duration-500",
        @selected && "ring-2 ring-cyan-400 ring-offset-2 ring-offset-slate-900"
      ]}
      style={"left: #{@position.x * 100}%; top: #{@position.y * 100}%; transform: translate(-50%, -50%);"}
      title={Map.get(@bit, :content) || Map.get(@bit, "content") || ""}
    >
      <.bit_shape shape={@shape} color={@color} size={@size} energy={@energy} />
    </div>
    """
  end

  # ===========================================================================
  # Bit Shapes
  # ===========================================================================

  attr :shape, :atom, required: true
  attr :color, :string, required: true
  attr :size, :integer, required: true
  attr :energy, :float, default: 0.5

  defp bit_shape(%{shape: :circle} = assigns) do
    ~H"""
    <div
      class="rounded-full animate-pulse-slow"
      style={"width: #{@size}px; height: #{@size}px; background: radial-gradient(circle, #{@color}88, #{@color}44); box-shadow: 0 0 #{round(@energy * 20)}px #{@color}66;"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :hex} = assigns) do
    ~H"""
    <div
      class="animate-pulse-slow"
      style={"width: #{@size}px; height: #{@size}px; background: #{@color}66; clip-path: polygon(50% 0%, 100% 25%, 100% 75%, 50% 100%, 0% 75%, 0% 25%); box-shadow: 0 0 #{round(@energy * 20)}px #{@color}66;"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :capsule} = assigns) do
    ~H"""
    <div
      class="rounded-full animate-pulse-slow"
      style={"width: #{round(@size * 1.5)}px; height: #{@size}px; background: linear-gradient(90deg, #{@color}66, #{@color}88, #{@color}66); box-shadow: 0 0 #{round(@energy * 20)}px #{@color}66;"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :bubble} = assigns) do
    ~H"""
    <div
      class="rounded-xl animate-float"
      style={"width: #{@size}px; height: #{round(@size * 0.8)}px; background: #{@color}44; border: 2px solid #{@color}88; box-shadow: 0 0 #{round(@energy * 15)}px #{@color}44;"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :diamond} = assigns) do
    ~H"""
    <div
      class="animate-pulse-slow"
      style={"width: #{@size}px; height: #{@size}px; background: #{@color}66; transform: rotate(45deg); box-shadow: 0 0 #{round(@energy * 20)}px #{@color}66;"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :star} = assigns) do
    ~H"""
    <div
      class="animate-spin-slow"
      style={"width: #{@size}px; height: #{@size}px; background: #{@color}88; clip-path: polygon(50% 0%, 61% 35%, 98% 35%, 68% 57%, 79% 91%, 50% 70%, 21% 91%, 32% 57%, 2% 35%, 39% 35%); box-shadow: 0 0 #{round(@energy * 25)}px #{@color}88;"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :triangle} = assigns) do
    ~H"""
    <div
      class="animate-pulse"
      style={"width: 0; height: 0; border-left: #{round(@size / 2)}px solid transparent; border-right: #{round(@size / 2)}px solid transparent; border-bottom: #{@size}px solid #{@color}; filter: drop-shadow(0 0 #{round(@energy * 15)}px #{@color});"}
    >
    </div>
    """
  end

  defp bit_shape(%{shape: :square} = assigns) do
    ~H"""
    <div
      class="rounded-sm animate-pulse-slow"
      style={"width: #{@size}px; height: #{@size}px; background: #{@color}66; box-shadow: 0 0 #{round(@energy * 15)}px #{@color}66;"}
    >
    </div>
    """
  end

  defp bit_shape(assigns) do
    # Default fallback
    ~H"""
    <div
      class="rounded-full animate-pulse-slow"
      style={"width: #{@size}px; height: #{@size}px; background: #{@color}66; box-shadow: 0 0 #{round(@energy * 15)}px #{@color}66;"}
    >
    </div>
    """
  end

  # ===========================================================================
  # Legend
  # ===========================================================================

  attr :color, :string, required: true
  attr :label, :string, required: true

  defp legend_item(assigns) do
    ~H"""
    <div class="flex items-center gap-1 px-2 py-0.5 bg-black/40 rounded">
      <div class="w-2 h-2 rounded-full" style={"background: #{@color};"}></div>
      <span class="text-gray-400">{@label}</span>
    </div>
    """
  end

  # ===========================================================================
  # Detail Panel
  # ===========================================================================

  attr :bit, :any, default: nil
  attr :on_close, :string, default: nil
  attr :class, :string, default: ""

  def thunderbit_detail(assigns) do
    ~H"""
    <div
      :if={@bit}
      class={[
        "backdrop-blur-lg bg-slate-900/90 rounded-xl border border-cyan-500/30 p-4",
        "animate-slide-in",
        @class
      ]}
    >
      <%!-- Header --%>
      <div class="flex items-start justify-between mb-4">
        <div class="flex items-center gap-2">
          <div
            class="w-4 h-4 rounded-full"
            style={"background: #{Thunderbit.color(@bit)};"}
          >
          </div>
          <span class="text-sm font-semibold text-white capitalize">{@bit.kind}</span>
        </div>
        <button
          :if={@on_close}
          phx-click={@on_close}
          class="text-gray-400 hover:text-white transition-colors"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <%!-- Content --%>
      <p class="text-gray-200 text-sm mb-4">{@bit.content}</p>

      <%!-- Metrics --%>
      <div class="grid grid-cols-2 gap-2 mb-4">
        <div class="bg-black/30 rounded-lg p-2">
          <div class="text-xs text-gray-400">Energy</div>
          <div class="flex items-center gap-2">
            <div class="flex-1 h-1.5 bg-gray-700 rounded-full overflow-hidden">
              <div
                class="h-full bg-gradient-to-r from-cyan-500 to-blue-500"
                style={"width: #{@bit.energy * 100}%;"}
              >
              </div>
            </div>
            <span class="text-xs text-cyan-300">{round(@bit.energy * 100)}%</span>
          </div>
        </div>
        <div class="bg-black/30 rounded-lg p-2">
          <div class="text-xs text-gray-400">Salience</div>
          <div class="flex items-center gap-2">
            <div class="flex-1 h-1.5 bg-gray-700 rounded-full overflow-hidden">
              <div
                class="h-full bg-gradient-to-r from-amber-500 to-orange-500"
                style={"width: #{@bit.salience * 100}%;"}
              >
              </div>
            </div>
            <span class="text-xs text-amber-300">{round(@bit.salience * 100)}%</span>
          </div>
        </div>
      </div>

      <%!-- Tags --%>
      <div :if={@bit.tags != []} class="mb-4">
        <div class="text-xs text-gray-400 mb-2">Tags</div>
        <div class="flex flex-wrap gap-1">
          <%= for tag <- @bit.tags do %>
            <span class={[
              "px-2 py-0.5 rounded-full text-xs",
              tag_class(tag)
            ]}>
              {tag}
            </span>
          <% end %>
        </div>
      </div>

      <%!-- Ontology Path --%>
      <div class="mb-4">
        <div class="text-xs text-gray-400 mb-1">Ontology Path</div>
        <div class="text-xs text-gray-300 font-mono">
          {Enum.join(@bit.ontology_path, " → ")}
        </div>
      </div>

      <%!-- Maxims --%>
      <div :if={@bit.maxims != []} class="mb-4">
        <div class="text-xs text-gray-400 mb-1">MCP Maxims</div>
        <%= for maxim <- @bit.maxims do %>
          <div class="text-xs text-purple-300 italic">"{maxim}"</div>
        <% end %>
      </div>

      <%!-- Meta --%>
      <div class="text-xs text-gray-500 border-t border-gray-700 pt-2">
        <div class="flex justify-between">
          <span>Source: {to_string(@bit.source)}</span>
          <span>Status: {to_string(@bit.status)}</span>
        </div>
        <div :if={@bit.owner} class="mt-1">Owner: {@bit.owner}</div>
      </div>
    </div>
    """
  end

  defp tag_class(tag) do
    cond do
      String.starts_with?(tag, "PAC:") ->
        "bg-purple-500/30 text-purple-300 border border-purple-500/30"

      String.starts_with?(tag, "zone:") ->
        "bg-blue-500/30 text-blue-300 border border-blue-500/30"

      String.starts_with?(tag, "topic:") ->
        "bg-green-500/30 text-green-300 border border-green-500/30"

      true ->
        "bg-gray-500/30 text-gray-300 border border-gray-500/30"
    end
  end

  # Extract position from either struct field or nested geometry in DTO
  defp extract_position(%{position: %{x: _, y: _} = pos}), do: pos
  defp extract_position(%{geometry: %{position: %{x: _, y: _} = pos}}), do: pos
  defp extract_position(%{"position" => %{"x" => x, "y" => y}}), do: %{x: x, y: y}
  defp extract_position(%{"geometry" => %{"position" => %{"x" => x, "y" => y}}}), do: %{x: x, y: y}
  defp extract_position(_), do: %{x: 0.5, y: 0.5}

  # ===========================================================================
  # Input Panel
  # ===========================================================================

  attr :class, :string, default: ""
  attr :form, :map, required: true
  attr :on_submit, :string, default: "submit_input"
  attr :placeholder, :string, default: "Type or speak a Thunderbit..."
  attr :voice_enabled, :boolean, default: false

  def thunderbit_input(assigns) do
    ~H"""
    <.form for={@form} phx-submit={@on_submit} id="thunderbit-input-form" class={["flex gap-2", @class]}>
      <div class="flex-1 relative">
        <input
          type="text"
          name={@form[:content].name}
          id={@form[:content].id}
          value={@form[:content].value}
          placeholder={@placeholder}
          class="w-full bg-slate-900/80 border border-cyan-500/30 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-cyan-400/60 focus:ring-1 focus:ring-cyan-400/30"
          autocomplete="off"
          phx-debounce="100"
        />
        <button
          :if={@voice_enabled}
          type="button"
          phx-click="toggle_voice"
          class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-cyan-400 transition-colors"
        >
          <.icon name="hero-microphone" class="w-5 h-5" />
        </button>
      </div>
      <button
        type="submit"
        class="px-6 py-3 bg-gradient-to-r from-cyan-600 to-blue-600 hover:from-cyan-500 hover:to-blue-500 rounded-xl text-white font-medium transition-all shadow-lg shadow-cyan-500/20 hover:shadow-cyan-500/40"
      >
        Spawn
      </button>
    </.form>
    """
  end
end
