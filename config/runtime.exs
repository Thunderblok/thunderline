import Config

defmodule Thunderline.RuntimeOTelHelpers do
  def maybe_put(opts, _key, nil), do: opts
  def maybe_put(opts, _key, ""), do: opts
  def maybe_put(opts, _key, []), do: opts
  def maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  def parse_otlp_headers(nil), do: nil
  def parse_otlp_headers(""), do: nil

  def parse_otlp_headers(headers) do
    headers
    |> String.split(",", trim: true)
    |> Enum.reduce([], fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [k, v] ->
          key = k |> String.trim() |> String.downcase() |> String.to_charlist()
          value = v |> String.trim() |> String.to_charlist()
          [{key, value} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
    |> case do
      [] -> nil
      list -> list
    end
  end

  def parse_compression(nil), do: nil
  def parse_compression(""), do: nil

  def parse_compression(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      "none" -> nil
      other -> String.to_atom(other)
    end
  end
end

alias Thunderline.RuntimeOTelHelpers, as: RuntimeOTel
config :langchain, openai_key: fn -> System.fetch_env!("OPENAI_API_KEY") end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/thunderline start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :thunderline, ThunderlineWeb.Endpoint, server: true
end

# Slim mode: when SKIP_ASH_SETUP is active we remove ecto repos at runtime so
# no accidental Repo startup occurs via generic code paths (mix tasks, etc.).
if System.get_env("SKIP_ASH_SETUP") in ["1", "true"] do
  config :thunderline, :ecto_repos, []
end

# Optional: route Logger console backend to stderr when LOG_STDERR=1 for diagnosing
# piping/STDOUT issues (safe no-op in normal operation).
if System.get_env("LOG_STDERR") == "1" do
  config :logger, :default_handler, config: [type: :standard_error]
end

# Use new handler-based logger config (replaces deprecated :backends)
config :logger, :default_handler, level: :debug

# ------------------------------------------------------------
# Magika Configuration
# ------------------------------------------------------------
config :thunderline, Thunderline.Thundergate.Magika,
  cli_path: System.get_env("MAGIKA_CLI_PATH", "magika"),
  confidence_threshold: String.to_float(System.get_env("MAGIKA_CONFIDENCE_THRESHOLD", "0.85")),
  timeout: String.to_integer(System.get_env("MAGIKA_TIMEOUT_MS", "5000"))

# Classifier Consumer Configuration
config :thunderline, Thunderline.Thunderflow.Consumers.Classifier,
  batch_size: String.to_integer(System.get_env("CLASSIFIER_BATCH_SIZE", "10")),
  batch_timeout: String.to_integer(System.get_env("CLASSIFIER_BATCH_TIMEOUT_MS", "1000")),
  concurrency: String.to_integer(System.get_env("CLASSIFIER_CONCURRENCY", "4"))

# ------------------------------------------------------------
# OpenTelemetry Runtime Wiring (enabled by default; can be disabled via env)
#
# Use OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT/TRACES_ENDPOINT to direct traces.
# Set OTEL_DISABLED=1 to skip instrumentation entirely.
# ------------------------------------------------------------
if System.get_env("OTEL_DISABLED") not in ["1", "true", "TRUE"] do
  # Resource/service attributes
  service_name = System.get_env("OTEL_SERVICE_NAME") || "thunderline"
  service_namespace = System.get_env("OTEL_SERVICE_NAMESPACE") || "thunderline"
  service_version = Application.spec(:thunderline, :vsn) |> to_string()

  config :opentelemetry, :resource,
    service: [
      name: service_name,
      namespace: service_namespace,
      version: service_version
    ]

  exporter_opts =
    []
    |> RuntimeOTel.maybe_put(
      :traces_endpoint,
      System.get_env("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
    )
    |> RuntimeOTel.maybe_put(:endpoint, System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT"))
    |> RuntimeOTel.maybe_put(
      :headers,
      RuntimeOTel.parse_otlp_headers(System.get_env("OTEL_EXPORTER_OTLP_HEADERS"))
    )
    |> RuntimeOTel.maybe_put(:certificate, System.get_env("OTEL_EXPORTER_OTLP_CERTIFICATE"))
    |> RuntimeOTel.maybe_put(
      :compression,
      RuntimeOTel.parse_compression(System.get_env("OTEL_EXPORTER_OTLP_COMPRESSION"))
    )

  exporter_available? =
    Code.ensure_loaded?(:opentelemetry_exporter) and
      function_exported?(:opentelemetry_exporter, :start_link, 1)

  if exporter_available? do
    config :opentelemetry, :processors, [
      {:otel_batch_processor, %{exporter: {:opentelemetry_exporter, exporter_opts}}}
    ]
  else
    IO.puts(:stderr, "[otel] opentelemetry_exporter not available; telemetry export disabled.")
    config :opentelemetry, :processors, []
  end

  # Phoenix & Ecto instrumentation enables spans for web and DB
  config :opentelemetry_phoenix, enable: true
  config :opentelemetry_ecto, enable: true
end

# ------------------------------------------------------------
# Runtime Feature Flag Overrides (Demo / Env-based)
# Allows enabling features at runtime without recompilation. The
# Feature.enabled?/2 helper now checks Application env first.
#
#   DEMO_MODE=1 -> enables curated demo feature set
#   FEATURE_CA_VIZ=1
#   FEATURE_THUNDERVINE_LINEAGE=1
#   FEATURE_AI_CHAT_PANEL=0/1
#   FEATURE_ENABLE_NDJSON=1 (NDJSON logging) / FEATURE_ENABLE_UPS=1
# ------------------------------------------------------------
if System.get_env("DEMO_MODE") in ["1", "true", "TRUE"] do
  base = Application.get_env(:thunderline, :features, []) |> Enum.into(%{})

  demo =
    base
    |> Map.merge(%{
      ca_viz: true,
      thundervine_lineage: true,
      ai_chat_panel: true
    })

  config :thunderline, :features, demo |> Enum.into([])
end

# Accept legacy env names for backwards compat (README drift)
legacy_overrides = [
  {:enable_ndjson, System.get_env("ENABLE_NDJSON") in ["1", "true", "TRUE"]},
  {:enable_ups, System.get_env("ENABLE_UPS") in ["1", "true", "TRUE"]}
]

runtime_feature_overrides = [
  {:ca_viz, "FEATURE_CA_VIZ"},
  {:thundervine_lineage, "FEATURE_THUNDERVINE_LINEAGE"},
  {:ai_chat_panel, "FEATURE_AI_CHAT_PANEL"},
  {:enable_ndjson, "FEATURE_ENABLE_NDJSON"},
  {:enable_ups, "FEATURE_ENABLE_UPS"},
  {:tocp, "FEATURE_TOCP"},
  {:ml_nas, "CEREBROS_ENABLED"},
  {:cerebros_bridge, "CEREBROS_ENABLED"}
]

runtime_enabled =
  runtime_feature_overrides
  |> Enum.reduce(Application.get_env(:thunderline, :features, []) |> Enum.into(%{}), fn {flag,
                                                                                         env},
                                                                                        acc ->
    case System.get_env(env) do
      val when val in ["1", "true", "TRUE"] -> Map.put(acc, flag, true)
      val when val in ["0", "false", "FALSE"] -> Map.put(acc, flag, false)
      _ -> acc
    end
  end)

enabled_list = runtime_enabled |> Enum.into([]) |> Enum.sort()
config :thunderline, :features, enabled_list

# Log enabled features on boot for observability
enabled = enabled_list |> Enum.filter(fn {_k, v} -> v end) |> Enum.map(&elem(&1, 0))
IO.puts("[features] enabled: #{inspect(enabled)}")

cerebros_toggle =
  case System.get_env("CEREBROS_ENABLED") do
    val when val in ["1", "true", "TRUE"] -> true
    val when val in ["0", "false", "FALSE"] -> false
    _ -> nil
  end

if not is_nil(cerebros_toggle) do
  base_bridge = Application.get_env(:thunderline, :cerebros_bridge, [])
  config :thunderline, :cerebros_bridge, Keyword.put(base_bridge, :enabled, cerebros_toggle)
end

# ------------------------------------------------------------
# Oban Configuration (Runtime)
# NOTE: test.exs sets up Oban in :manual testing mode via compile-time config.
# We only override Oban config in non-test environments.
# Set TL_ENABLE_OBAN=1 or CEREBROS_ENABLED=1 to enable in dev/prod.
# ------------------------------------------------------------
if config_env() != :test do
  oban_enabled =
    System.get_env("TL_ENABLE_OBAN") in ["1", "true", "TRUE"] or
      System.get_env("CEREBROS_ENABLED") in ["1", "true", "TRUE"]

  if oban_enabled do
    config :thunderline, Oban,
      repo: Thunderline.Repo,
      queues: [cerebros_training: 10],
      plugins: []
  else
    config :thunderline, Oban, false
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :thunderline, Thunderline.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :thunderline, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :thunderline, ThunderlineWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :thunderline,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :thunderline, ThunderlineWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :thunderline, ThunderlineWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :thunderline, Thunderline.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Cloak Vault configuration (AshCloak uses this vault)
  if vault_key = System.get_env("THUNDERLINE_VAULT_KEY") do
    config :thunderline, Thunderline.Vault,
      ciphers: [
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(vault_key)}
      ]
  else
    # In dev/test, you can set THUNDERLINE_VAULT_KEY to a base64-encoded 256-bit key.
    # Leaving it unset keeps the vault unconfigured; encrypted fields should not be accessed.
    :ok
  end
end
