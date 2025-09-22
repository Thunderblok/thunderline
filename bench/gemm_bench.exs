Mix.install([
  {:benchee, "~> 1.3"}
])

alias Thunderline.Thunderbolt.Numerics

m = 64
k = 64
n = 64

a = for _ <- 1..m, do: (for _ <- 1..k, do: :rand.uniform())
b = for _ <- 1..k, do: (for _ <- 1..n, do: :rand.uniform())

Benchee.run(%{
  "fallback" => fn -> Numerics.gemm_fp16_acc32(a, b) end
})
