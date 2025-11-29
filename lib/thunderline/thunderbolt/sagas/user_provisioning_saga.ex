defmodule Thunderline.Thunderbolt.Sagas.UserProvisioningSaga do
  @moduledoc """
  Reactor saga for complete user onboarding flow.

  This saga orchestrates the entire user provisioning workflow across multiple
  domains (ThunderGate → ThunderBlock → ThunderLink) with proper compensation.

  ## Workflow Steps

  1. **Validate Email** - Check email format and domain validity
  2. **Generate Magic Link Token** - Create secure authentication token
  3. **Send Magic Link Email** - Dispatch email via configured sender
  4. **Await Token Verification** - Wait for user to click link (handled externally)
  5. **Create User** - Persist user record in ThunderGate
  6. **Provision Vault** - Create user's memory/knowledge vault in ThunderBlock
  7. **Create Default Community** - Bootstrap initial community membership
  8. **Emit Onboarding Complete Event** - Publish to EventBus

  ## Compensation Strategy

  If any step fails after user creation, the saga will:
  - Delete the created user record
  - Deprovision any allocated vault space
  - Remove community memberships
  - Log compensation telemetry

  ## Usage

      alias Thunderline.Thunderbolt.Sagas.UserProvisioningSaga

      inputs = %{
        email: "user@example.com",
        correlation_id: Thunderline.UUID.v7(),
        magic_link_redirect: "/communities"
      }

      case Reactor.run(UserProvisioningSaga, inputs) do
        {:ok, %{user: user, vault: vault}} ->
          {:ok, user}

        {:error, reason} ->
          Logger.error("User provisioning failed: \#{inspect(reason)}")
          {:error, :provisioning_failed}
      end
  """

  use Reactor, extensions: [Reactor.Dsl]

  require Logger
  alias Thunderline.Thunderbolt.Sagas.Base
  alias Thunderline.Thundergate.Resources.User

  middlewares do
    middleware Thunderline.Thunderbolt.Sagas.TelemetryMiddleware
    middleware Reactor.Middleware.Telemetry
  end
  alias Thunderline.Thunderblock.Resources.VaultUser

  # Emit telemetry for all steps (start/stop events)
  middlewares do
    middleware Reactor.Middleware.Telemetry
  end

  input :email

  input :correlation_id do
    transform fn value ->
      case value do
        nil -> Thunderline.UUID.v7()
        "" -> Thunderline.UUID.v7()
        v when is_binary(v) -> v
        _ -> Thunderline.UUID.v7()
      end
    end
  end

  input :causation_id
  input :magic_link_redirect

  step :emit_saga_start do
    argument :correlation_id, input(:correlation_id)
    argument :causation_id, input(:causation_id)

    run fn args, _context ->
      # correlation_id is already transformed/defaulted from input
      actual_correlation_id = args.correlation_id

      # Emit the telemetry event that tests are waiting for
      metadata = %{
        saga: "Elixir.Thunderline.Thunderbolt.Sagas.UserProvisioningSaga",
        correlation_id: actual_correlation_id,
        causation_id: args.causation_id,
        step: "emit_saga_start"
      }

      :telemetry.execute([:reactor, :saga, :start], %{count: 1}, metadata)
      Logger.info("UserProvisioningSaga started [#{actual_correlation_id}]")

      {:ok, %{correlation_id: actual_correlation_id}}
    end
  end

  step :validate_email do
    argument :email, input(:email)

    run fn %{email: email}, _ ->
      case validate_email_format(email) do
        :ok -> {:ok, email}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  step :generate_token do
    argument :email, result(:validate_email)
    argument :correlation_id, result(:emit_saga_start, [:correlation_id])

    run fn %{email: email, correlation_id: correlation_id}, _ ->
      token = Thunderline.UUID.v7()
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok,
       %{
         token: token,
         email: email,
         expires_at: expires_at,
         correlation_id: correlation_id
       }}
    end
  end

  step :send_magic_link do
    argument :token_data, result(:generate_token)
    argument :redirect_path, input(:magic_link_redirect)

    run fn %{token_data: token_data, redirect_path: redirect}, _ ->
      # Delegate to ThunderGate's MagicLinkSender
      case Thunderline.Thundergate.Authentication.MagicLinkSender.send_magic_link(
             token_data.email,
             token_data.token,
             redirect
           ) do
        {:ok, _result} ->
          Logger.info("Magic link sent to #{token_data.email}")
          {:ok, token_data}

        {:error, reason} ->
          Logger.error("Failed to send magic link: #{inspect(reason)}")
          {:error, {:magic_link_send_failed, reason}}
      end
    end

    # No compensation needed - email already sent, can't "unsend"
  end

  step :create_user do
    argument :token_data, result(:send_magic_link)

    run fn %{token_data: token_data}, _ ->
      # Create user via Ash action
      user_attrs = %{
        email: token_data.email,
        hashed_password: nil,
        # Will be set when user completes onboarding
        created_via: :magic_link,
        correlation_id: token_data.correlation_id
      }

      case Ash.create(User, user_attrs) do
        {:ok, user} ->
          Logger.info("User created: #{user.id}")
          {:ok, user}

        {:error, reason} ->
          Logger.error("User creation failed: #{inspect(reason)}")
          {:error, {:user_creation_failed, reason}}
      end
    end

    compensate fn user, _ ->
      Logger.warning("Compensating: deleting user #{user.id}")

      case Ash.destroy(user) do
        :ok -> {:ok, :compensated}
        {:error, reason} -> {:error, {:compensation_failed, reason}}
      end
    end
  end

  step :provision_vault do
    argument :user, result(:create_user)

    run fn %{user: user}, _ ->
      vault_attrs = %{
        user_id: user.id,
        capacity_bytes: 1_073_741_824,
        # 1 GB default
        storage_tier: :standard,
        encryption_enabled: true
      }

      case Ash.create(VaultUser, vault_attrs) do
        {:ok, vault} ->
          Logger.info("Vault provisioned for user #{user.id}")
          {:ok, vault}

        {:error, reason} ->
          Logger.error("Vault provisioning failed: #{inspect(reason)}")
          {:error, {:vault_provisioning_failed, reason}}
      end
    end

    compensate fn vault, _ ->
      Logger.warning("Compensating: deprovisioning vault #{vault.id}")

      case Ash.destroy(vault) do
        :ok -> {:ok, :compensated}
        {:error, reason} -> {:error, {:compensation_failed, reason}}
      end
    end
  end

  step :create_default_community do
    argument :user, result(:create_user)

    run fn %{user: user}, context ->
      # Wire to ThunderLink community creation if available
      case create_community_membership(user, context) do
        {:ok, membership} ->
          Logger.info("Default community membership created for user #{user.id}")
          {:ok, membership}

        {:error, reason} ->
          Logger.warning("Community creation failed: #{inspect(reason)}, using stub")
          # Return stub on failure - community can be created later
          {:ok, %{community_id: Thunderline.UUID.v7(), user_id: user.id, stub: true}}
      end
    end

    compensate fn membership, _context ->
      # Remove community membership if it was actually created
      if Map.get(membership, :stub) do
        {:ok, :no_compensation_needed}
      else
        Logger.warning("Compensating: removing community membership #{membership.community_id}")
        remove_community_membership(membership)
      end
    end
  end

  step :emit_onboarding_event do
    argument :user, result(:create_user)
    argument :vault, result(:provision_vault)
    argument :correlation_id, result(:emit_saga_start, [:correlation_id])
    argument :causation_id, input(:causation_id)

    run fn %{user: user, vault: vault, correlation_id: correlation_id, causation_id: causation_id},
           _ ->
      event_attrs = %{
        name: "user.onboarding.complete",
        type: :user_lifecycle,
        domain: :gate,
        source: "UserProvisioningSaga",
        correlation_id: correlation_id,
        causation_id: causation_id,
        payload: %{
          user_id: user.id,
          email: user.email,
          vault_id: vault.id
        },
        meta: %{
          pipeline: :cross_domain
        }
      }

      case Thunderline.Event.new(event_attrs) do
        {:ok, event} ->
          Thunderline.Thunderflow.EventBus.publish_event(event)
          {:ok, %{user: user, vault: vault}}

        {:error, reason} ->
          # Event emission failure shouldn't block the saga
          Logger.warning("Failed to emit onboarding event: #{inspect(reason)}")
          {:ok, %{user: user, vault: vault}}
      end
    end
  end

  return :emit_onboarding_event

  # Private helpers

  defp validate_email_format(email) when is_binary(email) do
    if String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
      :ok
    else
      {:error, :invalid_email_format}
    end
  end

  defp validate_email_format(_), do: {:error, :invalid_email_format}

  defp create_community_membership(user, context) do
    # Check if ThunderLink is available and create membership
    if Code.ensure_loaded?(Thunderline.Thunderlink.Resources.CommunityMember) do
      # Get or create default community
      default_community_id = get_default_community_id()

      Ash.create(Thunderline.Thunderlink.Resources.CommunityMember, %{
        user_id: user.id,
        community_id: default_community_id,
        role: :member,
        joined_at: DateTime.utc_now()
      })
    else
      # ThunderLink not available
      {:error, :thunderlink_unavailable}
    end
  rescue
    _ -> {:error, :community_creation_failed}
  end

  defp remove_community_membership(membership) do
    if Code.ensure_loaded?(Thunderline.Thunderlink.Resources.CommunityMember) do
      case Ash.get(Thunderline.Thunderlink.Resources.CommunityMember, membership.id) do
        {:ok, member} ->
          Ash.destroy(member)
          {:ok, :compensated}

        {:error, %Ash.Error.Query.NotFound{}} ->
          {:ok, :already_removed}

        {:error, reason} ->
          {:error, {:compensation_failed, reason}}
      end
    else
      {:ok, :thunderlink_unavailable}
    end
  rescue
    _ -> {:ok, :compensation_error_ignored}
  end

  defp get_default_community_id do
    # Return a well-known default community ID
    # In production, this would query for the system default community
    Application.get_env(:thunderline, :default_community_id, Thunderline.UUID.v7())
  end
end
