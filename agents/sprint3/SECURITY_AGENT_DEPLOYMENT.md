# 🔒 Security Agent Deployment Plan

**Agent ID:** `security-agent`  
**Epic:** 3.2 Authentication & Authorization Hardening  
**Priority:** 🔴 CRITICAL (Priority 1)  
**Duration:** 3 hours  
**Can Run Parallel With:** session-agent, event-test-agent  

## Mission
Audit Ash policies and write comprehensive authorization tests.

## Tasks

### Task 1: Policy Audit Across All Domains (60 min)

**Scan all resources in:**
- `lib/thunderline/thunderblock/**/*.ex`
- `lib/thunderline/thunderbolt/**/*.ex`
- `lib/thunderline/thundercrown/**/*.ex`
- `lib/thunderline/thundergate/**/*.ex`
- `lib/thunderline/thundergrid/**/*.ex`
- `lib/thunderline/thunderlink/**/*.ex`
- `lib/thunderline/thunderflow/**/*.ex`

**Check each resource for:**
```elixir
use Ash.Resource,
  authorizers: [Ash.Policy.Authorizer]  # ✅ Good

policies do
  # Policies defined
end
```

**Create:** `docs/POLICY_AUDIT_REPORT.md`

**Format:**
```markdown
# Policy Audit Report

## Resources WITH Policies (✅)
- Thunderline.Thunderblock.User - 5 policies
- Thunderline.Thunderblock.Post - 3 policies

## Resources WITHOUT Policies (❌)
- Thunderline.Thunderbolt.Config - NEEDS POLICIES
- Thunderline.Thundercrown.Dashboard - NEEDS POLICIES

## Policy Gaps Found
1. User resource: No policy for :list action
2. Post resource: Missing field policies for sensitive data

## Recommendations
[Specific fixes needed]
```

---

### Task 2: Write Authorization Tests (90 min)

**For EACH critical resource, create tests:**

**File:** `test/thunderline/thunderblock/user_authorization_test.exs`

```elixir
defmodule Thunderline.Thunderblock.UserAuthorizationTest do
  use Thunderline.DataCase
  alias Thunderline.Thunderblock.User

  describe "create action authorization" do
    test "allows authenticated user to create" do
      actor = create_user()
      assert {:ok, _user} = User.create(%{email: "test@example.com"}, actor: actor)
    end

    test "forbids unauthenticated user" do
      assert {:error, %Ash.Error.Forbidden{}} = 
        User.create(%{email: "test@example.com"}, actor: nil)
    end
  end

  describe "read action authorization" do
    test "user can read own data" do
      user = create_user()
      assert {:ok, _} = User.read(user.id, actor: user)
    end

    test "user cannot read other user's data" do
      user1 = create_user()
      user2 = create_user()
      assert {:error, %Ash.Error.Forbidden{}} = User.read(user2.id, actor: user1)
    end

    test "admin can read all users" do
      admin = create_admin()
      user = create_user()
      assert {:ok, _} = User.read(user.id, actor: admin)
    end
  end

  describe "update action authorization" do
    # Similar pattern
  end

  describe "destroy action authorization" do
    # Similar pattern
  end
end
```

**Write tests for:**
- User (create, read, update, destroy)
- Post (all actions)
- Comment (all actions)
- Any custom actions

**Target:** 20+ authorization tests total

---

### Task 3: Test Edge Cases (30 min)

**File:** `test/authorization_edge_cases_test.exs`

```elixir
defmodule AuthorizationEdgeCasesTest do
  use Thunderline.DataCase

  test "nil actor forbidden for protected resources" do
    assert {:error, %Ash.Error.Forbidden{}} = 
      User.create(%{email: "test@example.com"}, actor: nil)
  end

  test "wrong tenant isolation" do
    user = create_user(tenant: "tenant1")
    resource = create_resource(tenant: "tenant2")
    
    assert {:error, %Ash.Error.Forbidden{}} = 
      Resource.read(resource.id, actor: user, tenant: "tenant1")
  end

  test "expired token rejected" do
    user = create_user_with_expired_token()
    assert {:error, %Ash.Error.Forbidden{}} = 
      User.read(user.id, actor: user)
  end

  test "soft-deleted resources hidden" do
    user = create_deleted_user()
    assert {:error, %Ash.Error.NotFound{}} = User.read(user.id)
  end
end
```

---

## Deliverables

- [ ] `POLICY_AUDIT_REPORT.md` with findings
- [ ] 20+ authorization tests across domains
- [ ] Edge case tests covering:
  - Nil actor scenarios
  - Tenant isolation
  - Token expiration
  - Soft deletes
- [ ] All tests passing
- [ ] Policy gaps documented

## Success Criteria
✅ All resources audited  
✅ Policy gaps identified  
✅ 20+ authorization tests written  
✅ Edge cases covered  
✅ All tests green  
✅ Report actionable  

## Blockers
- ❌ Resources without policies → Document for fixing
- ❌ Complex policies hard to test → Break down into scenarios
- ❌ Missing test helpers → Create auth test helpers

## Communication
**Report When:**
- Audit complete (60 min mark)
- Core tests written (150 min mark)
- Edge cases covered (180 min mark)
- All verified (final check)

**Estimated Completion:** 3 hours  
**Status:** 🟢 READY TO DEPLOY
