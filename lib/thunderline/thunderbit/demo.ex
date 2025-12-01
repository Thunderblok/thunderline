defmodule Thunderline.Thunderbit.Demo do
  @moduledoc """
  Thunderbit Demo - Canonical Text → Sensory → Cognitive → UI Flow

  This module demonstrates the "physics of meaning" - how text flows through
  the Thunderbit Protocol to become visible, linked bits on the UI.

  ## The Flow

  1. User types text: "What is the weather?"
  2. Protocol spawns sensory bit (input perception)
  3. Protocol binds classification (→ :question kind)
  4. Protocol spawns cognitive bit (reasoning)
  5. Protocol links sensory → cognitive (:feeds relation)
  6. UIContract broadcasts slim DTOs to front-end
  7. Front-end renders 2 bits with arrow between them

  ## Usage

      # Run the demo intake flow
      {:ok, bits, edges, ctx} = Demo.intake("What is the weather?", "pac_ezra")

      # Or run the full demo with broadcast
      :ok = Demo.run("What is the weather?", "pac_ezra")
  """

  alias Thunderline.Thunderbit.{Protocol, Context, UIContract}

  require Logger

  @doc """
  Demonstrates the canonical text intake flow.

  Takes raw text input and transforms it into linked Thunderbits,
  returning the bits, edges, and final context.

  ## Parameters
  - `text` - The input text to process
  - `pac_id` - The PAC (agent) ID for context

  ## Returns
  - `{:ok, bits, edges, ctx}` on success

  ## Example

      {:ok, [sensory, cognitive], [edge], ctx} = Demo.intake("What is the weather?", "ezra")
      IO.inspect(sensory.category)  # => :sensory
      IO.inspect(cognitive.category)  # => :cognitive
      IO.inspect(edge.relation)  # => :feeds
  """
  @spec intake(String.t(), String.t()) :: {:ok, [map()], [map()], Context.t()} | {:error, term()}
  def intake(text, pac_id) when is_binary(text) and is_binary(pac_id) do
    Logger.info("[Demo.intake] Starting intake flow for PAC #{pac_id}")
    
    # 1. Create fresh context
    ctx = Context.new(pac_id: pac_id, zone: :cortex)
    
    # 2. Spawn sensory bit (input perception)
    with {:ok, sensory, ctx} <- Protocol.spawn_bit(:sensory, %{content: text}, ctx) do
      Logger.debug("[Demo.intake] Spawned sensory bit: #{sensory.id}")
      
      # 3. Bind classification to determine intent
      {:ok, sensory, ctx} = Protocol.bind(sensory, &classify_intent/2, ctx)
      Logger.debug("[Demo.intake] Classified as: #{sensory.kind}")
      
      # 4. Spawn cognitive bit (reasoning layer)
      with {:ok, cognitive, ctx} <- Protocol.spawn_bit(:cognitive, %{
             content: text,
             input_bit_id: sensory.id
           }, ctx) do
        Logger.debug("[Demo.intake] Spawned cognitive bit: #{cognitive.id}")
        
        # 5. Link sensory → cognitive with :feeds relation
        with {:ok, edge, ctx} <- Protocol.link(sensory, cognitive, :feeds, ctx) do
          Logger.debug("[Demo.intake] Created edge: #{edge.id} (#{edge.relation})")
          
          bits = [sensory, cognitive]
          edges = [edge]
          
          # Log the final context state
          Logger.info("[Demo.intake] Complete: #{length(bits)} bits, #{length(edges)} edges")
          Logger.debug("[Demo.intake] Context event_log: #{length(ctx.event_log)} events")
          
          {:ok, bits, edges, ctx}
        end
      end
    end
  end

  @doc """
  Runs the full demo with UI broadcast.

  This is the end-to-end demonstration: text comes in, bits come out,
  and the front-end receives slim DTOs via PubSub.

  ## Parameters
  - `text` - The input text to process
  - `pac_id` - The PAC (agent) ID for context

  ## Returns
  - `:ok` after successful broadcast

  ## Side Effects
  - Broadcasts `{:thunderbit_spawn, %{bits: [...], edges: [...]}}` to `"thunderbits:lobby"`

  ## Example

      :ok = Demo.run("What is the weather?", "ezra")
      # Front-end receives 2 bit DTOs and 1 edge DTO
  """
  @spec run(String.t(), String.t()) :: :ok | {:error, term()}
  def run(text, pac_id) when is_binary(text) and is_binary(pac_id) do
    Logger.info("[Demo.run] Starting demo: '#{String.slice(text, 0, 30)}...'")
    
    case intake(text, pac_id) do
      {:ok, bits, edges, ctx} ->
        # 6. Broadcast to UI via slim DTOs
        Logger.info("[Demo.run] Broadcasting #{length(bits)} bits, #{length(edges)} edges")
        UIContract.broadcast(bits, edges)
        
        # Log summary
        Logger.info("""
        [Demo.run] Complete!
        - Bits: #{inspect(Enum.map(bits, & &1.category))}
        - Edges: #{inspect(Enum.map(edges, & &1.relation))}
        - Events: #{length(ctx.event_log)}
        """)
        
        :ok
        
      {:error, reason} ->
        Logger.error("[Demo.run] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns a sample demo result for testing/inspection.

  Useful for seeing what the output looks like without running the full flow.
  """
  @spec sample() :: {:ok, [map()], [map()], Context.t()}
  def sample do
    intake("What is the weather in Tokyo?", "demo_pac")
  end

  @doc """
  Returns the DTOs that would be sent to the front-end.

  Useful for inspecting the slim DTO format.
  """
  @spec sample_dtos() :: {:ok, [map()], [map()]}
  def sample_dtos do
    case sample() do
      {:ok, bits, edges, _ctx} ->
        bit_dtos = UIContract.to_dtos(bits, edges)
        edge_dtos = Enum.map(edges, &UIContract.edge_to_dto/1)
        {:ok, bit_dtos, edge_dtos}
    end
  end

  # ===========================================================================
  # Classification Continuation
  # ===========================================================================

  @doc false
  def classify_intent(bit, ctx) do
    content = bit.content || ""
    
    kind =
      cond do
        # Questions
        String.contains?(content, "?") -> :question
        String.match?(content, ~r/^(what|who|when|where|why|how)\b/i) -> :question
        
        # Commands
        String.match?(content, ~r/^(go|move|navigate|run|stop|start)\b/i) -> :command
        String.match?(content, ~r/^(do|make|create|delete|update)\b/i) -> :command
        
        # Memory operations
        String.match?(content, ~r/^(remember|save|store|forget|recall)\b/i) -> :memory
        
        # Default: general intent
        true -> :intent
      end
    
    # Update the bit with classification
    new_bit = %{bit | kind: kind}
    
    # Log the classification
    ctx = Context.log(ctx, :info, "classify_intent", "Classified as #{kind}")
    
    {:ok, new_bit, ctx}
  end

  # ===========================================================================
  # Helper: Inspect Context
  # ===========================================================================

  @doc """
  Pretty-prints the context state for debugging.
  """
  @spec inspect_context(Context.t()) :: :ok
  def inspect_context(%Context{} = ctx) do
    IO.puts("""
    
    === Context State ===
    Session: #{ctx.session_id}
    PAC: #{ctx.pac_id || "nil"}
    Zone: #{ctx.zone || "nil"}
    
    Bits (#{map_size(ctx.bits_by_id)}):
    #{format_bits(ctx.bits_by_id)}
    
    Edges (#{length(ctx.edges)}):
    #{format_edges(ctx.edges)}
    
    Events (#{length(ctx.event_log)}):
    #{format_events(ctx.event_log)}
    =====================
    """)
    
    :ok
  end

  defp format_bits(bits_by_id) do
    bits_by_id
    |> Enum.map(fn {id, bit} ->
      "  - #{String.slice(id, 0, 8)}... [#{bit.category}] #{String.slice(bit.content || "", 0, 30)}"
    end)
    |> Enum.join("\n")
  end

  defp format_edges(edges) do
    edges
    |> Enum.map(fn edge ->
      "  - #{String.slice(edge.from_id, 0, 8)} --[#{edge.relation}]--> #{String.slice(edge.to_id, 0, 8)}"
    end)
    |> Enum.join("\n")
  end

  defp format_events(events) do
    events
    |> Enum.take(5)
    |> Enum.map(fn event ->
      "  - [#{event.type}] #{inspect(event.data)}"
    end)
    |> Enum.join("\n")
    |> then(fn s ->
      if length(events) > 5, do: s <> "\n  ... and #{length(events) - 5} more", else: s
    end)
  end
end
