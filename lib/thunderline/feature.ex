defmodule Thunderline.Feature do
  @moduledoc """
  Runtime feature flag evaluation & simple per-process overrides.

  Reads static flags from application config `:thunderline, :features` (keyword list or map)
  and allows test/local overrides via process dictionary.

  NOTE: This is a minimal implementation (HC-10). Future extensions:
    * Telemetry emission (sampled)
    * Per-tenant dynamic store
    * Percentage & cohort rollouts
  """

  @compile {:no_warn_undefined, Application}
  # Compile-time snapshot (default baseline)
  @features (Application.compile_env(:thunderline, :features, []) |> Enum.into(%{}))

  @doc """
  Return true if the feature `flag` is enabled.

  Options:
    * `:default` - fallback boolean if flag absent (default false)
  """
  @spec enabled?(atom(), keyword()) :: boolean()
  def enabled?(flag, opts \\ []) when is_atom(flag) do
    case Process.get({:thunderline_flag_override, flag}) do
      nil ->
        # Allow runtime application env overrides (so demo/prod can enable flags without recompiling)
        runtime = Application.get_env(:thunderline, :features, []) |> Enum.into(%{})
        Map.get(runtime, flag, Map.get(@features, flag, Keyword.get(opts, :default, false)))
      override -> override
    end
  end

  @doc """
  Temporarily override a feature flag for the current process (tests).
  """
  @spec override(atom(), boolean()) :: :ok
  def override(flag, value) when is_atom(flag) and is_boolean(value) do
    Process.put({:thunderline_flag_override, flag}, value)
    :ok
  end

  @doc """
  Clear a previously set override for current process.
  """
  @spec clear_override(atom()) :: :ok
  def clear_override(flag) when is_atom(flag) do
    Process.delete({:thunderline_flag_override, flag})
    :ok
  end

  @doc """
  Return map of all compile-time feature flags (ignores overrides).
  """
  @spec all() :: map()
  def all, do: @features
end
