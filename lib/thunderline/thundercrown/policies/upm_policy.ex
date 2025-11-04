defmodule Thunderline.Thundercrown.Policies.UPMPolicy do
  @moduledoc """
  Authorization policies for Unified Persistent Model snapshot operations.

  Governs the lifecycle progression of UPM snapshots through rollout phases:
  - Shadow Mode: Observational deployment with all tenants, no production impact
  - Canary Mode: Limited rollout to configured tenant subset
  - Active Mode: Full production deployment after validation

  ## Policy Rules

  1. **Admin Bypass**: System and UPM admins can activate any snapshot
  2. **Shadow Mode**: Always allowed (observational only, no real impact)
  3. **Canary Mode**: Only allowed for tenants in configured canary list
  4. **Active Mode**: Only allowed after minimum shadow duration (14 days default)

  ## Configuration

      config :thunderline, :upm_policies,
        canary_tenants: ["tenant-1", "tenant-2"],  # Tenant IDs for canary rollout
        min_shadow_hours: 336,                     # Minimum shadow duration (14 days)
        admin_roles: [:system, :upm_admin]         # Roles with admin bypass

  ## Usage

      # In SnapshotManager
      case UPMPolicy.can_activate_snapshot?(actor, snapshot, tenant) do
        :ok ->
          # Proceed with activation
        {:error, reason} ->
          # Handle policy violation
      end

  ## Telemetry

  Emits `[:thunderline, :upm, :policy, :decision]` events with:
  - `measurements`: %{duration: microseconds}
  - `metadata`: %{decision: :allow | :deny, reason: term(), actor: map(), snapshot_id: binary()}

  Ownership: ThunderCrown Policy Team (HC-22)
  Security Level: Critical
  """

  require Logger

  @type actor :: map() | nil
  @type snapshot :: %{mode: atom(), activated_at: DateTime.t() | nil, id: binary()} | map()
  @type tenant :: %{id: binary()} | map() | nil
  @type policy_result :: :ok | {:error, term()}

  # Configuration defaults
  @default_min_shadow_hours 336  # 14 days
  @default_admin_roles [:system, :upm_admin, :system_admin]
  @default_canary_tenants []

  @doc """
  Primary authorization check for snapshot activation.

  Returns `:ok` if activation is allowed, or `{:error, reason}` if denied.

  ## Parameters

  - `actor` - The user or system attempting activation (may be nil)
  - `snapshot` - The snapshot to be activated (requires :mode, :activated_at, :id)
  - `tenant` - The tenant context for activation (may be nil)

  ## Authorization Logic

  1. **Admin Bypass**: If actor has admin role → `:ok`
  2. **Shadow Mode**: If snapshot.mode == :shadow → `:ok` (observational only)
  3. **Canary Mode**: If snapshot.mode == :canary → check canary tenant list
  4. **Active Mode**: If snapshot.mode == :active → validate shadow duration
  5. **Unknown Mode**: Deny with `:invalid_mode`

  ## Examples

      # Admin can activate any snapshot
      iex> actor = %{role: :system}
      iex> snapshot = %{mode: :canary, id: "snap-123"}
      iex> UPMPolicy.can_activate_snapshot?(actor, snapshot, tenant)
      :ok

      # Shadow mode always allowed
      iex> actor = %{role: :user}
      iex> snapshot = %{mode: :shadow, id: "snap-456"}
      iex> UPMPolicy.can_activate_snapshot?(actor, snapshot, nil)
      :ok

      # Canary mode requires tenant in list
      iex> actor = %{role: :user}
      iex> snapshot = %{mode: :canary, id: "snap-789"}
      iex> tenant = %{id: "non-canary-tenant"}
      iex> UPMPolicy.can_activate_snapshot?(actor, snapshot, tenant)
      {:error, :not_in_canary_rollout}

      # Active mode requires shadow validation
      iex> actor = %{role: :user}
      iex> snapshot = %{mode: :active, activated_at: nil, id: "snap-012"}
      iex> UPMPolicy.can_activate_snapshot?(actor, snapshot, tenant)
      {:error, :no_shadow_activation_timestamp}
  """
  @spec can_activate_snapshot?(actor, snapshot, tenant) :: policy_result
  def can_activate_snapshot?(actor, snapshot, tenant) do
    start = System.monotonic_time(:microsecond)

    result =
      cond do
        # Rule 1: Admin bypass
        is_admin?(actor) ->
          Logger.debug("""
          [UPM.Policy] Admin bypass activated
            actor: #{format_actor(actor)}
            snapshot: #{snapshot.id}
            mode: #{snapshot.mode}
          """)

          :ok

        # Rule 2: Shadow mode (observational, always allowed)
        snapshot.mode == :shadow ->
          Logger.debug("""
          [UPM.Policy] Shadow mode activation allowed
            snapshot: #{snapshot.id}
            tenant: #{format_tenant(tenant)}
          """)

          :ok

        # Rule 3: Canary mode (restricted tenant list)
        snapshot.mode == :canary ->
          validate_canary_eligibility(snapshot, tenant)

        # Rule 4: Active mode (requires shadow validation period)
        snapshot.mode == :active ->
          validate_active_rollout(snapshot)

        # Rule 5: Unknown or invalid mode
        true ->
          Logger.error("""
          [UPM.Policy] Invalid snapshot mode
            snapshot: #{snapshot.id}
            mode: #{inspect(snapshot.mode)}
          """)

          {:error, :invalid_snapshot_mode}
      end

    # Emit telemetry
    emit_decision(actor, snapshot, tenant, result, start)

    result
  end

  @doc """
  Validates if a tenant is eligible for canary rollout.

  Returns `:ok` if tenant is in canary list, or `{:error, reason}` otherwise.

  ## Parameters

  - `snapshot` - The canary snapshot being activated
  - `tenant` - The tenant context (may be nil)

  ## Returns

  - `:ok` - Tenant is in canary list
  - `{:error, :tenant_required_for_canary}` - Tenant context is nil
  - `{:error, :not_in_canary_rollout}` - Tenant not in canary list
  """
  @spec validate_canary_eligibility(snapshot, tenant) :: policy_result
  def validate_canary_eligibility(snapshot, tenant) do
    cond do
      is_nil(tenant) ->
        Logger.warning("""
        [UPM.Policy] Canary activation requires tenant context
          snapshot: #{snapshot.id}
        """)

        {:error, :tenant_required_for_canary}

      not is_map(tenant) or not is_map_key(tenant, :id) or is_nil(Map.get(tenant, :id)) ->
        Logger.warning("""
        [UPM.Policy] Canary activation requires tenant ID
          snapshot: #{snapshot.id}
          tenant: #{inspect(tenant)}
        """)

        {:error, :tenant_id_required_for_canary}

      tenant_in_canary_list?(tenant) ->
        Logger.info("""
        [UPM.Policy] Canary activation authorized
          snapshot: #{snapshot.id}
          tenant: #{tenant.id}
        """)

        :ok

      true ->
        Logger.warning("""
        [UPM.Policy] Tenant not in canary rollout
          snapshot: #{snapshot.id}
          tenant: #{tenant.id}
          canary_list: #{inspect(get_canary_tenants())}
        """)

        {:error, :not_in_canary_rollout}
    end
  end

  @doc """
  Validates if a snapshot has completed required shadow mode duration.

  Active mode requires minimum shadow validation period (default 14 days).

  ## Parameters

  - `snapshot` - The active snapshot being activated

  ## Returns

  - `:ok` - Shadow duration requirement met
  - `{:error, :no_shadow_activation_timestamp}` - Shadow activation never recorded
  - `{:error, {:insufficient_shadow_duration, required, actual}}` - Duration too short
  """
  @spec validate_active_rollout(snapshot) :: policy_result
  def validate_active_rollout(snapshot) do
    min_hours = get_min_shadow_hours()

    cond do
      is_nil(snapshot.activated_at) ->
        Logger.error("""
        [UPM.Policy] Active mode requires prior shadow activation
          snapshot: #{snapshot.id}
          activated_at: nil
        """)

        {:error, :no_shadow_activation_timestamp}

      true ->
        shadow_duration = DateTime.diff(DateTime.utc_now(), snapshot.activated_at, :hour)

        if shadow_duration >= min_hours do
          Logger.info("""
          [UPM.Policy] Active rollout authorized
            snapshot: #{snapshot.id}
            shadow_duration: #{shadow_duration}h
            required: #{min_hours}h
          """)

          :ok
        else
          Logger.warning("""
          [UPM.Policy] Insufficient shadow duration
            snapshot: #{snapshot.id}
            shadow_duration: #{shadow_duration}h
            required: #{min_hours}h
            remaining: #{min_hours - shadow_duration}h
          """)

          {:error, {:insufficient_shadow_duration, min_hours, shadow_duration}}
        end
    end
  end

  @doc """
  Checks if actor has administrative privileges for UPM operations.

  Admin roles (default: [:system, :upm_admin, :system_admin]) bypass all policy checks.

  ## Parameters

  - `actor` - The actor to check (may be nil)

  ## Returns

  - `true` - Actor has admin role
  - `false` - Actor does not have admin role or is nil
  """
  @spec is_admin?(actor) :: boolean()
  def is_admin?(nil), do: false

  def is_admin?(actor) do
    admin_roles = get_admin_roles()
    actor_role = Map.get(actor, :role)

    actor_role in admin_roles
  end

  # Private Helper Functions

  @spec tenant_in_canary_list?(tenant) :: boolean()
  defp tenant_in_canary_list?(tenant) when is_nil(tenant), do: false

  defp tenant_in_canary_list?(tenant) do
    canary_tenants = get_canary_tenants()
    tenant_id = Map.get(tenant, :id)

    tenant_id in canary_tenants
  end

  @spec get_canary_tenants() :: [binary()]
  defp get_canary_tenants do
    Application.get_env(:thunderline, :upm_policies, [])
    |> Keyword.get(:canary_tenants, @default_canary_tenants)
  end

  @spec get_min_shadow_hours() :: non_neg_integer()
  defp get_min_shadow_hours do
    Application.get_env(:thunderline, :upm_policies, [])
    |> Keyword.get(:min_shadow_hours, @default_min_shadow_hours)
  end

  @spec get_admin_roles() :: [atom()]
  defp get_admin_roles do
    Application.get_env(:thunderline, :upm_policies, [])
    |> Keyword.get(:admin_roles, @default_admin_roles)
  end

  @spec format_actor(actor) :: String.t()
  defp format_actor(nil), do: "nil"
  defp format_actor(%{role: role}), do: "role=#{role}"
  defp format_actor(actor), do: inspect(actor)

  @spec format_tenant(tenant) :: String.t()
  defp format_tenant(nil), do: "nil"
  defp format_tenant(%{id: id}), do: id
  defp format_tenant(tenant), do: inspect(tenant)

  @spec emit_decision(actor, snapshot, tenant, policy_result, integer()) :: :ok
  defp emit_decision(actor, snapshot, tenant, result, start_time) do
    duration = System.monotonic_time(:microsecond) - start_time

    {decision, reason} = case result do
      :ok -> {:allow, nil}
      {:error, r} -> {:deny, r}
    end

    metadata = %{
      decision: decision,
      reason: reason,
      actor: format_actor(actor),
      snapshot_id: snapshot.id,
      snapshot_mode: snapshot.mode,
      tenant: format_tenant(tenant)
    }

    :telemetry.execute([:thunderline, :upm, :policy, :decision], %{duration: duration}, metadata)
  end
end
