defmodule Thunderline.EventNormalizationPropertyTest do
  use ExUnit.Case, async: true

  @moduledoc false

  describe "normalize/1 idempotence" do
    test "normalizing an already normalized event is identity" do
      input = %{
        "type" => "user_created",
        "payload" => %{"id" => 1},
        "source_domain" => "thunderlink"
      }

      {:ok, first} = Thunderline.Event.normalize(input)
      {:ok, second} = Thunderline.Event.normalize(first)
      assert first == second
    end

    test "normalize produces required defaults" do
      {:ok, event} =
        Thunderline.Event.normalize(%{
          "type" => "agent_spawned",
          "payload" => %{},
          "source_domain" => "thunderflow"
        })

      assert event.hop_count == 0
      assert is_binary(event.correlation_id)
      assert %DateTime{} = event.timestamp
    end
  end
end
