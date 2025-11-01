# 🎫 Session Agent Deployment Plan

**Agent ID:** `session-agent`  
**Epic:** 3.2 Authentication & Authorization Hardening  
**Priority:** 🟡 HIGH (Priority 2)  
**Duration:** 2 hours  
**Can Run Parallel With:** security-agent, event-test-agent  

## Mission
Test token management, session handling, and refresh flows.

## Tasks

### Task 1: Token Expiration Tests (45 min)

**File:** `test/thunderline/auth/token_expiration_test.exs`

```elixir
defmodule Thunderline.Auth.TokenExpirationTest do
  use Thunderline.DataCase
  alias Thunderline.Auth.Tokens

  describe "token expiration" do
    test "valid token allows access" do
      user = create_user()
      token = Tokens.generate_token(user)
      
      assert {:ok, _user} = Tokens.verify_token(token)
    end

    test "expired token rejected" do
      user = create_user()
      token = Tokens.generate_token(user, expires_in: -3600) # Expired
      
      assert {:error, :expired} = Tokens.verify_token(token)
    end

    test "token expiration uses configured lifetime" do
      # Test config value is respected
    end
  end

  describe "token refresh" do
    test "valid refresh token generates new access token" do
      user = create_user()
      refresh_token = Tokens.generate_refresh_token(user)
      
      assert {:ok, new_access_token} = Tokens.refresh(refresh_token)
      assert {:ok, _user} = Tokens.verify_token(new_access_token)
    end

    test "expired refresh token rejected" do
      user = create_user()
      expired_refresh = Tokens.generate_refresh_token(user, expires_in: -3600)
      
      assert {:error, :expired} = Tokens.refresh(expired_refresh)
    end

    test "refresh token rotation" do
      # Test that refresh creates new refresh token
    end
  end
end
```

---

### Task 2: Concurrent Session Tests (45 min)

**File:** `test/thunderline/auth/concurrent_sessions_test.exs`

```elixir
defmodule Thunderline.Auth.ConcurrentSessionsTest do
  use Thunderline.DataCase
  alias Thunderline.Auth.Sessions

  describe "multiple active sessions" do
    test "user can have multiple sessions" do
      user = create_user()
      
      session1 = Sessions.create_session(user, device: "browser")
      session2 = Sessions.create_session(user, device: "mobile")
      
      assert session1.id != session2.id
      assert Sessions.active_sessions(user) |> length() == 2
    end

    test "logout one session keeps others active" do
      user = create_user()
      session1 = Sessions.create_session(user)
      session2 = Sessions.create_session(user)
      
      Sessions.logout(session1.id)
      
      assert Sessions.active?(session1.id) == false
      assert Sessions.active?(session2.id) == true
    end

    test "logout all sessions works" do
      user = create_user()
      _session1 = Sessions.create_session(user)
      _session2 = Sessions.create_session(user)
      
      Sessions.logout_all(user)
      
      assert Sessions.active_sessions(user) == []
    end
  end

  describe "session limits" do
    test "enforces max sessions per user" do
      # If you have session limits configured
    end
  end
end
```

---

### Task 3: Session Security Tests (30 min)

**File:** `test/thunderline/auth/session_security_test.exs`

```elixir
defmodule Thunderline.Auth.SessionSecurityTest do
  use Thunderline.DataCase

  describe "session hijacking prevention" do
    test "session tied to IP address" do
      # If you track IP
      user = create_user()
      session = Sessions.create_session(user, ip: "192.168.1.1")
      
      assert {:error, :ip_mismatch} = 
        Sessions.verify(session.id, ip: "10.0.0.1")
    end

    test "session tied to user agent" do
      # If you track user agent
    end

    test "session timeout after inactivity" do
      user = create_user()
      session = Sessions.create_session(user, last_active: hours_ago(2))
      
      assert Sessions.active?(session.id) == false
    end
  end

  describe "token security" do
    test "tokens are cryptographically signed" do
      # Verify signature validation
    end

    test "tampered tokens rejected" do
      user = create_user()
      token = Tokens.generate_token(user)
      tampered = String.replace(token, "a", "b", global: false)
      
      assert {:error, :invalid_signature} = Tokens.verify_token(tampered)
    end
  end
end
```

---

### Task 4: Documentation (10 min)

**File:** `docs/SESSION_SECURITY_MODEL.md`

```markdown
# Session Security Model

## Token Types
1. **Access Token**: Short-lived (1 hour), for API requests
2. **Refresh Token**: Long-lived (30 days), to get new access tokens

## Token Lifecycle
1. User logs in → Receives access + refresh tokens
2. Access token expires → Use refresh to get new access token
3. Refresh token expires → User must re-authenticate

## Session Management
- Sessions tracked in database
- Multiple concurrent sessions allowed
- Sessions can be revoked individually or all at once

## Security Features
- Tokens cryptographically signed
- IP address tracking (optional)
- User agent tracking (optional)
- Inactivity timeout
- Token rotation on refresh

## Testing
All flows tested in:
- `test/thunderline/auth/token_expiration_test.exs`
- `test/thunderline/auth/concurrent_sessions_test.exs`
- `test/thunderline/auth/session_security_test.exs`
```

---

## Deliverables

- [ ] Token expiration tests (6+ test cases)
- [ ] Concurrent session tests (5+ test cases)
- [ ] Session security tests (4+ test cases)
- [ ] Session security model documented
- [ ] All tests passing

## Success Criteria
✅ Token lifecycle fully tested  
✅ Refresh flow validated  
✅ Concurrent sessions work  
✅ Security measures verified  
✅ Documentation complete  

## Blockers
- ❌ Token implementation incomplete → Coordinate with auth team
- ❌ Session tracking not implemented → Test what exists, note gaps
- ❌ Config values unclear → Document assumptions

## Communication
**Report When:**
- Token tests complete (45 min mark)
- Session tests complete (90 min mark)
- Security tests complete (120 min mark)
- All verified (final check)

**Estimated Completion:** 2 hours  
**Status:** 🟢 READY TO DEPLOY
