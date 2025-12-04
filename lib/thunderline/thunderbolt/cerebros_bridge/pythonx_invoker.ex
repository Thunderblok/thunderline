defmodule Thunderline.Thunderbolt.CerebrosBridge.PythonxInvoker do
  @moduledoc """
  DEPRECATED: Pythonx-based Cerebros bridge invoker.

  This module is deprecated in favor of SnexInvoker which provides GIL-free
  Python execution. The Pythonx library is no longer a dependency.

  Use SnexInvoker instead:

      config :thunderline, :cerebros_bridge,
        invoker: :snex,  # Default, GIL-free Python
        python_path: ["python/cerebros", "python/cerebros/core", "python/cerebros/service"]

  This module is kept for API compatibility but all functions return {:error, :deprecated}.
  """

  require Logger

  @deprecated "Use SnexInvoker instead"
  def init do
    Logger.warning("[PythonxInvoker] DEPRECATED - Use SnexInvoker instead")
    {:error, :deprecated}
  end

  @deprecated "Use SnexInvoker instead"
  def invoke(_op, _call_spec, _opts \\ []), do: {:error, :deprecated}

  @deprecated "Use SnexInvoker instead"
  def run_nas(_params), do: {:error, :deprecated}

  @deprecated "Use SnexInvoker instead"
  def run_nas(_params, _opts), do: {:error, :deprecated}

  @deprecated "Use SnexInvoker instead"
  def health_check, do: {:error, :deprecated}

  @deprecated "Use SnexInvoker instead"
  def shutdown, do: {:error, :deprecated}
end
