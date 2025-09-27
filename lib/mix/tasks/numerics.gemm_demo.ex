defmodule Mix.Tasks.Numerics.GemmDemo do
  use Mix.Task
  @shortdoc "Run a quick GEMM demo through configured adapter"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    alias Thunderline.Thunderbolt.Numerics

    a = for _ <- 1..4, do: for(_ <- 1..4, do: :rand.uniform())
    b = for _ <- 1..4, do: for(_ <- 1..4, do: :rand.uniform())

    case Numerics.gemm_fp16_acc32(a, b) do
      {:ok, res} -> IO.puts("GEMM ok: #{inspect(hd(res))} ...")
      {:error, err} -> IO.puts("GEMM error: #{inspect(err)}")
    end
  end
end
