# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

## AshTypescript configuration (typed TS client & RPC)
config :ash_typescript,
  # Default output into Phoenix assets (adjust if separate frontend)
  output_file: "assets/js/ash_rpc.ts",
  # HTTP RPC endpoints
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  # Field casing from/to the client
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,
  # Multitenancy: get tenant from conn/socket assigns by default
  require_tenant_parameters: false,
  # Generate Zod schemas & validation helpers alongside client
  generate_zod_schemas: true,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",
  generate_validation_functions: true,
  # Phoenix channel RPC generation is optional; disabled by default
  generate_phx_channel_rpc_actions: false,
  phoenix_import_path: "phoenix"

config :ash_graphql, authorize_update_destroy_with_error?: true

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  tracer: [OpentelemetryAsh]

# OpenTelemetry Ash configuration - routed through Thundergate domain for unified observability
config :opentelemetry_ash,
  trace_types: [:custom, :action, :flow]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :tokens,
        :postgres,
        :admin,
        :graphql,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [
        :admin,
        :graphql,
        :resources,
        :policies,
        :authorization,
        :domain,
        :execution
      ]
    ]
  ]

config :thunderline,
  ecto_repos: [Thunderline.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Feature flags list (see FEATURE_FLAGS.md). Add flags here to enable.
  features: [
    # :vim, :vim_active, :cerebros_bridge
  ],
  # Numerics adapter defaults (fallback; switch to :sidecar or :nif via env/config)
  numerics_adapter: Thunderline.Thunderbolt.Numerics.Adapters.ElixirFallback,
  numerics_sidecar_url:
    System.get_env("THUNDERLINE_NUMERICS_SIDECAR_URL") || "http://localhost:8089",
  # Cerebros bridge facade configuration (disabled by default)
  cerebros_bridge: [
    enabled: false,
    repo_path:
      System.get_env("CEREBROS_REPO") ||
        Path.expand("../../cerebros-core-algorithm-alpha", __DIR__),
    script_path:
      System.get_env("CEREBROS_SCRIPT") ||
        Path.expand(
          "../../cerebros-core-algorithm-alpha/generative-proof-of-concept-CPU-preprocessing-in-memory.py",
          __DIR__
        ),
    python_executable: System.get_env("CEREBROS_PYTHON") || "python3",
    working_dir:
      System.get_env("CEREBROS_WORKDIR") ||
        Path.expand("../../cerebros-core-algorithm-alpha", __DIR__),
    invoke: [
      default_timeout_ms:
        case System.get_env("CEREBROS_TIMEOUT_MS") do
          nil -> 15_000
          value -> String.to_integer(value)
        end,
      max_retries:
        case System.get_env("CEREBROS_MAX_RETRIES") do
          nil -> 2
          value -> String.to_integer(value)
        end,
      retry_backoff_ms:
        case System.get_env("CEREBROS_RETRY_BACKOFF_MS") do
          nil -> 750
          value -> String.to_integer(value)
        end
    ],
    env: %{
      "PYTHONUNBUFFERED" => "1"
    },
    cache: [
      enabled:
        case System.get_env("CEREBROS_CACHE_ENABLED") do
          "0" -> false
          "false" -> false
          "FALSE" -> false
          _ -> true
        end,
      ttl_ms:
        case System.get_env("CEREBROS_CACHE_TTL_MS") do
          nil -> 30_000
          value -> String.to_integer(value)
        end,
      max_entries:
        case System.get_env("CEREBROS_CACHE_MAX_ENTRIES") do
          nil -> 512
          value -> String.to_integer(value)
        end
    ]
  ],
  # VIM (Virtual Ising Machine) config surface (shadow mode = dry-run)
  vim: [
    enabled: false,
    shadow_mode: true,
    router: [
      k_relays: 3,
      lambda_exact_k: 2.0,
      schedule: [t0: 3.0, alpha: 0.95, iters: 200, max_ms: 25]
    ],
    persona: [board_size: 128, schedule: [t0: 2.5, alpha: 0.96, iters: 150, max_ms: 40]],
    temp_ctrl: [enabled: true, target_variance: 0.05, alpha: 0.05]
  ],
  # TOCP domain base config (scaffold). Feature flag lives under :features (flag :tocp disabled by default).
  # The nested :tocp keyword list holds protocol runtime parameters.
  tocp: [
    port: 5088,
    gossip_interval_ms: 1_000,
    gossip_jitter_ms: 150,
    reliability_window: 32,
    ack_batch_ms: 10,
    ttl_hops: 8,
    max_retries: 5,
    dedup_lru: 2_048,
    # Security-tilted fragment assembly caps (MVP hardening)
    fragments_max_assemblies_peer: 8,
    fragments_global_cap: 256,
    store_retention_hours: 24,
    store_retention_bytes: 512 * 1_024 * 1_024,
    hb_sample_ratio: 20,
    # Credits / rate limiting (security posture)
    credits_initial: 64,
    credits_min: 8,
    credit_refill_per_sec: 1_000,
    rate_tokens_per_sec_peer: 200,
    # Admission / identity / replay
    admission_required: true,
    replay_skew_ms: 30_000,
    security_sign_control: true,
    security_soft_encrypt_flag: :reserved,
    selector_hysteresis_pct: 15,
    presence_secured: true
  ],
  ash_domains: [
    Thunderline.Chat,
    # === SLIM MODE ACTIVE ===
    # For the current milestone we only need the core runtime needed to ship
    # fast on comms + events + storage. Extra domains are commented out to
    # reduce compile surface, migration noise, Oban scan time, and cognitive load.
    # Re‑enable by uncommenting when you actually implement features there.

    # CORE (keep):
    # Storage / memory / vault
    Thunderline.Thunderblock.Domain,
    # Event streams / pipelines
    Thunderline.Thunderflow.Domain,
    # Realtime messaging / channels
    Thunderline.Thunderlink.Domain,
    # Re-enabled to host AshAI-powered orchestration & MCP resources
    Thunderline.Thundercrown.Domain,
    # Auth/security domain now enabled for AshAuthentication integration
    Thunderline.Thundergate.Domain,
    Thunderline.Thundercom.Domain
  ]

# OPTIONAL (disabled right now):
# Thunderline.Thundergate.Domain,  # Auth / security / policies
# Thunderline.Thunderbolt.Domain,  # Heavy compute / CA engine / optimization
# Thunderline.Thundercrown.Domain,  # (now enabled above) Governance / orchestration / AI routing
# Thunderline.Thundergrid.Domain   # Spatial grid / zone topology

# Configures the endpoint
config :thunderline, ThunderlineWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: ThunderlineWeb.ErrorHTML, json: ThunderlineWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Thunderline.PubSub,
  live_view: [signing_salt: "v6rw1L8A"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :thunderline, Thunderline.Mailer, adapter: Swoosh.Adapters.Local

## esbuild bundling removed (Option A no-node). If bundling reintroduced later, restore config :esbuild.

# Re-introduced esbuild for CA visualization & richer JS hooks
config :esbuild,
  version: "0.23.0",
  thunderline: [
    args: ~w(js/app.js --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  thunderline: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ash compatible foreign key types
config :ash, :compatible_foreign_key_types, [
  {Ash.Type.UUID, Ash.Type.String}
]

# Configure Mnesia database location
config :mnesia,
  # Using ~c for charlist
  dir: ~c".mnesia/#{Mix.env()}/#{node()}"

# Configure git_ops for semantic versioning and changelog automation.
# Loaded only in :dev to avoid loading git plumbing in test/prod releases.
if config_env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/Thunderblok/Thunderline",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v"
end

# Configure Oban for background job processing with AshOban integration
# NOTE: Oban's Cron plugin does not support an inline :if option inside the crontab entry.
# We build the crontab list conditionally at config compile time instead.
compactor_cron =
  if System.get_env("ENABLE_WORKFLOW_COMPACTOR_CRON") in ["1", "true", "TRUE"] do
    [
      {"*/5 * * * *", Thunderline.Thundervine.WorkflowCompactorWorker}
    ]
  else
    []
  end

config :thunderline, Oban,
  repo: Thunderline.Repo,
  plugins: [
    {Oban.Plugins.Cron, crontab: compactor_cron},
    Oban.Plugins.Pruner
  ],
  queues: [
    default: 10,
    cross_domain: 5,
    scheduled_workflows: 3,
    heavy_compute: 2,
    probe: 2,
    chat_responses: [limit: 10],
    conversations: [limit: 10]
  ]

# --- AshOban Trigger Usage Reference ---------------------------------------
# Example (from docs) for adding a trigger inside a resource:
#
#   defmodule MyApp.Resource do
#     use Ash.Resource, domain: MyDomain, extensions: [AshOban]
#
#     oban do
#       triggers do
#         trigger :process do
#           action :process
#           where expr(processed != true)
#           # check every minute
#           scheduler_cron "* * * * *"
#           # optionally: queue :resource_process  (defaults to <short_name>_<trigger>)
#           # on_error :errored   # (example of additional DSL option)
#         end
#       end
#     end
#   end
#
# Queue Naming:
# * If you DO NOT specify `queue`, AshOban will derive one as <resource_short_name>_<trigger_name>.
# * If you DO specify `queue`, ensure it is declared above in Oban queues (with a concurrency integer).
#
# Current Ticket resource triggers:
#   :process_tickets  -> explicitly uses queue :default (declared above)
#   :escalate_tickets -> explicitly uses queue :scheduled_workflows (declared above)
# Add additional queues here when introducing new triggers with custom queues.
# ---------------------------------------------------------------------------

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# AshAuthentication Phoenix integration (basic defaults; can be overridden per env)
# AshAuthentication Phoenix generated component configuration
config :ash_authentication, AshAuthenticationPhoenix.Components, otp_app: :thunderline

config :ash_authentication_phoenix,
  use_get?: true,
  root_path: "/auth"

# AshAdmin configuration (enable admin UI over all primary domains)
config :ash_admin, AshAdmin,
  otp_app: :thunderline,
  domains: [
    Thunderline.Thunderblock.Domain,
    Thunderline.Thunderflow.Domain,
    Thunderline.Thunderlink.Domain,
    Thunderline.Thundercrown.Domain,
    Thunderline.Thundergate.Domain,
    Thunderline.Thundercom.Domain
  ]
