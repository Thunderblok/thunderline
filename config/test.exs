import Config
config :thunderline, Oban, testing: :manual
config :thunderline, token_signing_secret: "QnSxy5agB4izHalnSgxl23Q+Gx+Jt+Ve"
config :thunderline, event_validator_mode: :raise, require_actor_ctx: true
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :thunderline, Thunderline.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "thunderline_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :thunderline, ThunderlineWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "6XIfh+Dr+STP7e3yXe23pXwQAFctUcCb0ve6kJXQPNCE0KyUwFjG4f1oA2r7Z2iQ",
  server: false

# In test we don't send emails
config :thunderline, Thunderline.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Thunderwatch in test: keep disabled unless explicitly enabled to avoid noisy events.
config :thunderline, :thunderwatch,
  enabled: false,
  roots: ["lib"],
  ignore: [~r{/\.git/}, ~r{/deps/}],
  hash?: false,
  max_events: 500

# Explicit test feature flags (tocp scaffold disabled unless opted-in per test)
config :thunderline, :features, tocp: false, reward_signal: false

config :thunderline,
  minimal_test_boot: true,
  features: [],
  cerebros_bridge: [
    enabled: false,
    repo_path: Path.expand("../../cerebros-core-algorithm-alpha", __DIR__),
    script_path:
      Path.expand(
        "../../cerebros-core-algorithm-alpha/generative-proof-of-concept-CPU-preprocessing-in-memory.py",
        __DIR__
      ),
    python_executable: System.get_env("CEREBROS_PYTHON") || "python3",
    working_dir: Path.expand("../../cerebros-core-algorithm-alpha", __DIR__),
    invoke: [
      default_timeout_ms:
        case System.get_env("CEREBROS_TIMEOUT_MS") do
          nil -> 5_000
          value -> String.to_integer(value)
        end,
      max_retries:
        case System.get_env("CEREBROS_MAX_RETRIES") do
          nil -> 1
          value -> String.to_integer(value)
        end,
      retry_backoff_ms:
        case System.get_env("CEREBROS_RETRY_BACKOFF_MS") do
          nil -> 250
          value -> String.to_integer(value)
        end
    ],
    env: %{"PYTHONUNBUFFERED" => "1"},
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
          nil -> 1_000
          value -> String.to_integer(value)
        end,
      max_entries:
        case System.get_env("CEREBROS_CACHE_MAX_ENTRIES") do
          nil -> 64
          value -> String.to_integer(value)
        end
    ]
  ],
  vim: [
    enabled: false,
    shadow_mode: true
  ]
