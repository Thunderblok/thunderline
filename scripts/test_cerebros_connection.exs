#!/usr/bin/env elixir

# Cerebros Connection Test Script
# Usage: mix run scripts/test_cerebros_connection.exs

Mix.install([
  {:req, "~> 0.5"}
])

defmodule CerebrosConnectionTest do
  @moduledoc """
  Tests connectivity to the Cerebros Python service.
  """

  def run do
    service_url = System.get_env("CEREBROS_SERVICE_URL", "http://localhost:5000")

    IO.puts("\n🧪 Testing Cerebros Connection")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Service URL: #{service_url}")
    IO.puts("")

    # Test 1: Health Check
    IO.puts("Test 1: Health Check Endpoint")
    case Req.get("#{service_url}/health") do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("✅ Health check passed")
        IO.inspect(body, label: "Response")
      {:ok, %{status: status}} ->
        IO.puts("❌ Health check failed with status: #{status}")
      {:error, reason} ->
        IO.puts("❌ Health check error: #{inspect(reason)}")
    end
    IO.puts("")

    # Test 2: API Version
    IO.puts("Test 2: API Version Endpoint")
    case Req.get("#{service_url}/api/version") do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("✅ Version check passed")
        IO.inspect(body, label: "Response")
      {:ok, %{status: status}} ->
        IO.puts("❌ Version check failed with status: #{status}")
      {:error, reason} ->
        IO.puts("❌ Version check error: #{inspect(reason)}")
    end
    IO.puts("")

    # Test 3: Simple NAS Query
    IO.puts("Test 3: Simple NAS Query")
    payload = %{
      spec: %{
        model: "test_model",
        dataset: "test_dataset",
        search_space: %{
          layers: [1, 2, 3],
          units: [32, 64, 128]
        }
      },
      budget: %{
        max_trials: 3,
        timeout_seconds: 60
      }
    }

    case Req.post("#{service_url}/api/nas/query", json: payload) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        IO.puts("✅ NAS query test passed")
        IO.inspect(body, label: "Response")
      {:ok, %{status: status, body: body}} ->
        IO.puts("❌ NAS query failed with status: #{status}")
        IO.inspect(body, label: "Error Response")
      {:error, reason} ->
        IO.puts("❌ NAS query error: #{inspect(reason)}")
    end
    IO.puts("")

    IO.puts("=" |> String.duplicate(50))
    IO.puts("✨ Connection test complete!")
  end
end

CerebrosConnectionTest.run()
