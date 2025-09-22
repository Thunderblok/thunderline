defmodule Mix.Tasks.Thunderline.Cerebros.Demo do
  use Mix.Task

  @shortdoc "Run the Cerebros generative demo script from Thunderline (mirrors Cerebros MLflow pattern)"
  @moduledoc """
  Runs the Cerebros generative proof-of-concept script from within Thunderline, mirroring
  how Cerebros spins up MLflow locally (file-backed tracking by default).

  By default this task will:
  - Resolve the Cerebros repo root (../cerebros-core-algorithm-alpha relative to Thunderline)
  - Set MLFLOW_TRACKING_URI to `file:<repo>/mlruns` if it's not already set
  - Invoke the Python script:
      generative-proof-of-concept-CPU-preprocessing-in-memory.py

  Options:
    --python <path>   : Python interpreter (default: "python3")
    --repo <path>     : Path to cerebros-core-algorithm-alpha (default: ../cerebros-core-algorithm-alpha)
    --mlflow <uri>    : Override MLFLOW_TRACKING_URI (e.g., http://127.0.0.1:5000)
    --                 : All args after -- will be passed to the Python script

  Examples:
    mix thunderline.cerebros.demo
    mix thunderline.cerebros.demo --python /usr/bin/python3.11
    mix thunderline.cerebros.demo --mlflow http://127.0.0.1:5000
    mix thunderline.cerebros.demo --repo /home/mo/DEV/cerebros-core-algorithm-alpha
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
    default_repo = Path.expand("../cerebros-core-algorithm-alpha", cwd)
    repo = opts[:repo] || default_repo

    script =
      Path.join(repo, "generative-proof-of-concept-CPU-preprocessing-in-memory.py")
      |> Path.expand()

    unless File.exists?(script) do
      Mix.raise("""
      Cerebros demo script not found:

        #{script}

      Specify a repo with --repo <path> if your cerebros-core-algorithm-alpha is elsewhere.
      """)
    end

    python = opts[:python] || "python3"

    # MLflow tracking URI: mirror Cerebros default if not already defined
    mlflow_uri =
      cond do
        is_binary(opts[:mlflow]) and opts[:mlflow] != "" ->
          opts[:mlflow]

        is_binary(System.get_env("MLFLOW_TRACKING_URI")) and System.get_env("MLFLOW_TRACKING_URI") != "" ->
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
    {status, exit_code} =
      run_streaming(cmd, args, env: env, cd: repo)

    case status do
      :ok ->
        Mix.shell().info("[done] Cerebros demo completed with exit code #{exit_code}")
        :ok

      {:error, reason} ->
        Mix.raise("Cerebros demo failed: #{inspect(reason)}")
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
            System.cmd(cmd, args,
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
