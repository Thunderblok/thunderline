defmodule Thunderline.Thundercrown.Policies.UPMPolicyTest do
  @moduledoc """
  Comprehensive test suite for UPM policy authorization.
  
  Tests all policy decision paths including:
  - Admin bypass for all modes
  - Shadow mode (always allow)
  - Canary mode (tenant validation)
  - Active mode (shadow duration validation)
  - Edge cases and error conditions
  """
  use Thunderline.DataCase, async: true

  alias Thunderline.Thundercrown.Policies.UPMPolicy

  @moduletag :upm_policy

  setup do
    # Setup test actors
    admin_actor = %{role: :system, id: "admin-1"}
    upm_admin_actor = %{role: :upm_admin, id: "upm-admin-1"}
    system_admin_actor = %{role: :system_admin, id: "sys-admin-1"}
    user_actor = %{role: :user, id: "user-1"}

    # Setup test tenants
    canary_tenant = %{id: "canary-tenant-1"}
    regular_tenant = %{id: "regular-tenant-1"}

    # Setup test snapshots
    shadow_snapshot = %{
      id: "snap-shadow",
      mode: :shadow,
      activated_at: nil
    }

    canary_snapshot = %{
      id: "snap-canary",
      mode: :canary,
      activated_at: DateTime.utc_now()
    }

    # Active snapshot with valid shadow duration (400 hours = 16.7 days)
    active_snapshot_valid = %{
      id: "snap-active-valid",
      mode: :active,
      activated_at: DateTime.add(DateTime.utc_now(), -400, :hour)
    }

    # Active snapshot with invalid shadow duration (only 100 hours)
    active_snapshot_invalid = %{
      id: "snap-active-invalid",
      mode: :active,
      activated_at: DateTime.add(DateTime.utc_now(), -100, :hour)
    }

    %{
      admin: admin_actor,
      upm_admin: upm_admin_actor,
      system_admin: system_admin_actor,
      user: user_actor,
      canary_tenant: canary_tenant,
      regular_tenant: regular_tenant,
      shadow: shadow_snapshot,
      canary: canary_snapshot,
      active_valid: active_snapshot_valid,
      active_invalid: active_snapshot_invalid
    }
  end

  # ============================================================================
  # Admin Bypass Tests
  # ============================================================================

  describe "can_activate_snapshot?/3 - admin bypass" do
    test "allows system admin to activate shadow snapshot", %{admin: admin, shadow: shadow} do
      assert :ok = UPMPolicy.can_activate_snapshot?(admin, shadow, nil)
    end

    test "allows system admin to activate canary snapshot", %{admin: admin, canary: canary} do
      assert :ok = UPMPolicy.can_activate_snapshot?(admin, canary, nil)
    end

    test "allows system admin to activate active snapshot", %{
      admin: admin,
      active_valid: active
    } do
      assert :ok = UPMPolicy.can_activate_snapshot?(admin, active, nil)
    end

    test "allows system admin to activate invalid active snapshot", %{
      admin: admin,
      active_invalid: active
    } do
      # Admin can bypass even insufficient shadow duration
      assert :ok = UPMPolicy.can_activate_snapshot?(admin, active, nil)
    end

    test "allows upm_admin role to activate any snapshot", %{
      upm_admin: upm_admin,
      shadow: shadow
    } do
      assert :ok = UPMPolicy.can_activate_snapshot?(upm_admin, shadow, nil)
    end

    test "allows system_admin role to activate any snapshot", %{
      system_admin: system_admin,
      canary: canary
    } do
      assert :ok = UPMPolicy.can_activate_snapshot?(system_admin, canary, nil)
    end
  end

  # ============================================================================
  # Shadow Mode Tests
  # ============================================================================

  describe "can_activate_snapshot?/3 - shadow mode" do
    test "allows shadow mode for regular user", %{user: user, shadow: shadow} do
      assert :ok = UPMPolicy.can_activate_snapshot?(user, shadow, nil)
    end

    test "allows shadow mode with nil actor", %{shadow: shadow} do
      assert :ok = UPMPolicy.can_activate_snapshot?(nil, shadow, nil)
    end

    test "allows shadow mode with any tenant", %{
      user: user,
      shadow: shadow,
      regular_tenant: tenant
    } do
      assert :ok = UPMPolicy.can_activate_snapshot?(user, shadow, tenant)
    end

    test "allows shadow mode with empty actor map", %{shadow: shadow} do
      assert :ok = UPMPolicy.can_activate_snapshot?(%{}, shadow, nil)
    end
  end

  # ============================================================================
  # Canary Mode Tests
  # ============================================================================

  describe "can_activate_snapshot?/3 - canary mode" do
    setup do
      # Configure canary tenants for these tests
      Application.put_env(:thunderline, :upm_policies,
        canary_tenants: ["canary-tenant-1", "canary-tenant-2"]
      )

      on_exit(fn ->
        Application.delete_env(:thunderline, :upm_policies)
      end)

      :ok
    end

    test "allows canary mode for configured tenant", %{
      user: user,
      canary: canary,
      canary_tenant: tenant
    } do
      assert :ok = UPMPolicy.can_activate_snapshot?(user, canary, tenant)
    end

    test "denies canary mode for non-canary tenant", %{
      user: user,
      canary: canary,
      regular_tenant: tenant
    } do
      assert {:error, :not_in_canary_rollout} =
               UPMPolicy.can_activate_snapshot?(user, canary, tenant)
    end

    test "denies canary mode with nil tenant", %{user: user, canary: canary} do
      assert {:error, :tenant_required_for_canary} =
               UPMPolicy.can_activate_snapshot?(user, canary, nil)
    end

    test "denies canary mode when tenant id is missing", %{user: user, canary: canary} do
      # Tenant map without id field
      tenant_no_id = %{name: "Some Tenant"}

      assert {:error, :tenant_id_required_for_canary} =
               UPMPolicy.can_activate_snapshot?(user, canary, tenant_no_id)
    end

    test "handles tenant as map with string id", %{user: user, canary: canary} do
      tenant_string_id = %{id: "canary-tenant-1"}

      assert :ok = UPMPolicy.can_activate_snapshot?(user, canary, tenant_string_id)
    end
  end

  describe "can_activate_snapshot?/3 - canary mode with empty canary list" do
    setup do
      # Configure empty canary list
      Application.put_env(:thunderline, :upm_policies, canary_tenants: [])

      on_exit(fn ->
        Application.delete_env(:thunderline, :upm_policies)
      end)

      :ok
    end

    test "denies canary mode when no tenants configured", %{
      user: user,
      canary: canary,
      canary_tenant: tenant
    } do
      assert {:error, :not_in_canary_rollout} =
               UPMPolicy.can_activate_snapshot?(user, canary, tenant)
    end
  end

  # ============================================================================
  # Active Mode Tests
  # ============================================================================

  describe "can_activate_snapshot?/3 - active mode" do
    test "allows active mode after shadow validation period", %{
      user: user,
      active_valid: active
    } do
      assert :ok = UPMPolicy.can_activate_snapshot?(user, active, nil)
    end

    test "denies active mode before shadow validation complete", %{
      user: user,
      active_invalid: active
    } do
      assert {:error, {:insufficient_shadow_duration, 336, actual}} =
               UPMPolicy.can_activate_snapshot?(user, active, nil)

      # Should be around 100 hours
      assert actual >= 90 and actual <= 110
    end

    test "denies active mode with nil activated_at", %{user: user} do
      snapshot = %{id: "snap-1", mode: :active, activated_at: nil}

      assert {:error, :no_shadow_activation_timestamp} =
               UPMPolicy.can_activate_snapshot?(user, snapshot, nil)
    end

    test "allows active mode exactly at minimum duration", %{user: user} do
      # Exactly 336 hours ago
      snapshot = %{
        id: "snap-1",
        mode: :active,
        activated_at: DateTime.add(DateTime.utc_now(), -336, :hour)
      }

      assert :ok = UPMPolicy.can_activate_snapshot?(user, snapshot, nil)
    end

    test "denies active mode one hour short of minimum", %{user: user} do
      # 335 hours ago (one hour short)
      snapshot = %{
        id: "snap-1",
        mode: :active,
        activated_at: DateTime.add(DateTime.utc_now(), -335, :hour)
      }

      assert {:error, {:insufficient_shadow_duration, 336, actual}} =
               UPMPolicy.can_activate_snapshot?(user, snapshot, nil)

      assert actual >= 334 and actual <= 336
    end
  end

  describe "can_activate_snapshot?/3 - active mode with custom min_shadow_hours" do
    setup do
      # Set custom minimum shadow hours (100 hours)
      Application.put_env(:thunderline, :upm_policies, min_shadow_hours: 100)

      on_exit(fn ->
        Application.delete_env(:thunderline, :upm_policies)
      end)

      :ok
    end

    test "uses configured min_shadow_hours", %{user: user} do
      # 150 hours ago (exceeds 100 hour minimum)
      snapshot = %{
        id: "snap-1",
        mode: :active,
        activated_at: DateTime.add(DateTime.utc_now(), -150, :hour)
      }

      assert :ok = UPMPolicy.can_activate_snapshot?(user, snapshot, nil)
    end

    test "denies when below custom minimum", %{user: user} do
      # 50 hours ago (below 100 hour minimum)
      snapshot = %{
        id: "snap-1",
        mode: :active,
        activated_at: DateTime.add(DateTime.utc_now(), -50, :hour)
      }

      assert {:error, {:insufficient_shadow_duration, 100, actual}} =
               UPMPolicy.can_activate_snapshot?(user, snapshot, nil)

      assert actual >= 45 and actual <= 55
    end
  end

  # ============================================================================
  # Invalid Mode Tests
  # ============================================================================

  describe "can_activate_snapshot?/3 - invalid mode" do
    test "denies unknown mode", %{user: user} do
      snapshot = %{id: "snap-1", mode: :unknown_mode, activated_at: nil}

      assert {:error, :invalid_snapshot_mode} =
               UPMPolicy.can_activate_snapshot?(user, snapshot, nil)
    end

    test "denies nil mode", %{user: user} do
      snapshot = %{id: "snap-1", mode: nil, activated_at: nil}

      assert {:error, :invalid_snapshot_mode} =
               UPMPolicy.can_activate_snapshot?(user, snapshot, nil)
    end
  end

  # ============================================================================
  # is_admin?/1 Tests
  # ============================================================================

  describe "is_admin?/1" do
    test "returns true for system role" do
      assert UPMPolicy.is_admin?(%{role: :system})
    end

    test "returns true for upm_admin role" do
      assert UPMPolicy.is_admin?(%{role: :upm_admin})
    end

    test "returns true for system_admin role" do
      assert UPMPolicy.is_admin?(%{role: :system_admin})
    end

    test "returns false for user role" do
      refute UPMPolicy.is_admin?(%{role: :user})
    end

    test "returns false for owner role" do
      refute UPMPolicy.is_admin?(%{role: :owner})
    end

    test "returns false for nil actor" do
      refute UPMPolicy.is_admin?(nil)
    end

    test "returns false for actor without role field" do
      refute UPMPolicy.is_admin?(%{id: "user-1"})
    end

    test "returns false for empty actor map" do
      refute UPMPolicy.is_admin?(%{})
    end
  end

  describe "is_admin?/1 with custom admin_roles config" do
    setup do
      # Configure custom admin roles
      Application.put_env(:thunderline, :upm_policies, admin_roles: [:custom_admin, :superuser])

      on_exit(fn ->
        Application.delete_env(:thunderline, :upm_policies)
      end)

      :ok
    end

    test "returns true for custom admin role" do
      assert UPMPolicy.is_admin?(%{role: :custom_admin})
    end

    test "returns true for superuser role" do
      assert UPMPolicy.is_admin?(%{role: :superuser})
    end

    test "returns false for default system role when overridden" do
      # When custom admin_roles configured, default roles not included
      refute UPMPolicy.is_admin?(%{role: :system})
    end
  end

  # ============================================================================
  # Telemetry Tests
  # ============================================================================

  describe "telemetry" do
    test "emits policy decision telemetry for allow decision", %{user: user, shadow: shadow} do
      # Attach telemetry handler
      ref = make_ref()

      handler = fn _event, measurements, metadata, ref_value ->
        send(self(), {:telemetry, ref_value, measurements, metadata})
      end

      :telemetry.attach(
        "test-policy-decision-allow",
        [:thunderline, :upm, :policy, :decision],
        handler,
        ref
      )

      # Trigger policy decision
      UPMPolicy.can_activate_snapshot?(user, shadow, nil)

      # Verify telemetry
      assert_receive {:telemetry, ^ref, measurements, metadata}, 1000
      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert metadata.decision == :allow
      assert metadata.snapshot_id == "snap-shadow"
      assert metadata.snapshot_mode == :shadow
      assert metadata.actor == "role=user"

      :telemetry.detach("test-policy-decision-allow")
    end

    test "emits policy decision telemetry for deny decision", %{user: user, canary: canary} do
      # Configure empty canary list to trigger denial
      Application.put_env(:thunderline, :upm_policies, canary_tenants: [])

      ref = make_ref()

      handler = fn _event, measurements, metadata, ref_value ->
        send(self(), {:telemetry, ref_value, measurements, metadata})
      end

      :telemetry.attach(
        "test-policy-decision-deny",
        [:thunderline, :upm, :policy, :decision],
        handler,
        ref
      )

      # Trigger policy denial (nil tenant for canary mode)
      UPMPolicy.can_activate_snapshot?(user, canary, nil)

      # Verify telemetry
      assert_receive {:telemetry, ^ref, measurements, metadata}, 1000
      assert is_integer(measurements.duration)
      assert metadata.decision == :deny
      assert metadata.reason == :tenant_required_for_canary
      assert metadata.snapshot_id == "snap-canary"

      :telemetry.detach("test-policy-decision-deny")
      Application.delete_env(:thunderline, :upm_policies)
    end
  end
end
