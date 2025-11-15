defmodule Thunderline.Thunderbolt.CerebrosBridge.ValidatorTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.CerebrosBridge.Validator

  setup do
    original_features = Application.get_env(:thunderline, :features)
    original_config = Application.get_env(:thunderline, :cerebros_bridge)

    on_exit(fn ->
      Application.put_env(:thunderline, :features, original_features)
      Application.put_env(:thunderline, :cerebros_bridge, original_config)
    end)

    :ok
  end

  test "validate returns ok when all checks pass" do
    tmp = temp_dir()
    script = Path.join(tmp, "bridge.py")
    python_mock = Path.join(tmp, "python-mock.sh")
    File.write!(script, "print('hello world')\n")
    File.write!(python_mock, "#!/bin/sh\nexit 0\n")
    File.chmod!(python_mock, 0o755)
    File.write!(Path.join(tmp, "VERSION"), "0.0.1\n")

    Application.put_env(:thunderline, :features, [:ml_nas])

    Application.put_env(:thunderline, :cerebros_bridge,
      enabled: true,
      repo_path: tmp,
      script_path: script,
      python_executable: python_mock,
      working_dir: tmp,
      invoke: [default_timeout_ms: 1000, max_retries: 0, retry_backoff_ms: 10],
      env: %{"PYTHONUNBUFFERED" => "1"},
      cache: [enabled: true, ttl_ms: 1000, max_entries: 16]
    )

    assert %{status: :ok, checks: checks} = Validator.validate()
    assert Enum.all?(checks, fn check -> check.status in [:ok, :warning] end)
  end

  test "missing feature flag produces error" do
    tmp = temp_dir()
    Application.put_env(:thunderline, :features, [])

    Application.put_env(:thunderline, :cerebros_bridge,
      enabled: true,
      repo_path: tmp,
      script_path: Path.join(tmp, "missing.py"),
      python_executable: "nonexistent-exec",
      cache: [enabled: false]
    )

    assert %{status: :error, checks: checks} = Validator.validate()

    assert Enum.any?(checks, fn %{name: name, status: status} ->
             name == :feature_flag and status == :error
           end)
  end

  test "require_enabled enforces config flag" do
    tmp = temp_dir()
    Application.put_env(:thunderline, :features, [:ml_nas])

    Application.put_env(:thunderline, :cerebros_bridge,
      enabled: false,
      repo_path: tmp,
      script_path: Path.join(tmp, "script.py"),
      python_executable: "nonexistent"
    )

    assert %{status: :error, checks: checks} = Validator.validate(require_enabled?: true)

    assert Enum.any?(checks, fn %{name: name, status: status} ->
             name == :config_enabled and status == :error
           end)
  end

  defp temp_dir do
    path = Path.join(System.tmp_dir!(), "thunderline-validator-test-" <> random_suffix())
    File.mkdir_p!(path)
    path
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end
end
