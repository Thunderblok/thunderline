defmodule Mix.Tasks.Thunderline.Cerebros.Demo do
  use Mix.Task

  @shortdoc "Run the Cerebros generative demo script from Thunderline (mirrors Cerebros MLflow pattern)"
  @moduledoc """
  Runs the Cerebros generative proof-of-concept script from within Thunderline, mirroring
  how Cerebros spins up MLflow locally (file-backed tracking by default).

  By default this task will:
  - Resolve the Cerebros root from python/cerebros (in-repo) or CEREBROS_REPO env
  - Set MLFLOW_TRACKING_URI to `file:<repo>/mlruns` if it's not already set
  - Invoke the Cerebros service via cerebros_service.py

  Options:
    --python <path>   : Python interpreter (default: "python3")
    --repo <path>     : Path to Cerebros root (default: python/cerebros or CEREBROS_REPO env)
    --mlflow <uri>    : Override MLFLOW_TRACKING_URI (e.g., http://127.0.0.1:5000)
    --                 : All args after -- will be passed to the Python script

  Examples:
    mix thunderline.cerebros.demo
    mix thunderline.cerebros.demo --python /usr/bin/python3.11
    mix thunderline.cerebros.demo --mlflow http://127.0.0.1:5000
    mix thunderline.cerebros.demo --repo /path/to/external/cerebros
    mix thunderline.cerebros.demo -- --epochs 2 --batch-size 16
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start", [])

    {opts, rest, _invalid} =
      OptionParser.parse(argv,
        switches: [
          python: :string,
          repo: :string,
          mlflow: :string
        ]
      )

    cwd = File.cwd!()
    # Default to in-repo python/cerebros, fall back to CEREBROS_REPO env or external path
    default_repo =
      case System.get_env("CEREBROS_REPO") do
        nil -> Path.join(cwd, "python/cerebros")
        env_path -> env_path
      end
    repo = opts[:repo] || default_repo

    # Look for cerebros_service.py (new structure) or fallback to legacy script
    script =
      cond do
        File.exists?(Path.join(repo, "service/cerebros_service.py")) ->
          Path.join(repo, "service/cerebros_service.py") |> Path.expand()
        File.exists?(Path.join(repo, "generative-proof-of-concept-CPU-preprocessing-in-memory.py")) ->
          Path.join(repo, "generative-proof-of-concept-CPU-preprocessing-in-memory.py") |> Path.expand()
        true ->
          Path.join(repo, "service/cerebros_service.py") |> Path.expand()
      end

    unless File.exists?(script) do
      Mix.raise("""
      Cerebros script not found:

        #{script}

      Tried locations:
        - #{Path.join(repo, "service/cerebros_service.py")}
        - #{Path.join(repo, "generative-proof-of-concept-CPU-preprocessing-in-memory.py")}

      Set CEREBROS_REPO env or use --repo <path> to specify the Cerebros location.
      """)
    end

    python = opts[:python] || "python3"

    # MLflow tracking URI: mirror Cerebros default if not already defined
    mlflow_uri =
      cond do
        is_binary(opts[:mlflow]) and opts[:mlflow] != "" ->
          opts[:mlflow]

        is_binary(System.get_env("MLFLOW_TRACKING_URI")) and
            System.get_env("MLFLOW_TRACKING_URI") != "" ->
          System.get_env("MLFLOW_TRACKING_URI")

        true ->
          "file:" <> Path.join(repo, "mlruns")
      end

    # Print banner
    Mix.shell().info("""
    [Cerebros Demo Runner]
      repo:   #{repo}
      script: #{script}
      python: #{python}
      MLFLOW_TRACKING_URI: #{mlflow_uri}
    """)

    # Friendly checks for Python deps (non-fatal)
    req = Path.join(repo, "requirements.txt")

    if File.exists?(req) do
      Mix.shell().info("[hint] Ensure Cerebros requirements are installed:")
      Mix.shell().info("       pip install -r #{req}")
    end

    # Pass-through args after option parsing
    passthrough_args = rest

    env =
      System.get_env()
      |> Map.put("MLFLOW_TRACKING_URI", mlflow_uri)

    {cmd, args} = {python, [script | passthrough_args]}

    Mix.shell().info("[exec] #{cmd} #{Enum.map_join(args, " ", &escape_arg/1)}")

    # Try Venomous first (managed Python workers); fallback to System.cmd streaming
    venomous_supported? =
      Code.ensure_loaded?(Venomous) and function_exported?(Venomous, :python, 2)

    result =
      if venomous_supported? do
        # Configure Venomous SnakeManager at runtime with our repo/script context
        snake_envvars = Enum.map(env, fn {k, v} -> {k, v} end)

        Application.put_env(:venomous, :snake_manager, %{
          python_opts: [
            module_paths: [repo],
            cd: repo,
            envvars: snake_envvars,
            python_executable: python
          ],
          snake_ttl_minutes: 5,
          perpetual_workers: 0
        })

        args_map = %Venomous.SnakeArgs{
          module: :venomous_bridge,
          func: :run_cerebros,
          args: [repo, script, python, passthrough_args, snake_envvars]
        }

        try do
          Venomous.python(args_map, python_timeout: 300_000)
        rescue
          _ -> :venomous_error
        end
      else
        :venomous_unavailable
      end

    case result do
      {:ok, %{"returncode" => 0}} ->
        Mix.shell().info("[done] Cerebros demo completed with exit code 0")
        :ok

      {:ok, %{"returncode" => code}} when is_integer(code) and code != 0 ->
        Mix.raise("Cerebros demo (venomous) exited non-zero: #{code}")

      {:ok, %{"error" => msg}} ->
        Mix.raise("Cerebros demo (venomous) failed: #{inspect(msg)}")

      _fallback ->
        # Fallback to direct System.cmd streaming
        case run_streaming(cmd, args, env: env, cd: repo) do
          {:ok, exit_code} ->
            if exit_code == 0 do
              Mix.shell().info("[done] Cerebros demo completed with exit code 0")
              :ok
            else
              Mix.raise("Cerebros demo exited non-zero: #{exit_code}")
            end

          {:error, reason} ->
            Mix.raise("Cerebros demo failed: #{inspect(reason)}")
        end
    end
  end

  defp escape_arg(arg) when is_binary(arg) do
    if String.contains?(arg, " ") do
      ~s("#{arg}")
    else
      arg
    end
  end

  defp run_streaming(cmd, args, opts) do
    parent = self()

    task =
      Task.async(fn ->
        try do
          {_, exit_code} =
            System.cmd(
              cmd,
              args,
              Keyword.merge(opts,
                into: IO.stream(:stdio, :line),
                stderr_to_stdout: true
              )
            )

          send(parent, {:cmd_exit, exit_code})
        rescue
          e -> send(parent, {:cmd_error, e})
        end
      end)

    receive do
      {:cmd_exit, code} -> {:ok, code}
      {:cmd_error, e} -> {:error, e}
    after
      60 * 60 * 1000 ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end
end
