# Thunderline Test Patterns

## 📘 Purpose
This document defines the testing foundations, shared helpers, and naming patterns across all Thunderline domains. The objective is to make tests consistent, expressive, and easy to maintain as the codebase evolves.

---

## 📁 Directory Structure

```
test/
│
├── support/                    # Shared helpers and setup modules
│   ├── conn_case.ex            # Phoenix connection test setup
│   ├── data_case.ex            # Repository & database setup for tests
│   ├── domain_test_helpers.ex  # Shared helpers across all domains
│
├── thunderline/                # Core domain-level tests
│   ├── feature_test.exs
│   ├── event_property_test.exs
│   └── integration/
│       ├── cross_domain_trace_test.exs
│       └── event_ledger_test.exs
│
└── thunderline_web/            # Web layer (LiveView & controller)
    ├── controllers/
    └── live/
```

Each test mirrors the related application module path.  
Integration tests live under `test/thunderline/integration/`.

---

## 🧩 Test Types and Cases

### `ConnCase`
Used for controller and request tests that depend on the Phoenix connection layer.  
Located in `test/support/conn_case.ex`.

### `DataCase`
Used for repository tests that rely on database state setup through Ecto.  
Found in `test/support/data_case.ex`.

### `LiveViewTest`
Used to verify interactive UIs in Phoenix LiveView.  
Test IDs in templates must match `element(view, "#id")` in tests.

### Example usage
```elixir
describe "user login" do
  test "renders login form", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Sign in"
  end
end
```

---

## 🧱 Coding Standards and Assertions

- **Avoid side effects**: Use helpers and isolated test data.
- **Use factories**: All seed data must come from helpers like `create_test_user/1`.
- **Prefer pattern assertions**:
  ```elixir
  assert %{email: "user@example.com"} = create_test_user()
  ```
- **Check event results** via `assert_event_published/2` for emitted test signals.
- **Avoid flakey waiting**: use synchronous test APIs or simulated event hooks.

---

## 🧠 Test Documentation and Clarity

- Each test file starts with a module docstring explaining purpose and coverage area.
- Use `@tag` annotations to group tests (`@tag :integration` etc.).
- Avoid raw IO or manual sleeps—prefer process monitoring or message assertions.

---

## 🧪 CI Coverage & Metrics

- All new modules must have ≥90% coverage.
- Tests must run deterministically and without network dependencies.
- The `mix test` suite must pass without external service startup.
- Long-running integration tests should be annotated `@tag :slow`.
- Use `mix test --only slow` to isolate heavier coverage runs.

---

## ✅ Best Practices Summary

- Use `DomainTestHelpers` for consistent factory data
- Avoid state bleed between cases
- Factor setup logic into `setup` blocks or helpers
- Tests belong closest to the component under test
- Work with async: true unless DB access is required
- Ensure reproducibility — rerun `mix test` yields same results each time

---

**Maintainers:** Rookie Team Sprint 2  
**Scope:** Epic 4 - Test Infrastructure Setup  
**Last Updated:** October 2025