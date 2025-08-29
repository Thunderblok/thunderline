defmodule Thunderline.TOCP.Config do
  @moduledoc """
  Unified TOCP configuration accessor. Normalizes the existing keyword list in
  `Application.get_env(:thunderline, :tocp)` into a structured map compatible
  with the future canonical map form documented in TOCP_SECURITY.md.

  Supports hot reload via `reload/0` (idempotent) and cheap runtime reads from
  `:persistent_term` to avoid repeated env merges in hot paths (membership
  ticks, routing, etc.).
  """

  @pt_key {:thunderline, :tocp_config}

  @doc "Return normalized config map (loads once then cached)."
  def get do
    case :persistent_term.get(@pt_key, :undefined) do
      :undefined -> load(); map -> map
    end
  end

  @doc "Reload configuration from application env (updates cache)."
  def reload do
    load()
  end

  @doc "Get a top-level key or nested path.

  Examples:
      get_in_path([:reliable, :window])
      get_in_path([:security, :sign_control])
  "
  def get_in_path(path) when is_list(path) do
    get() |> Kernel.get_in(path)
  end

  defp load do
    raw = Application.get_env(:thunderline, :tocp, []) |> Enum.into(%{})

    map = %{
      port: raw[:port] || 5088,
      gossip: %{
        interval_ms: raw[:gossip_interval_ms] || 1_000,
        jitter_ms: raw[:gossip_jitter_ms] || 150,
        k_mode: :auto
      },
      reliable: %{
        window: raw[:reliability_window] || 32,
        ack_batch_ms: raw[:ack_batch_ms] || 10,
        max_retries: raw[:max_retries] || 5
      },
      ttl: %{default: raw[:ttl_hops] || 8},
      dedup: %{lru: raw[:dedup_lru] || 2_048},
      fragments: %{
        max_assemblies_peer: raw[:fragments_max_assemblies_peer] || 8,
        global_cap: raw[:fragments_global_cap] || 256,
        max_chunk: :dynamic
      },
      store: %{
        retention_hours: raw[:store_retention_hours] || 24,
        retention_bytes: raw[:store_retention_bytes] || 512 * 1_024 * 1_024
      },
      hb: %{sample_ratio: raw[:hb_sample_ratio] || 20},
      credits: %{
        initial: raw[:credits_initial] || 64,
        min: raw[:credits_min] || 8,
        refill_per_sec: raw[:credit_refill_per_sec] || 1_000
      },
      rate: %{
        tokens_per_sec_peer: raw[:rate_tokens_per_sec_peer] || 200,
        tokens_per_sec_zone: raw[:rate_tokens_per_sec_zone] || 1_000,
        bucket_size_factor: raw[:rate_bucket_size_factor] || 2
      },
      admission: %{required: raw[:admission_required] != false},
      replay: %{skew_ms: raw[:replay_skew_ms] || 30_000},
      security: %{
        sign_control: raw[:security_sign_control] != false,
        soft_encrypt_flag: raw[:security_soft_encrypt_flag] || :reserved,
        presence_secured: raw[:presence_secured] != false
      },
      selector: %{hysteresis_pct: raw[:selector_hysteresis_pct] || 15}
    }

    :persistent_term.put(@pt_key, map)
    map
  end
end
