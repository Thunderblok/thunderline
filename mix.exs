defmodule Thunderline.MixProject do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :thunderline,
      version: @version,
      # Bump Elixir version to support Jido ecosystem (requires >= 1.18 for ash_jido)
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Use default Mix compilers (was restricted to [:elixir, :app] which can skip needed steps)
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.github": :test
      ],
      consolidate_protocols: Mix.env() != :dev,
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      mod: {Thunderline.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :ssl]
    ]
  end

  # Compile only core lib/ by default. Experimental former BOnus modules have been
  # migrated into proper domain folders under lib/thunderline/* so we no longer
  # need to add a separate BOnus path.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    base = [
      {:mdex, "~> 0.7"},
      {:usage_rules, "~> 0.1", only: [:dev]},
      # igniter:deps-start
      {:oban, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:bcrypt_elixir, "~> 3.1"},
      {:igniter, "~> 0.6"},
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
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.0"},
      # OpenTelemetry (align versions to avoid conflicts)
      {:opentelemetry, "~> 1.4"},
      {:opentelemetry_exporter, "~> 1.8", only: :prod},
      {:opentelemetry_phoenix, "~> 1.2"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_oban, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:pythonx, "~> 0.4.0"},
      {:venomous, "~> 0.7"},
      {:swoosh, "~> 1.16"},
      # Ash Framework
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_cloak, "~> 0.1.6"},
      {:ash_postgres, "~> 2.0"},
      {:ash_graphql, "~> 1.0"},
      {:ash_rate_limiter, "~> 0.1.1"},
      {:ash_json_api, "~> 1.0"},
      {:ash_oban, "~> 0.4"},
      {:ash_events, "~> 0.4.3"},
      {:opentelemetry_ash, "~> 0.1.3"},
      {:ash_state_machine, "~> 0.2.12"},
      {:ash_admin, "~> 0.11"},
      {:ash_ai, "~> 0.2"},
      # Type-safe TS client & RPC bridge
      {:ash_typescript, github: "ash-project/ash_typescript", ref: "main"},
      # Additional deps
      {:uuid, "~> 1.1"},
      {:broadway, "~> 1.0"},
      {:picosat_elixir, "~> 0.2"},
      {:sourceror, "~> 1.10"},
      {:iterex, "~> 0.1.2"},
      {:off_broadway_memory, "~> 1.1"},
      {:off_broadway_amqp10, "~> 0.1"},
      {:flow, "~> 1.0"},
      {:timex, "~> 3.7"},
      {:ex_webrtc, "~> 0.13.0"},
      {:ex_sctp, "~> 0.1.2"},
      {:reactor, "~> 0.15.6"},
      {:eagl, "~> 0.9.0"},
      {:simple_sat, "~> 0.1.3"},
      {:stb_image, "~> 0.6"},
      {:ex_rose_tree, "~> 0.1.3"},
      # Native and benchmarking
      {:rustler, "~> 0.36"},
      {:benchee, "~> 1.3", only: [:dev]},
      {:nimble_parsec, "~> 1.4"},
      {:yamerl, "~> 0.10"},
      # Memory & Security
      {:memento, "~> 0.5.0"},
      {:cloak, "~> 1.1"},
      # Crypto / JOSE (Ed25519 capability & policy signature stack)
      {:jose, "~> 1.11"},
      # ECS & GraphQL
      {:ecsx, "~> 0.5"},
      {:absinthe, "~> 1.7"},
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_plug, "~> 1.5"},
      # Neural / ML
      {:nx, "~> 0.9"},
      {:axon, "~> 0.7"},
      {:exla, "~> 0.9"},
      {:torchx, "~> 0.9"},
      {:bumblebee, "~> 0.6"},
      {:polaris, "~> 0.1"},
      # Agents (non-Jido runtime deps live above; Jido ecosystem is added below via git)
      # File system watch (dev/test only)
      {:file_system, "~> 1.0"},
      # Code Quality
      # credo required unscoped because upstream jido pulls it without :only restriction
      {:credo, "~> 1.7", override: true},
      {:excoveralls, "~> 0.18", only: [:test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.6.1", only: [:dev]}
      # Optional Cerebros local toolkit (enable with ENABLE_CEREBROS=1 if available)
      # If you do not have the local path or hex package, leave this commented or remove.
      # Using a runtime flag so it won't start unless explicitly enabled.
      # {:cerebros, "~> 0.1", only: [:dev], runtime: System.get_env("ENABLE_CEREBROS") in ["1","true","TRUE"]}
      # igniter:deps-end
    ]

    # --- Jido Agent Runtime Integration -----------------------------------
    # The Jido ecosystem packages are not (all) published on Hex under these names yet.
    # We source them directly from GitHub. Pin to tags where possible for reproducibility.
    # If tags ever change, fall back to :ref => "main" but expect occasional breakage.
    # TODO(fork): Repoint these to organization forks (Thunderblok/*) to persist local patches.
    jido_git_deps = [
      # Use latest available pre-release tag for jido (v1.1.0-rc.1)
      {:jido, github: "agentjido/jido", tag: "v1.1.0-rc.1", override: true},
      {:jido_action, github: "agentjido/jido_action", ref: "main", override: true},
      # Keep jido_signal on main until a matching release tag supports rc.1 struct shape
      {:jido_signal, github: "agentjido/jido_signal", ref: "main", override: true},
      {:jido_behaviortree, github: "agentjido/jido_behaviortree", ref: "main", override: true}
    ]

    # ash_jido currently targets newer Ash & Elixir; include only if the
    # running compiler version satisfies its stated requirement (>= 1.18) to avoid
    # blocking other dependency resolution. You can force include by exporting
    # INCLUDE_ASH_JIDO=1 (and upgrading your Elixir toolchain).
    ash_jido_dep =
      if System.get_env("INCLUDE_ASH_JIDO") in ["1", "true"] or
           Version.match?(
             System.version(),
             ">= 1.18.0"
           ) do
        [{:ash_jido, github: "agentjido/ash_jido", ref: "main", override: true}]
      else
        []
      end

    base ++ jido_git_deps ++ ash_jido_dep
  end

  defp aliases do
    [
      # setup no longer unconditionally runs "deps.get". We only fetch deps if:
      #  1. SKIP_DEPS_GET env var is NOT set to true, AND
      #  2. We detect a missing representative dependency folder (phoenix) or lock file.
      # This prevents surprise re-resolution of deps during iterative dev where you just want
      # migrations/assets. Force with `mix deps.get` manually when you really intend it.
      setup: [
        &maybe_deps_get/1,
        "ash.setup",
        "assets.setup",
        "assets.build",
        "run priv/repo/seeds.exs"
      ],
      # Allow skipping ash.setup in tests to run fast, DB-less component/unit tests
      # Provide a non-recursive alias to run full test setup + tests.
      "test.all": [&maybe_ash_setup/1, "test"],
      # One-shot resource -> migration -> migrate convenience
      "ash.migrate": ["ash_postgres.generate_migrations", "ecto.migrate"],
      # Option A (no esbuild/node): only Tailwind profile 'thunderline'
      "assets.setup": ["tailwind.install --if-missing"],
      "assets.build": ["tailwind thunderline", "esbuild thunderline"],
      "assets.deploy": [
        "tailwind thunderline --minify",
        "esbuild thunderline --minify",
        "phx.digest"
      ],
      # WARHORSE lint bundle (Phase1 advisory)
      lint: ["format --check-formatted", "credo --strict"],
      test: ["ash.setup --quiet", "test"]
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

  # (dynamic cerebros injection removed for Igniter compatibility; add manually if needed)
end
