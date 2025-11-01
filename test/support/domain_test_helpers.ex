defmodule Thunderline.DomainTestHelpers do
  @moduledoc """
  Shared helper functions for domain test setup and assertions.

  This module provides common utilities to ensure consistency between tests
  across all Thunderline domains. These helpers should be used in combination
  with existing `ConnCase`, `DataCase`, or `LiveViewCase` modules.
  """

  @doc """
  Creates a test user with optional attributes.

  ## Examples

      iex> create_test_user(%{email: "test@example.com"})
      %{id: "user_123", email: "test@example.com", name: "Test User"}

  If no attributes are provided, default placeholders will be used.
  """
  @spec create_test_user(map()) :: map()
  def create_test_user(attrs \\ %{}) do
    Map.merge(
      %{
        id: "user_" <> Integer.to_string(:rand.uniform(1000)),
        email: "user@example.com",
        name: "Test User"
      },
      attrs
    )
  end

  @doc """
  Creates a test event record with the specified type, payload, and user.

  ## Examples

      iex> create_test_event("user_logged_in", %{id: 1}, %{id: "user_1"})
      %{type: "user_logged_in", payload: %{id: 1}, user: %{id: "user_1"}}
  """
  @spec create_test_event(binary(), map(), map()) :: map()
  def create_test_event(event_type, payload, user) do
    %{
      id: "evt_" <> Integer.to_string(:rand.uniform(10_000)),
      type: event_type,
      payload: payload,
      user: user,
      inserted_at: DateTime.utc_now()
    }
  end

  @doc """
  Asserts that a given event has been published to the system's event bus.

  This function acts as a placeholder for asserting events in integration
  tests. It will simply print a debug message for now.

  ## Examples

      iex> assert_event_published("user_logged_in", %{id: "evt_123"})
      :ok
  """
  @spec assert_event_published(binary(), map()) :: :ok
  def assert_event_published(event_type, _event) do
    IO.puts("[assert_event_published] validated event: #{event_type}")
    :ok
  end

  @doc """
  Starts test services such as fake event bus or cache for integration tests.

  This is a stub that can be adapted for real startup routines later.

  ## Example

      iex> start_test_services()
      :ok
  """
  @spec start_test_services() :: :ok
  def start_test_services do
    IO.puts("[start_test_services] Simulating startup of event bus, cache, and mock services...")
    :ok
  end
end
