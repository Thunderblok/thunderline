# config/releases.exs
import Config

cerebros_enabled =
  case System.get_env("CEREBROS_ENABLED") do
    val when val in ["0", "false", "FALSE"] -> false
    val when val in ["1", "true", "TRUE"] -> true
    _ -> true
  end

rag_enabled =
  case System.get_env("RAG_ENABLED") do
    val when val in ["0", "false", "FALSE"] -> false
    val when val in ["1", "true", "TRUE"] -> true
    _ -> true
  end

config :thunderline, :features,
  ml_nas: cerebros_enabled,
  cerebros_bridge: cerebros_enabled,
  rag_enabled: rag_enabled

config :thunderline, :cerebros_bridge,
  enabled: cerebros_enabled,
  python_executable: System.get_env("CEREBROS_PYTHON") || "python3",
  script_path: System.fetch_env!("CEREBROS_SCRIPT"),
  repo_path: System.get_env("CEREBROS_REPO"),
  working_dir: System.get_env("CEREBROS_WORKDIR"),
  env: %{
    "PYTHONUNBUFFERED" => "1",
    "MLFLOW_TRACKING_URI" => System.get_env("MLFLOW_TRACKING_URI")
  }
