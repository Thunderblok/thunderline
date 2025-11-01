defmodule Thunderline.Auth.TokenTest do
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundergate.ActorContext
  alias Thunderline.Thundergate.Resources.Token

  describe "token expiration" do
    test "token expires after configured TTL" do
      now = System.os_time(:second)
      
      ctx = ActorContext.new(%{
        actor_id: "user_123",
        tenant: "org_456",
        scopes: ["read", "write"],
        exp: now + 3600,  # 1 hour from now
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      # Should verify successfully when not expired
      assert {:ok, verified_ctx} = ActorContext.verify(signed_ctx.sig)
      assert verified_ctx.actor_id == "user_123"
    end

    test "rejects expired token" do
      past_time = System.os_time(:second) - 3600  # 1 hour ago
      
      ctx = ActorContext.new(%{
        actor_id: "user_789",
        tenant: "org_123",
        scopes: ["read"],
        exp: past_time,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      # Should fail verification due to expiration
      assert {:error, :expired} = ActorContext.verify(signed_ctx.sig)
    end

    test "token expiration boundary case - exactly at expiration" do
      now = System.os_time(:second)
      
      ctx = ActorContext.new(%{
        actor_id: "user_boundary",
        tenant: "org_boundary",
        scopes: ["admin"],
        exp: now,  # Expires right now
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      # Should be expired (exp <= now)
      assert {:error, :expired} = ActorContext.verify(signed_ctx.sig)
    end

    test "token with future expiration is valid" do
      far_future = System.os_time(:second) + 86400  # 24 hours from now
      
      ctx = ActorContext.new(%{
        actor_id: "user_future",
        tenant: "org_future",
        scopes: ["read", "write", "admin"],
        exp: far_future,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      assert {:ok, verified} = ActorContext.verify(signed_ctx.sig)
      assert verified.exp == far_future
    end
  end

  describe "token refresh logic" do
    test "token can be refreshed before expiration" do
      now = System.os_time(:second)
      
      # Create original token expiring in 1 hour
      original_ctx = ActorContext.new(%{
        actor_id: "user_refresh",
        tenant: "org_refresh",
        scopes: ["read", "write"],
        exp: now + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_original = ActorContext.sign(original_ctx)
      
      # Verify original is valid
      assert {:ok, verified_original} = ActorContext.verify(signed_original.sig)
      
      # Create refreshed token with new expiration
      refreshed_ctx = ActorContext.new(%{
        actor_id: verified_original.actor_id,
        tenant: verified_original.tenant,
        scopes: verified_original.scopes,
        exp: now + 7200,  # 2 hours from now
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_refreshed = ActorContext.sign(refreshed_ctx)
      
      # Both tokens should be valid
      assert {:ok, _} = ActorContext.verify(signed_original.sig)
      assert {:ok, verified_refreshed} = ActorContext.verify(signed_refreshed.sig)
      assert verified_refreshed.exp > verified_original.exp
    end

    test "expired token cannot be refreshed" do
      past_time = System.os_time(:second) - 3600
      
      expired_ctx = ActorContext.new(%{
        actor_id: "user_expired_refresh",
        tenant: "org_expired",
        scopes: ["read"],
        exp: past_time,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_expired = ActorContext.sign(expired_ctx)
      
      # Verify fails on expired token
      assert {:error, :expired} = ActorContext.verify(signed_expired.sig)
      
      # Cannot extract data from expired token to refresh it
      # This is correct behavior - must re-authenticate
    end
  end

  describe "token grace periods" do
    test "no grace period - tokens expire immediately at exp time" do
      now = System.os_time(:second)
      
      ctx = ActorContext.new(%{
        actor_id: "user_nograce",
        tenant: "org_nograce",
        scopes: ["read"],
        exp: now - 1,  # 1 second ago
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      # Should be rejected immediately
      assert {:error, :expired} = ActorContext.verify(signed_ctx.sig)
    end

    test "token validity window behavior" do
      now = System.os_time(:second)
      
      # Token valid for exactly 5 minutes
      valid_ctx = ActorContext.new(%{
        actor_id: "user_window",
        tenant: "org_window",
        scopes: ["read"],
        exp: now + 300,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_valid = ActorContext.sign(valid_ctx)
      
      # Should be valid now
      assert {:ok, _} = ActorContext.verify(signed_valid.sig)
      
      # Create an already-expired token for comparison
      expired_ctx = %{valid_ctx | exp: now - 1}
      signed_expired = ActorContext.sign(expired_ctx)
      
      # Should be expired
      assert {:error, :expired} = ActorContext.verify(signed_expired.sig)
    end
  end

  describe "AshAuthentication token resource integration" do
    test "tokens can be stored in database" do
      # This tests integration with Thunderline.Thundergate.Resources.Token
      # which uses AshAuthentication.TokenResource extension
      
      token_attrs = %{
        jti: Thunderline.UUID.v7(),
        subject: "user_db_123",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        purpose: "access",
        extra_data: %{"scope" => "read"}
      }
      
      # Store token using Ash action
      assert {:ok, token} = 
        Token
        |> Ash.Changeset.for_create(:store_token, %{
          token: "test_token_" <> token_attrs.jti,
          extra_data: token_attrs.extra_data,
          purpose: token_attrs.purpose
        })
        |> Ash.create()
      
      assert token.purpose == "access"
      assert token.extra_data["scope"] == "read"
    end

    test "expired tokens can be queried" do
      # Create expired token
      expired_attrs = %{
        jti: Thunderline.UUID.v7(),
        subject: "user_expired_db",
        expires_at: DateTime.add(DateTime.utc_now(), -3600, :second),  # 1 hour ago
        purpose: "access"
      }
      
      assert {:ok, _token} = 
        Token
        |> Ash.Changeset.for_create(:store_token, %{
          token: "expired_token_" <> expired_attrs.jti,
          purpose: expired_attrs.purpose
        })
        |> Ash.create()
      
      # Query expired tokens
      assert {:ok, expired_tokens} = Token |> Ash.Query.for_read(:expired) |> Ash.read()
      
      # Should find at least the one we just created
      assert Enum.any?(expired_tokens, fn t -> t.subject == expired_attrs.subject end)
    end

    test "tokens can be revoked" do
      jti = Thunderline.UUID.v7()
      subject = "user_revoke_test"
      
      # Store a token
      assert {:ok, token} = 
        Token
        |> Ash.Changeset.for_create(:store_token, %{
          token: "revoke_test_" <> jti,
          purpose: "access"
        })
        |> Ash.create()
      
      # Revoke the token
      assert {:ok, _revocation} = 
        Token
        |> Ash.Changeset.for_create(:revoke_jti, %{
          subject: token.subject,
          jti: token.jti
        })
        |> Ash.create()
      
      # Check if revoked
      assert {:ok, is_revoked} = 
        Token
        |> Ash.ActionInput.for_action(:revoked?, %{jti: token.jti})
        |> Ash.run_action()
      
      assert is_revoked == true
    end
  end

  describe "token signature validation" do
    test "tampered token is rejected" do
      ctx = ActorContext.new(%{
        actor_id: "user_tamper",
        tenant: "org_tamper",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      # Tamper with the signature
      tampered_sig = String.replace(signed_ctx.sig, "A", "B", global: false)
      
      # Should fail verification
      assert {:error, :invalid_signature} = ActorContext.verify(tampered_sig)
    end

    test "token with wrong algorithm is rejected" do
      # Invalid token format
      invalid_token = "invalid.token.format"
      
      # Should fail to decode
      assert {:error, _reason} = ActorContext.verify(invalid_token)
    end

    test "valid signature verification" do
      ctx = ActorContext.new(%{
        actor_id: "user_valid_sig",
        tenant: "org_valid",
        scopes: ["admin"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      # Should verify successfully
      assert {:ok, verified} = ActorContext.verify(signed_ctx.sig)
      assert verified.actor_id == ctx.actor_id
      assert verified.tenant == ctx.tenant
      assert verified.scopes == ctx.scopes
    end
  end

  describe "token scopes and permissions" do
    test "token preserves scope information through sign/verify cycle" do
      scopes = ["read:users", "write:posts", "delete:comments", "admin:system"]
      
      ctx = ActorContext.new(%{
        actor_id: "user_scopes",
        tenant: "org_scopes",
        scopes: scopes,
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      assert {:ok, verified} = ActorContext.verify(signed_ctx.sig)
      assert verified.scopes == scopes
      assert Enum.all?(scopes, &(&1 in verified.scopes))
    end

    test "empty scopes are preserved" do
      ctx = ActorContext.new(%{
        actor_id: "user_noscopes",
        tenant: "org_noscopes",
        scopes: [],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      assert {:ok, verified} = ActorContext.verify(signed_ctx.sig)
      assert verified.scopes == []
    end
  end

  describe "correlation ID tracking" do
    test "correlation ID is preserved across token lifecycle" do
      correlation_id = Thunderline.UUID.v7()
      
      ctx = ActorContext.new(%{
        actor_id: "user_corr",
        tenant: "org_corr",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: correlation_id
      })
      
      signed_ctx = ActorContext.sign(ctx)
      
      assert {:ok, verified} = ActorContext.verify(signed_ctx.sig)
      assert verified.correlation_id == correlation_id
    end

    test "different tokens have different correlation IDs" do
      ctx1 = ActorContext.new(%{
        actor_id: "user_1",
        tenant: "org_1",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      ctx2 = ActorContext.new(%{
        actor_id: "user_2",
        tenant: "org_2",
        scopes: ["read"],
        exp: System.os_time(:second) + 3600,
        correlation_id: Thunderline.UUID.v7()
      })
      
      assert ctx1.correlation_id != ctx2.correlation_id
    end
  end
end
