# 🧪 Test Agent Deployment Plan

**Agent ID:** `test-agent`  
**Epic:** 3.1 Cerebros Integration Execution  
**Priority:** 🟡 HIGH (Priority 2)  
**Duration:** 2 hours  
**Can Run Parallel With:** fix-agent, config-agent  
**Dependencies:** Needs code from fix-agent to compile

## Mission
Write comprehensive integration tests for Cerebros bridge functionality.

## Tasks

### Task 1: Bridge Integration Tests (45 min)
**File:** `test/thunderline/thunderbolt/cerebros_bridge/run_worker_test.exs`

```elixir
defmodule Thunderline.Thunderbolt.CerebrosBridge.RunWorkerTest do
  use Thunderline.DataCase, async: true
  alias Thunderline.Thunderbolt.CerebrosBridge.RunWorker

  describe "run/1" do
    test "creates worker job with valid params" do
      params = %{"config" => %{"epochs" => 100}}
      assert {:ok, job} = RunWorker.run(params)
      assert job.args["config"]["epochs"] == 100
    end

    test "rejects invalid params" do
      assert {:error, _} = RunWorker.run(%{})
    end

    test "handles service unavailable" do
      # Mock service down scenario
      assert {:error, :service_unavailable} = RunWorker.run(%{"fail" => true})
    end
  end
end
```

**Write 10+ test cases covering:**
- Valid job creation
- Invalid parameters
- Service errors
- Timeout handling
- Result processing

---

### Task 2: LiveView Event Tests (45 min)
**File:** `test/thunderline_web/live/cerebros_live_test.exs`

```elixir
defmodule ThunderlineWeb.CerebrosLiveTest do
  use ThunderlineWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "launch_nas_run event" do
    test "creates job and shows success flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cerebros")
      
      view
      |> form("#launch-form", nas_run: %{config: %{epochs: 100}})
      |> render_submit()
      
      assert has_element?(view, ".flash-info", "NAS run launched")
    end

    test "shows error flash on failure", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cerebros")
      
      # Trigger error condition
      assert render_click(view, "launch_nas_run", %{invalid: true}) =~ "Failed"
    end
  end

  describe "cancel_run event" do
    test "cancels running job", %{conn: conn} do
      # Test cancel functionality
    end
  end

  describe "view_results event" do
    test "displays job results", %{conn: conn} do
      # Test results display
    end
  end
end
```

---

### Task 3: Error Scenario Tests (30 min)
**File:** `test/thunderline/thunderbolt/cerebros_bridge/error_handling_test.exs`

```elixir
defmodule Thunderline.Thunderbolt.CerebrosBridge.ErrorHandlingTest do
  use Thunderline.DataCase

  test "handles network timeout" do
    # Mock timeout scenario
  end

  test "handles service 500 error" do
    # Mock server error
  end

  test "handles invalid response format" do
    # Mock malformed response
  end

  test "retries transient failures" do
    # Test retry logic
  end
end
```

**Cover scenarios:**
- Network timeouts
- Service errors (500, 503)
- Invalid responses
- Retry logic
- Circuit breaker (if implemented)

---

## Deliverables

- [ ] `run_worker_test.exs` with 10+ tests
- [ ] `cerebros_live_test.exs` with event tests
- [ ] `error_handling_test.exs` with failure scenarios
- [ ] All tests passing
- [ ] Test coverage > 90% for bridge code

## Success Criteria
✅ 10+ integration tests written  
✅ LiveView event handlers tested  
✅ Error scenarios covered  
✅ All tests green  
✅ Code coverage > 90% on bridge  

## Blockers
- ❌ Code from fix-agent not ready → Wait for compilation
- ❌ LiveView changes incomplete → Coordinate with fix-agent
- ❌ Test helpers missing → Use domain_test_helpers.ex

## Communication
**Report When:**
- Bridge tests complete (45 min mark)
- LiveView tests complete (90 min mark)
- Error tests complete (120 min mark)
- All tests passing (final verification)

**Estimated Completion:** 2 hours  
**Status:** 🟡 WAITING ON FIX-AGENT (then deploy)
