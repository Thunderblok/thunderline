defmodule Thunderline.Thunderbolt.CerebrosBridge.RunOptionsTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CerebrosBridge.RunOptions

  describe "prepare/2" do
    test "generates run_id, merges metadata, and shapes enqueue options" do
      spec = %{
        "budget" => %{"max_models" => 3},
        "parameters" => %{"learning_rate" => 0.01},
        "metadata" => %{note: "initial"},
        "extra" => %{foo: "bar"}
      }

      {run_id, updated_spec, opts} =
        RunOptions.prepare(spec, meta: %{operator: "alice"}, source: "dashboard")

      assert is_binary(run_id)
      assert updated_spec["run_id"] == run_id
      assert Keyword.get(opts, :run_id) == run_id
      assert Keyword.get(opts, :budget) == %{"max_models" => 3}
      assert Keyword.get(opts, :parameters) == %{"learning_rate" => 0.01}
      assert Keyword.get(opts, :extra) == %{foo: "bar"}

  metadata = Keyword.fetch!(opts, :meta)
  assert metadata["operator"] == "alice"
  assert metadata["source"] == "dashboard"
  assert metadata["note"] == "initial"
  assert is_binary(metadata["submitted_at"])
    end

    test "reuses supplied run_id, pulls pulse data, and strips nil values" do
      run_id = "run-123"

      spec = %{
        "run_id" => run_id,
        "pulse" => %{"id" => "pulse-1", "tau" => 42},
        "extra" => nil
      }

      {returned_id, updated_spec, opts} =
        RunOptions.prepare(spec, operator: :system, meta: %{source: :cli})

      assert returned_id == run_id
      assert updated_spec["run_id"] == run_id
      assert Keyword.get(opts, :run_id) == run_id
      assert Keyword.get(opts, :pulse_id) == "pulse-1"
      assert Keyword.get(opts, :tau) == 42

  metadata = Keyword.fetch!(opts, :meta)
  assert metadata["operator"] == "system"
  assert metadata["source"] == :cli

      refute Keyword.has_key?(opts, :extra)
    end

    test "returns error for invalid spec" do
      assert {:error, :invalid_spec} = RunOptions.prepare("oops")
    end
  end
end
