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

# OpenTelemetry Ash configuration - routed through Thundereye domain for unified observability
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
    Thunderline.Accounts,
    # Simple test domain following Ash guide
    Thunderline.Support,
    # 7-Domain Federation Architecture
    # ⚡🔥 Compute & Acceleration
    Thunderline.Thunderbolt.Domain,
    # ⚡💧 Event Streams & Data Rivers
    Thunderline.Thunderflow.Domain,
    # ⚡🌐 Gateway & External Integration
    Thunderline.Thundergate.Domain,
    # ⚡🧱 Storage & Persistence
    Thunderline.Thunderblock.Domain,
    # ⚡🔗 Connection & Communication
    Thunderline.Thunderlink.Domain,
    # ⚡👑 Governance & Orchestration
    Thunderline.Thundercrown.Domain,
    # ⚡🌐 Spatial Coordinates & Reality Grid
    Thunderline.Thundergrid.Domain
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

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  thunderline: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" =>
        Path.join([Path.expand("../deps", __DIR__), Path.expand("../_build/dev", __DIR__)], ":")
    }
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

# Configure git_ops for semantic versioning and changelog automation
config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/mo/thunderline",
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"

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
    heavy_compute: 2
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
