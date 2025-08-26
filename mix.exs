defmodule Thunderline.MixProject do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :thunderline,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
  # Use default Mix compilers (was restricted to [:elixir, :app] which can skip needed steps)
  compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      mod: {Thunderline.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Compile only core lib/ by default. Experimental former BOnus modules have been
  # migrated into proper domain folders under lib/thunderline/* so we no longer
  # need to add a separate BOnus path.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:oban, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
  {:ash_authentication_phoenix, "~> 2.0"},
  # Password hashing for AshAuthentication password strategy
  {:bcrypt_elixir, "~> 3.1"},
  # Local ML/architecture engine (cloned repo) – Cerebros (quarantined behind feature flag)
  {:cerebros, path: "cerebros", only: [:dev], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test]},

      # Phoenix
      {:phoenix, "~> 1.8.0"},
      {:phoenix_html, "~> 4.0"},
      {:live_ex_webrtc, "~> 0.8.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
  {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:swoosh, "~> 1.16"},

      # Ash Framework (includes PostgreSQL support)
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
  {:ash_postgres, "~> 2.0"},
      {:ash_graphql, "~> 1.0"},
      {:ash_json_api, "~> 1.0"},
      {:ash_oban, "~> 0.4"},
      {:ash_events, "~> 0.4.3"},
      {:opentelemetry_ash, "~> 0.1.3"},
      {:ash_state_machine, "~> 0.2.12"},
      {:ash_admin, "~> 0.11"},

      # Additional deps
      {:uuid, "~> 1.1"},
      {:broadway, "~> 1.0"},
      {:picosat_elixir, "~> 0.2"},
      {:sourceror, "~> 1.10"},
      {:iterex, "~> 0.1.2"},
      {:off_broadway_memory, "~> 1.1"},
      {:off_broadway_amqp10, "~> 0.1"},
      {:flow, "~> 1.0"},
      {:hackney, "~> 1.18"},
      {:httpoison, "~> 2.0"},
      {:timex, "~> 3.7"},
      {:ex_webrtc, "~> 0.13.0"},
      {:ex_sctp, "~> 0.1.2"},
      {:reactor, "~> 0.15.6"},
      {:eagl, "~> 0.9.0"},
      {:simple_sat, "~> 0.1.3"},
      # Required for eagl image loading
      {:stb_image, "~> 0.6"},
      # For supervision tree visualization
      {:ex_rose_tree, "~> 0.1.3"},

      # Memory and Security

      {:memento, "~> 0.5.0"},
      {:cloak, "~> 1.1"},

      # ECS and GraphQL
      {:ecsx, "~> 0.5"},
      {:absinthe, "~> 1.7"},
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_plug, "~> 1.5"},

      # 3D Visualization
      # {:hologram, "~> 0.2", only: [:dev, :test]},  # Temporarily disabled for Team Bruce integration

      # Neural Computing & Machine Learning 🧠⚡
      {:nx, "~> 0.9"},
      {:axon, "~> 0.7"},
      {:exla, "~> 0.9"},
      {:torchx, "~> 0.9"},
      {:bumblebee, "~> 0.6"},
      {:polaris, "~> 0.1"},

  # File system watching (used by internal Thunderwatch service). Only in dev & test.
  {:file_system, "~> 1.0", only: [:dev, :test]},

      # Code Quality & Development Tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.6.1", only: [:dev]}
    ]
  end

  defp aliases do
    [
      # setup no longer unconditionally runs "deps.get". We only fetch deps if:
      #  1. SKIP_DEPS_GET env var is NOT set to true, AND
      #  2. We detect a missing representative dependency folder (phoenix) or lock file.
      # This prevents surprise re-resolution of deps during iterative dev where you just want
      # migrations/assets. Force with `mix deps.get` manually when you really intend it.
      setup: [&maybe_deps_get/1, "ash.setup", "assets.setup", "assets.build"],
      # Allow skipping ash.setup in tests to run fast, DB-less component/unit tests
  # Provide a non-recursive alias to run full test setup + tests.
  "test.all": [&maybe_ash_setup/1, "test"],
      # One-shot resource -> migration -> migrate convenience
      "ash.migrate": ["ash_postgres.generate_migrations", "ecto.migrate"],
  # Option A (no esbuild/node): only Tailwind profile 'thunderline'
  "assets.setup": ["tailwind.install --if-missing"],
  "assets.build": ["tailwind thunderline"],
  "assets.deploy": ["tailwind thunderline --minify", "phx.digest"]
    ]
  end

  # Conditionally run ash.setup for tests. Set SKIP_ASH_SETUP=true to bypass migrations
  # when running isolated, non-database dependent tests (e.g. LiveView logic, automata CA engine).
  defp maybe_ash_setup(_args) do
    if System.get_env("SKIP_ASH_SETUP") == "true" do
      Mix.shell().info("[test alias] Skipping ash.setup (SKIP_ASH_SETUP=true)")
    else
      Mix.Task.run("ash.setup", ["--quiet"])
    end
  end

  # Conditionally run deps.get only when really needed.
  # Heuristics:
  #   * If SKIP_DEPS_GET=true -> never run it
  #   * If deps/phoenix (arbitrary representative dep) is missing OR mix.lock missing -> run it
  # This avoids unexpected repeated "Resolving Hex dependencies" noise during normal dev cycles.
  defp maybe_deps_get(_args) do
    skip? = System.get_env("SKIP_DEPS_GET") == "true"
    lock_missing? = !File.exists?("mix.lock")
    phoenix_dep_missing? = !File.dir?("deps/phoenix")

    cond do
      skip? ->
        Mix.shell().info("[setup] Skipping deps.get (SKIP_DEPS_GET=true)")
      lock_missing? or phoenix_dep_missing? ->
        Mix.shell().info("[setup] Running deps.get (dependencies missing)")
        Mix.Task.run("deps.get", [])
      true ->
        Mix.shell().info("[setup] deps.get skipped (deps already present)")
    end
  end

  # Dialyzer configuration centralizes PLT location so CI cache & local dev share artifacts
  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/project.plt"},
      ignore_warnings: "dialyzer.ignore-warnings",
      list_unused_filters: true
    ]
  end
end
