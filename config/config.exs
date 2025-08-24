# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

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
  ash_domains: [
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

    # OPTIONAL (disabled right now):
    # Thunderline.Thundergate.Domain,  # Auth / security / policies
    # Thunderline.Thunderbolt.Domain,  # Heavy compute / CA engine / optimization
  # Thunderline.Thundercrown.Domain,  # (now enabled above) Governance / orchestration / AI routing
    # Thunderline.Thundergrid.Domain   # Spatial grid / zone topology
  ]

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
config :thunderline, Oban,
  repo: Thunderline.Repo,
  plugins: [
    Oban.Plugins.Cron,
    Oban.Plugins.Pruner
  ],
  queues: [
    default: 10,
    cross_domain: 5,
    scheduled_workflows: 3,
  heavy_compute: 2,
  probe: 2
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
config :ash_authentication, AshAuthenticationPhoenix.Components,
  otp_app: :thunderline

config :ash_authentication_phoenix,
  use_get?: true,
  root_path: "/auth"
