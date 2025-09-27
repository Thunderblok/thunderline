defmodule Thunderline.CerebrosBridge.InvokerTest do
  # Mutates Application env; must not be async to avoid races
  use ExUnit.Case, async: false
  alias Thunderline.Thunderbolt.CerebrosBridge.Invoker

  setup do
    original_flags = Application.get_env(:thunderline, :features, [])
    original_bridge = Application.get_env(:thunderline, :cerebros_bridge)

    maybe_start_task_supervisor()

    on_exit(fn ->
      Application.put_env(:thunderline, :features, original_flags)

      case original_bridge do
        nil -> Application.delete_env(:thunderline, :cerebros_bridge)
        value -> Application.put_env(:thunderline, :cerebros_bridge, value)
      end
    end)

    :ok
  end

  defp maybe_start_task_supervisor do
    case Process.whereis(Thunderline.TaskSupervisor) do
      nil ->
        {:ok, _pid} = start_supervised({Task.Supervisor, name: Thunderline.TaskSupervisor})
        :ok

      _pid ->
        :ok
    end
  end

  test "invoke returns disabled error when flag off" do
    Application.put_env(:thunderline, :features, [])
    Application.put_env(:thunderline, :cerebros_bridge, enabled: false)

    assert {:error, %{class: :dependency}} =
             Invoker.invoke(:foo, %{command: "echo", args: [], env: %{}, expect_json?: false})
  end

  test "invoke echoes args when enabled" do
    Application.put_env(:thunderline, :features, [:ml_nas])

    Application.put_env(:thunderline, :cerebros_bridge,
      enabled: true,
      env: %{},
      invoke: [default_timeout_ms: 1_000, max_retries: 0, retry_backoff_ms: 0]
    )

    call_spec = %{
      command: "echo",
      args: [~s({"echo":{"a":1}})],
      env: %{},
      expect_json?: true
    }

    assert {:ok, result} = Invoker.invoke(:echo, call_spec)
    assert result.parsed == %{"echo" => %{"a" => 1}}
  end
end
