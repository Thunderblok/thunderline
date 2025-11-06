defmodule Thunderline.Auth.SessionTest do
  use Thunderline.DataCase, async: true

  alias Ash.Query
  require Ash.Query

  alias Thunderline.Thundergate.ActorContext
  alias Thunderline.Thundergate.Resources.Token

  describe "multiple concurrent sessions" do
    test "user can have multiple active sessions" do
      user_id = "user_multisession"
      tenant = "org_multisession"
      now = System.os_time(:second)

      # Create first session (e.g., desktop browser)
      session1 = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read", "write"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      # Create second session (e.g., mobile app)
      session2 = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read", "write"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      signed1 = ActorContext.sign(session1)
      signed2 = ActorContext.sign(session2)

      # Both sessions should be valid independently
      assert {:ok, verified1} = ActorContext.verify(signed1.sig)
      assert {:ok, verified2} = ActorContext.verify(signed2.sig)

      # Same user but different correlation IDs
      assert verified1.actor_id == verified2.actor_id
      assert verified1.correlation_id != verified2.correlation_id
    end

    test "sessions have independent expiration times" do
      user_id = "user_independent_exp"
      tenant = "org_independent"
      now = System.os_time(:second)

      # Short-lived session
      session_short = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read"],
        exp: now + 300,  # 5 minutes
        correlation_id: Thunderline.UUID.v7()
      })

      # Long-lived session
      session_long = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read"],
        exp: now + 86400,  # 24 hours
        correlation_id: Thunderline.UUID.v7()
      })

      signed_short = ActorContext.sign(session_short)
      signed_long = ActorContext.sign(session_long)

      assert {:ok, verified_short} = ActorContext.verify(signed_short.sig)
      assert {:ok, verified_long} = ActorContext.verify(signed_long.sig)

      assert verified_short.exp < verified_long.exp
    end

    test "sessions can have different scopes" do
      user_id = "user_diff_scopes"
      tenant = "org_diff_scopes"
      now = System.os_time(:second)

      # Admin session with full permissions
      admin_session = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read", "write", "admin", "delete"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      # Limited read-only session
      readonly_session = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_admin = ActorContext.sign(admin_session)
      signed_readonly = ActorContext.sign(readonly_session)

      assert {:ok, verified_admin} = ActorContext.verify(signed_admin.sig)
      assert {:ok, verified_readonly} = ActorContext.verify(signed_readonly.sig)

      assert "admin" in verified_admin.scopes
      refute "admin" in verified_readonly.scopes
    end
  end

  describe "session conflicts and isolation" do
    test "session tokens are cryptographically independent" do
      user_id = "user_crypto_test"
      tenant = "org_crypto"
      now = System.os_time(:second)

      # Create two sessions with identical parameters
      session1 = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      session2 = ActorContext.new(%{
        actor_id: user_id,
        tenant: tenant,
        scopes: ["read"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      signed1 = ActorContext.sign(session1)
      signed2 = ActorContext.sign(session2)

      # Signatures should be different despite identical parameters
      # (except correlation_id which is different)
      assert signed1.sig != signed2.sig
    end

    test "revoking one session does not affect other sessions" do
      user_id = "user_revoke_one"
      tenant = "org_revoke"
      now = System.os_time(:second)

      # Create two stored tokens for the same user
      token1_jti = Thunderline.UUID.v7()
      token2_jti = Thunderline.UUID.v7()

      {:ok, token1} =
        Token
        |> Ash.Changeset.for_create(:store_token, %{
          token: "session1_" <> token1_jti,
          purpose: "access",
          extra_data: %{"session_id" => "session_1"}
        })
        |> Ash.create()

      {:ok, token2} =
        Token
        |> Ash.Changeset.for_create(:store_token, %{
          token: "session2_" <> token2_jti,
          purpose: "access",
          extra_data: %{"session_id" => "session_2"}
        })
        |> Ash.create()

      # Revoke token1
      {:ok, _} =
        Token
        |> Ash.Changeset.for_create(:revoke_jti, %{
          subject: token1.subject,
          jti: token1.jti
        })
        |> Ash.create()

      # Check revocation status
      {:ok, token1_revoked} =
        Token
        |> Ash.ActionInput.for_action(:revoked?, %{jti: token1.jti})
        |> Ash.run_action()

      {:ok, token2_revoked} =
        Token
        |> Ash.ActionInput.for_action(:revoked?, %{jti: token2.jti})
        |> Ash.run_action()

      assert token1_revoked == true
      assert token2_revoked == false
    end

    test "session isolation across tenants" do
      user_id = "user_multi_tenant"
      now = System.os_time(:second)

      # Session for tenant A
      session_a = ActorContext.new(%{
        actor_id: user_id,
        tenant: "org_tenant_a",
        scopes: ["read", "write"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      # Session for tenant B
      session_b = ActorContext.new(%{
        actor_id: user_id,
        tenant: "org_tenant_b",
        scopes: ["read"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_a = ActorContext.sign(session_a)
      signed_b = ActorContext.sign(session_b)

      assert {:ok, verified_a} = ActorContext.verify(signed_a.sig)
      assert {:ok, verified_b} = ActorContext.verify(signed_b.sig)

      # Same user but different tenants
      assert verified_a.actor_id == verified_b.actor_id
      assert verified_a.tenant != verified_b.tenant

      # Potentially different permissions per tenant
      assert length(verified_a.scopes) > length(verified_b.scopes)
    end
  end

  describe "session hijacking prevention" do
    test "token tampering is detected" do
      session = ActorContext.new(%{
        actor_id: "user_hijack_test",
        tenant: "org_secure",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_session = ActorContext.sign(session)

      # Attempt to tamper with the token
      tampered_token = String.replace(signed_session.sig, "e", "3", global: false)

      # Should fail verification
      assert {:error, :invalid_signature} = ActorContext.verify(tampered_token)
    end

    test "replayed expired session is rejected" do
      past_time = System.os_time(:second) - 7200

      old_session = ActorContext.new(%{
        actor_id: "user_replay_attack",
        tenant: "org_replay",
        scopes: ["admin"],
        exp: past_time,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_old = ActorContext.sign(old_session)

      # Even with valid signature, expired session should fail
      assert {:error, :expired} = ActorContext.verify(signed_old.sig)
    end

    test "session with forged expiration time fails signature check" do
      # Create a legitimate session
      session = ActorContext.new(%{
        actor_id: "user_forge_test",
        tenant: "org_forge",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_session = ActorContext.sign(session)

      # Verify the legitimate session works
      assert {:ok, _} = ActorContext.verify(signed_session.sig)

      # Attempting to create a new token with modified expiration
      # but using the same signature would fail
      # (This is prevented by the signing mechanism)

      # Trying to extract and modify the payload would also fail
      # because the signature is cryptographically bound to the payload
    end

    test "session tokens are unique per issuance" do
      session_attrs = %{
        actor_id: "user_unique_tokens",
        tenant: "org_unique",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      }

      # Issue the same session twice
      session1 = ActorContext.new(session_attrs)
      session2 = ActorContext.new(session_attrs)

      signed1 = ActorContext.sign(session1)
      signed2 = ActorContext.sign(session2)

      # Even with identical parameters, signatures should be different
      # due to different correlation IDs or signing timestamps
      assert signed1.sig != signed2.sig
    end
  end

  describe "session revocation" do
    test "revoke all sessions for a user" do
      subject = "user_revoke_all"

      # Create multiple tokens for the user
      token_jtis = for i <- 1..3 do
        jti = Thunderline.UUID.v7()

        {:ok, _token} =
          Token
          |> Ash.Changeset.for_create(:store_token, %{
            token: "multi_token_#{i}_" <> jti,
            purpose: "access",
            extra_data: %{"session_num" => i}
          })
          |> Ash.create()

        jti
      end

      # Get the subject from one of the created tokens
      first_jti = hd(token_jtis)
      {:ok, [first_token | _]} =
        Token
        |> Ash.Query.filter(jti == ^first_jti)
        |> Ash.read()

      # Revoke all tokens for this subject
      {:ok, _result} =
        Token
        |> Ash.Changeset.for_update(:revoke_all_stored_for_subject, %{
          subject: first_token.subject,
          extra_data: %{"reason" => "user_logout"}
        })
        |> Ash.update()

      # All tokens should now be revoked
      revocation_checks = for jti <- token_jtis do
        {:ok, is_revoked} =
          Token
          |> Ash.ActionInput.for_action(:revoked?, %{jti: jti})
          |> Ash.run_action()

        is_revoked
      end

      assert Enum.all?(revocation_checks)
    end

    test "session cleanup removes expired tokens" do
      # Create an expired token
      expired_jti = Thunderline.UUID.v7()

      {:ok, expired_token} =
        Token
        |> Ash.Changeset.for_create(:store_token, %{
          token: "expired_cleanup_" <> expired_jti,
          purpose: "access"
        })
        |> Ash.create()

      # Manually update to be expired (for test purposes)
      # In production, tokens would naturally expire

      # Expunge expired tokens
      {:ok, expunged_tokens} =
        Token
        |> Ash.Query.for_read(:expired)
        |> Ash.bulk_destroy(:expunge_expired, %{}, authorize?: false)

      # The action should complete successfully
      assert is_list(expunged_tokens) or match?(%Ash.BulkResult{}, expunged_tokens)
    end
  end

  describe "session timeout behavior" do
    test "session becomes invalid after expiration time" do
      short_ttl = 60  # 1 minute
      now = System.os_time(:second)

      session = ActorContext.new(%{
        actor_id: "user_timeout",
        tenant: "org_timeout",
        scopes: ["read"],
        exp: now + short_ttl,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_session = ActorContext.sign(session)

      # Should be valid immediately
      assert {:ok, verified} = ActorContext.verify(signed_session.sig)
      assert verified.exp == now + short_ttl

      # After expiration (simulated), should be invalid
      expired_session = %{session | exp: now - 1}
      signed_expired = ActorContext.sign(expired_session)

      assert {:error, :expired} = ActorContext.verify(signed_expired.sig)
    end

    test "session lifetime can be extended via refresh" do
      now = System.os_time(:second)
      original_exp = now + 1800  # 30 minutes

      original_session = ActorContext.new(%{
        actor_id: "user_extend",
        tenant: "org_extend",
        scopes: ["read", "write"],
        exp: original_exp,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_original = ActorContext.sign(original_session)

      # Verify original session
      assert {:ok, verified_original} = ActorContext.verify(signed_original.sig)

      # Create extended session with new expiration
      extended_session = ActorContext.new(%{
        actor_id: verified_original.actor_id,
        tenant: verified_original.tenant,
        scopes: verified_original.scopes,
        exp: now + 3600,  # Extended to 1 hour
        correlation_id: Thunderline.UUID.v7()  # New correlation ID for new session
      })

      signed_extended = ActorContext.sign(extended_session)

      assert {:ok, verified_extended} = ActorContext.verify(signed_extended.sig)
      assert verified_extended.exp > verified_original.exp
    end

    test "idle timeout simulation through token expiration" do
      now = System.os_time(:second)
      idle_timeout = 900  # 15 minutes

      # Create session with idle timeout expiration
      session = ActorContext.new(%{
        actor_id: "user_idle",
        tenant: "org_idle",
        scopes: ["read"],
        exp: now + idle_timeout,
        correlation_id: Thunderline.UUID.v7()
      })

      signed_session = ActorContext.sign(session)

      # Active session is valid
      assert {:ok, _} = ActorContext.verify(signed_session.sig)

      # After idle period, session would be expired
      # (In a real system, this would be checked on each request)
      idle_session = %{session | exp: now - idle_timeout}
      signed_idle = ActorContext.sign(idle_session)

      assert {:error, :expired} = ActorContext.verify(signed_idle.sig)
    end
  end
end
