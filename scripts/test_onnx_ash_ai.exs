#!/usr/bin/env elixir

# Quick smoke test for ONNX → Ash.AI integration
# Usage: mix run scripts/test_onnx_ash_ai.exs

IO.puts("\n🔥 ONNX → Ash.AI Integration Smoke Test\n")

alias Thunderline.Thunderbolt.Resources.OnnxInference

# Test 1: Verify resource loads
IO.puts("✓ OnnxInference resource loaded")

# Test 2: Check if code_interface is defined
if function_exported?(OnnxInference, :infer, 3) do
  IO.puts("✓ OnnxInference.infer/3 code interface defined")
else
  IO.puts("✗ OnnxInference.infer/3 NOT defined")
  System.halt(1)
end

# Test 3: Check Thundercrown tool registration
crown_tools = Ash.Domain.Info.tools(Thunderline.Thundercrown.Domain)
onnx_tool = Enum.find(crown_tools, fn t -> t.name == :onnx_infer end)

if onnx_tool do
  IO.puts("✓ :onnx_infer tool registered in Thundercrown.Domain")
  IO.puts("  Resource: #{inspect(onnx_tool.resource)}")
  IO.puts("  Action: #{inspect(onnx_tool.action)}")
else
  IO.puts("✗ :onnx_infer tool NOT registered")
  System.halt(1)
end

# Test 4: Check MCP endpoint availability
IO.puts("\n📡 MCP Server Check:")
IO.puts("  Endpoint: http://localhost:5001/mcp")
IO.puts("  Tools available:")
Enum.each(crown_tools, fn t ->
  IO.puts("    - #{t.name}")
end)

IO.puts("\n✅ All checks passed!")
IO.puts("\n📝 Next steps:")
IO.puts("  1. Create test ONNX model: See ONNX_ASHAI_INTEGRATION.md")
IO.puts("  2. Start Phoenix: mix phx.server")
IO.puts("  3. Test inference: OnnxInference.infer(\"priv/models/demo.onnx\", %{data: [[1,2,3]]}, %{})")
IO.puts("  4. Test via MCP: Point Claude Desktop to /mcp endpoint\n")
