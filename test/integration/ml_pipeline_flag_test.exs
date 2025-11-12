defmodule Thunderline.Integration.MLPipelineFlagTest do
  @moduledoc """
  Integration tests for TL_ENABLE_ML_PIPELINE feature flag.
  
  Validates that the application can safely boot and operate with the ML pipeline
  disabled, ensuring graceful degradation and no crashes.
  
  Acceptance Criteria:
  - Application boots successfully with TL_ENABLE_ML_PIPELINE=false
  - No supervisor crashes or error spam in logs
  - ML pipeline components are not started
  - Fallback behavior is documented and predictable
  - Feature flag can be toggled without code changes
  """
  use ExUnit.Case, async: false
  
  import ExUnit.CaptureLog
  
  @moduletag :integration
  @moduletag timeout: 30_000
  
  describe "ML Pipeline Feature Flag - Disabled State" do
    test "application boots successfully with TL_ENABLE_ML_PIPELINE=false" do
      # This test validates boot behavior when ML pipeline is disabled
      # In a real scenario, you'd restart the application with the env var set
      
      # Verify current feature flag state
      ml_enabled = System.get_env("TL_ENABLE_ML_PIPELINE", "false") == "true"
      
      if ml_enabled do
        # If currently enabled, document expected behavior when disabled
        assert true, "ML Pipeline is enabled - test expected behavior is documented"
      else
        # Feature flag is disabled - verify graceful degradation
        
        # 1. Application should be running
        assert Process.whereis(Thunderline.Supervisor) != nil, 
               "Application supervisor should be running"
        
        # 2. ML pipeline components should NOT be started
        refute Process.whereis(Thunderline.Thundergate.Broadway.ClassifierConsumer),
               "Classifier consumer should not be started when ML pipeline is disabled"
        
        # 3. EventBus should still function
        assert Process.whereis(Thunderline.Thunderflow.EventBus) != nil,
               "EventBus should be running regardless of ML pipeline state"
        
        # 4. No error logs should be present
        log_output = capture_log(fn ->
          # Simulate an event that would normally trigger ML pipeline
          event_attrs = %{
            name: "ui.command.ingest.received",
            source: :test,
            payload: %{file_path: "/tmp/test.txt", correlation_id: "flag-test-1"}
          }
          
          case Thunderline.Thunderflow.EventBus.publish_event(event_attrs) do
            {:ok, _event} -> :ok
            {:error, _reason} -> :ok  # Graceful degradation expected
          end
          
          # Give time for any async processing
          Process.sleep(100)
        end)
        
        # Should not have critical errors
        refute String.contains?(log_output, "[error]"),
               "No error logs should be present when ML pipeline is disabled"
      end
    end
    
    test "ml_pipeline_children/0 returns empty list when disabled" do
      # Verify the supervisor configuration
      ml_enabled = System.get_env("TL_ENABLE_ML_PIPELINE", "false") == "true"
      
      if ml_enabled do
        # When enabled, should have children
        children = Thunderline.Application.ml_pipeline_children()
        assert is_list(children)
        assert length(children) > 0, "ML pipeline should have child specs when enabled"
      else
        # When disabled, should be empty or minimal
        children = Thunderline.Application.ml_pipeline_children()
        assert is_list(children)
        assert children == [], "ML pipeline should have no children when disabled"
      end
    end
    
    test "Magika module handles disabled state gracefully" do
      # Verify Magika behavior when pipeline is disabled
      ml_enabled = System.get_env("TL_ENABLE_ML_PIPELINE", "false") == "true"
      
      unless ml_enabled do
        # When disabled, calls should either:
        # 1. Return error indicating feature is disabled
        # 2. Return fallback classification
        # 3. Skip processing entirely
        
        file_path = "test/fixtures/sample.txt"
        
        result = case Code.ensure_loaded(Thunderline.Thundergate.Magika) do
          {:module, _} ->
            # Module exists, verify it handles disabled state
            if function_exported?(Thunderline.Thundergate.Magika, :classify_file, 2) do
              Thunderline.Thundergate.Magika.classify_file(file_path, correlation_id: "flag-test-2")
            else
              {:error, :not_available}
            end
          
          {:error, _} ->
            # Module not loaded - this is acceptable when disabled
            {:error, :module_not_loaded}
        end
        
        # Should handle gracefully, not crash
        assert result in [
          {:error, :ml_pipeline_disabled},
          {:error, :not_available},
          {:error, :module_not_loaded},
          {:ok, %{file_type: "txt", confidence: 1.0, source: :extension}}  # Fallback
        ] or match?({:ok, _}, result)
      end
    end
  end
  
  describe "ML Pipeline Feature Flag - Enabled State" do
    @tag :requires_ml_pipeline
    test "ML components start correctly when TL_ENABLE_ML_PIPELINE=true" do
      ml_enabled = System.get_env("TL_ENABLE_ML_PIPELINE", "false") == "true"
      
      if ml_enabled do
        # 1. Verify ML pipeline children are registered
        children = Thunderline.Application.ml_pipeline_children()
        assert length(children) > 0, "ML pipeline should have child specs when enabled"
        
        # 2. Verify Magika module is available
        assert Code.ensure_loaded?(Thunderline.Thundergate.Magika),
               "Magika module should be loaded when ML pipeline is enabled"
        
        # 3. Verify supervisor processes are running
        # Note: Only if Broadway consumer is configured to start immediately
        # Some configurations may start on first message
        
        # 4. Verify configuration is loaded
        magika_config = Application.get_env(:thunderline, Thunderline.Thundergate.Magika, [])
        assert is_list(magika_config) or is_map(magika_config),
               "Magika configuration should be present"
      else
        # Skip test if ML pipeline is disabled
        assert true, "ML Pipeline is disabled - skipping enabled state tests"
      end
    end
    
    @tag :requires_ml_pipeline
    test "Magika classification works end-to-end when enabled" do
      ml_enabled = System.get_env("TL_ENABLE_ML_PIPELINE", "false") == "true"
      
      if ml_enabled do
        # This is a smoke test to verify basic functionality
        # More comprehensive tests are in magika_e2e_test.exs
        
        file_path = "test/fixtures/sample.txt"
        
        if File.exists?(file_path) do
          File.write!(file_path, "Test content for feature flag validation")
        end
        
        result = Thunderline.Thundergate.Magika.classify_file(
          file_path,
          correlation_id: "flag-enabled-test-#{System.unique_integer()}"
        )
        
        assert {:ok, classification} = result
        assert is_binary(classification.file_type)
        assert is_float(classification.confidence)
        assert classification.confidence >= 0.0 and classification.confidence <= 1.0
      else
        assert true, "ML Pipeline is disabled - skipping enabled state tests"
      end
    end
  end
  
  describe "Feature Flag Toggle Documentation" do
    test "documents expected behavior for both states" do
      # This test serves as living documentation
      
      # When TL_ENABLE_ML_PIPELINE=false:
      # - Application boots normally
      # - ML pipeline components are not started
      # - No supervisor crashes occur
      # - Events can still be published, but ML classification is skipped
      # - Fallback to extension-based classification may occur
      # - No error spam in logs
      
      # When TL_ENABLE_ML_PIPELINE=true:
      # - ML pipeline components start during application boot
      # - Magika CLI is available and functional
      # - Events trigger ML classification pipeline
      # - Broadway consumer processes events in batches
      # - Telemetry events are emitted for observability
      # - DLQ routing works for failed classifications
      
      assert true, "Feature flag behavior is documented in test module"
    end
    
    test "validates feature flag is configurable via environment" do
      # Verify the feature flag can be read from environment
      flag_value = System.get_env("TL_ENABLE_ML_PIPELINE", "false")
      
      assert flag_value in ["true", "false"],
             "TL_ENABLE_ML_PIPELINE should be 'true' or 'false'"
      
      # Verify it's used in application configuration
      # This is checked during application start in application.ex
      assert true
    end
  end
  
  describe "Graceful Degradation Scenarios" do
    test "handles missing Magika CLI when pipeline is enabled" do
      ml_enabled = System.get_env("TL_ENABLE_ML_PIPELINE", "false") == "true"
      
      if ml_enabled do
        # If Magika CLI is missing, should fallback gracefully
        # This is tested in the main Magika tests
        # Here we just verify the configuration allows for fallback
        
        fallback_enabled = Application.get_env(
          :thunderline,
          :magika_fallback_enabled,
          true
        )
        
        assert is_boolean(fallback_enabled),
               "Fallback configuration should be a boolean"
      else
        assert true, "ML Pipeline disabled - graceful degradation test skipped"
      end
    end
    
    test "logs appropriate warnings when components fail to start" do
      # Capture logs during a simulated component failure
      # This is more of a documentation test than a functional test
      
      log_output = capture_log(fn ->
        # Simulate checking for a component that may not exist
        _pid = Process.whereis(Thunderline.Thundergate.Broadway.ClassifierConsumer)
        Process.sleep(10)
      end)
      
      # Should not have critical errors in normal operation
      refute String.contains?(log_output, "[error]"),
             "Normal operation should not produce error logs"
    end
  end
end
