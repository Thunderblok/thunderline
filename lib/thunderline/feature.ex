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
  # Runtime baseline - read from application env at runtime for flexibility
  # No longer using compile_env to allow features to change without recompilation
  defp base_features do
    normalize_features(Application.get_env(:thunderline, :features, []))
  end

  @doc """
  Return true if the feature `flag` is enabled.

  Options:
    * `:default` - fallback boolean if flag absent (default false)
  """
  @spec enabled?(atom(), keyword()) :: boolean()
  def enabled?(flag, opts \\ []) when is_atom(flag) do
    case Process.get({:thunderline_flag_override, flag}) do
      nil ->
        # Read from runtime application env
        Map.get(base_features(), flag, Keyword.get(opts, :default, false))

      override ->
        override
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
  Return map of all feature flags (ignores overrides).
  """
  @spec all() :: map()
  def all, do: base_features()

  # Internal helpers
  defp normalize_features(v) do
    cond do
      is_map(v) ->
        v

      is_list(v) ->
        # Support either keyword list or plain list of atoms
        cond do
          v == [] ->
            %{}

          Enum.all?(v, &is_atom/1) ->
            Map.new(v, &{&1, true})

          Enum.all?(v, fn
            {k, _} when is_atom(k) -> true
            _ -> false
          end) ->
            Map.new(v)

          true ->
            %{}
        end

      true ->
        %{}
    end
  end
end
