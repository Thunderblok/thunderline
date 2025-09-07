defmodule Thunderline.CerebrosBridge.InvokerTest do
  # Mutates Application env; must not be async to avoid races
  use ExUnit.Case, async: false
  alias Thunderline.Thunderbolt.CerebrosBridge.Invoker

  setup do
    original_flags = Application.get_env(:thunderline, :features, [])
    on_exit(fn -> Application.put_env(:thunderline, :features, original_flags) end)
    :ok
  end

  test "invoke returns disabled error when flag off" do
    Application.put_env(:thunderline, :features, [])
    assert {:error, %{class: :dependency}} = Invoker.invoke(:foo, %{a: 1})
  end

  test "invoke echoes args when enabled" do
    Application.put_env(:thunderline, :features, [:cerebros_bridge])
    assert {:ok, %{echo: %{a: 1}}} = Invoker.invoke(:echo, %{a: 1})
  end
end
