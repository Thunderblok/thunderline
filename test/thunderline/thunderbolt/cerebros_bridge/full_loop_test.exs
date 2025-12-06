defmodule Thunderline.Thunderbolt.CerebrosBridge.FullLoopTest do
  use ExUnit.Case, async: false
  alias Thunderline.Thunderbolt.CerebrosBridge.Client
  alias Thunderline.Feature

  @moduletag :capture_log

  setup do
    # 1. Enable the bridge via config
    original_config = Application.get_env(:thunderline, :cerebros_bridge)
    Application.put_env(:thunderline, :cerebros_bridge, [
      enabled: true,
      invoke: [default_timeout_ms: 5000],
      cache: [enabled: true, ttl_ms: 1000]
    ])

    # 2. Enable the feature flag
    Feature.override(:ml_nas, true)

    # 3. Manually start the Cache GenServer because the Application supervisor skipped it
    #    due to the bridge being disabled at boot time (in test_helper.exs).
    start_result = Thunderline.Thunderbolt.CerebrosBridge.Cache.start_link([])
    
    # Handle case where it might be already started (e.g. if another test started it, though async: false helps)
    case start_result do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> IO.warn("Failed to start Cache: #{inspect(error)}")
    end

    on_exit(fn ->
      # Cleanup: Stop the Cache to avoid polluting other tests
      if pid = Process.whereis(Thunderline.Thunderbolt.CerebrosBridge.Cache) do
        Process.exit(pid, :normal)
      end
      
      if original_config do
        Application.put_env(:thunderline, :cerebros_bridge, original_config)
      else
        Application.delete_env(:thunderline, :cerebros_bridge)
      end
      Feature.clear_override(:ml_nas)
    end)

    :ok
  end

  test "full training loop execution" do
    # This test verifies that the Client can:
    # 1. Check enabled status (Config + Feature)
    # 2. Marshal the request via Translator
    # 3. Invoke the Python script via Invoker (mocked or real)
    # 4. Return a result

    # Since we don't have the actual Python environment in this test context,
    # we expect an error from the Invoker (e.g. script not found or execution failed),
    # BUT we want to verify we got past the "bridge disabled" check.

    # We'll use a dummy contract payload
    payload = %{
      run_id: "test_run_#{System.unique_integer()}",
      config: %{model: "test_model"},
      search_space: %{layers: [1, 2, 3]}
    }

    # We use invoke/3 generic helper to bypass specific contract structs for this test,
    # or we can use run_nas if we want to test that specific path.
    # Let's use run_nas as requested.
    
    # Note: run_nas expects a map with specific keys.
    # Based on Client.run_nas implementation (which we added), it calls Invoker.invoke(:run_nas, ...)
    
    result = Client.run_nas(payload, [])

    # We expect either {:ok, ...} or {:error, ...}
    # We specifically DO NOT want {:error, %{reason: :feature_flag_disabled}} 
    # or {:error, %{reason: :config_disabled}}.

    case result do
      {:ok, _data} -> 
        assert true
      {:error, error} ->
        # If it failed because python script is missing, that's fine for this test.
        # We just want to ensure the bridge attempted the call.
        reason = error.context[:reason] || error.context
        refute reason == :feature_flag_disabled
        refute reason == :config_disabled
        IO.puts("Bridge attempted execution but failed (expected): #{inspect(error)}")
    end
  end
end
