defmodule Thunderline.Thunderbolt.CerebrosBridge.Invoker do
  @moduledoc "Uniform invoke wrapper with telemetry + timeout (stub implementation)."
  alias Thunderline.Thunderbolt.CerebrosBridge.Client
  alias Thunderline.Thunderbolt.CerebrosBridge.Translator
  require Logger

  @tele_base [:cerebros, :bridge, :invoke]

  @spec invoke(atom, term, keyword) :: {:ok, term} | {:error, map}
  def invoke(op, args, opts \\ []) do
    if not Client.enabled?() do
      return_disabled(op, args)
    else
      meta = %{op: op, t0: System.monotonic_time(:millisecond)}
      :telemetry.execute(@tele_base ++ [:start], %{}, meta)

      timeout =
        opts[:timeout_ms] ||
          get_in(Application.get_env(:thunderline, :cerebros_bridge, []), [:invoke, :default_timeout_ms]) ||
          5_000

      task = Task.async(fn -> do_invoke(op, Translator.encode(args)) end)

      try do
        res = Task.await(task, timeout)
        :telemetry.execute(@tele_base ++ [:stop], %{duration_ms: elapsed(meta)}, Map.put(meta, :ok, true))
        Translator.decode(res)
      catch
        :exit, {:timeout, _} ->
          err = %{class: :timeout, origin: :cerebros}
          :telemetry.execute(@tele_base ++ [:exception], %{}, Map.put(meta, :error, err))
          {:error, err}
      rescue
        e ->
          err = %{class: :exception, origin: :cerebros, raw: Exception.message(e)}
          :telemetry.execute(@tele_base ++ [:exception], %{}, Map.put(meta, :error, err))
          {:error, err}
      end
    end
  end

  defp return_disabled(op, _args),
    do: {:error, %{class: :dependency, origin: :system, message: "cerebros_bridge disabled", op: op}}

  # Stub: replace with actual external invocation (e.g., Port/RPC/NIF) later
  defp do_invoke(_op, encoded_args), do: {:ok, %{echo: encoded_args}}

  defp elapsed(meta),
    do: System.monotonic_time(:millisecond) - Map.get(meta, :t0, System.monotonic_time(:millisecond))
end
