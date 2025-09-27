# config/releases.exs
import Config

config :thunderline, :features,
  ml_nas: true,
  cerebros_bridge: true

config :thunderline, :cerebros_bridge,
  enabled: true,
  python_executable: System.get_env("CEREBROS_PYTHON") || "python3",
  script_path: System.fetch_env!("CEREBROS_SCRIPT"),
  repo_path: System.get_env("CEREBROS_REPO"),
  working_dir: System.get_env("CEREBROS_WORKDIR"),
  env: %{
    "PYTHONUNBUFFERED" => "1",
    "MLFLOW_TRACKING_URI" => System.get_env("MLFLOW_TRACKING_URI")
  }
