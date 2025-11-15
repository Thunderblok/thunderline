defmodule Thunderline.Thunderbolt.ML.DistanceTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.ML.Distance

  # ──────────────────────────────────────────────────────────────────────
  # Setup & Helpers
  # ──────────────────────────────────────────────────────────────────────

  @eps 1.0e-9
  @tolerance 1.0e-6

  defp close_enough?(a, b, tol \\ @tolerance) do
    abs(a - b) < tol
  end

  # Helper to check if a float is NaN (x != x is the IEEE trick)
  defp is_nan?(x) when is_float(x), do: x != x
  defp is_nan?(_), do: false

  # Helper to check if a float is infinite
  defp is_infinite?(x) when is_float(x) do
    x == :infinity or x == :neg_infinity or abs(x) > 1.0e308
  end
  defp is_infinite?(_), do: false

  # ──────────────────────────────────────────────────────────────────────
  # KL Divergence Tests
  # ──────────────────────────────────────────────────────────────────────

  describe "kl_divergence/2" do
    test "identical distributions → KL ≈ 0" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.4, 0.3, 0.3])

      kl = Distance.kl_divergence(p, q)
      assert close_enough?(kl, 0.0, @tolerance)
    end

    test "orthogonal distributions → large KL" do
      p = Nx.tensor([1.0, 0.0])
      q = Nx.tensor([0.0, 1.0])

      kl = Distance.kl_divergence(p, q)
      # After normalization and epsilon smoothing, should be finite but large
      assert kl > 10.0
      assert is_float(kl)
      refute is_nan?(kl)
      refute is_infinite?(kl)
    end

    test "slightly different distributions → small positive KL" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      kl = Distance.kl_divergence(p, q)
      assert kl > 0.0
      assert kl < 0.1
    end

    test "non-normalized inputs are normalized automatically" do
      p = Nx.tensor([2.0, 1.5, 1.5])  # sum = 5.0
      q = Nx.tensor([2.0, 1.5, 1.5])

      kl = Distance.kl_divergence(p, q)
      assert close_enough?(kl, 0.0, @tolerance)
    end

    test "handles negative values by clamping to zero" do
      p = Nx.tensor([0.5, 0.3, -0.1, 0.3])
      q = Nx.tensor([0.4, 0.35, 0.1, 0.15])

      kl = Distance.kl_divergence(p, q)
      assert is_float(kl)
      refute is_nan?(kl)
      refute is_infinite?(kl)
    end

    test "all-zero distributions are handled gracefully" do
      p = Nx.tensor([0.0, 0.0, 0.0])
      q = Nx.tensor([0.0, 0.0, 0.0])

      kl = Distance.kl_divergence(p, q)
      # After normalization with epsilon, should be finite
      assert is_float(kl)
      refute is_nan?(kl)
      refute is_infinite?(kl)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Cross-Entropy Tests
  # ──────────────────────────────────────────────────────────────────────

  describe "cross_entropy/2" do
    test "identical distributions → H(P, P) = H(P)" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.4, 0.3, 0.3])

      h = Distance.cross_entropy(p, q)
      # Should be the entropy of P
      assert h > 0.0
      assert h < 2.0  # Reasonable range for 3-bin distribution
    end

    test "cross-entropy is always ≥ entropy (H(P, Q) ≥ H(P, P))" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      h_pp = Distance.cross_entropy(p, p)
      h_pq = Distance.cross_entropy(p, q)

      assert h_pq >= h_pp - @tolerance
    end

    test "orthogonal distributions → large cross-entropy" do
      p = Nx.tensor([1.0, 0.0])
      q = Nx.tensor([0.0, 1.0])

      h = Distance.cross_entropy(p, q)
      # After epsilon smoothing, should be finite but large
      assert h > 10.0
      assert is_float(h)
      refute is_nan?(h)
    end

    test "non-normalized inputs are normalized" do
      p = Nx.tensor([2.0, 1.5, 1.5])
      q = Nx.tensor([2.0, 1.5, 1.5])

      h = Distance.cross_entropy(p, q)
      assert h > 0.0
      refute is_nan?(h)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Hellinger Distance Tests
  # ──────────────────────────────────────────────────────────────────────

  describe "hellinger/2" do
    test "identical distributions → Hellinger = 0" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.4, 0.3, 0.3])

      h = Distance.hellinger(p, q)
      assert close_enough?(h, 0.0, @tolerance)
    end

    test "orthogonal distributions → Hellinger ≈ 1" do
      p = Nx.tensor([1.0, 0.0])
      q = Nx.tensor([0.0, 1.0])

      h = Distance.hellinger(p, q)
      # After epsilon smoothing, should be close to 1
      assert h > 0.9
      assert h <= 1.0
    end

    test "Hellinger is symmetric (H(P, Q) = H(Q, P))" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      h_pq = Distance.hellinger(p, q)
      h_qp = Distance.hellinger(q, p)

      assert close_enough?(h_pq, h_qp, @tolerance)
    end

    test "Hellinger is bounded [0, 1]" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.1, 0.6, 0.3])

      h = Distance.hellinger(p, q)
      assert h >= 0.0
      assert h <= 1.0
    end

    test "non-normalized inputs are normalized" do
      p = Nx.tensor([2.0, 1.5, 1.5])
      q = Nx.tensor([2.0, 1.5, 1.5])

      h = Distance.hellinger(p, q)
      assert close_enough?(h, 0.0, @tolerance)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Jensen-Shannon Divergence Tests
  # ──────────────────────────────────────────────────────────────────────

  describe "js_divergence/2" do
    test "identical distributions → JS = 0" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.4, 0.3, 0.3])

      js = Distance.js_divergence(p, q)
      assert close_enough?(js, 0.0, @tolerance)
    end

    test "orthogonal distributions → JS bounded" do
      p = Nx.tensor([1.0, 0.0])
      q = Nx.tensor([0.0, 1.0])

      js = Distance.js_divergence(p, q)
      # JS is bounded, should be close to log(2) ≈ 0.693 with natural log
      assert js > 0.5
      assert js < 1.0
      refute is_nan?(js)
    end

    test "JS is symmetric (JS(P, Q) = JS(Q, P))" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      js_pq = Distance.js_divergence(p, q)
      js_qp = Distance.js_divergence(q, p)

      assert close_enough?(js_pq, js_qp, @tolerance)
    end

    test "JS is less than KL (JS(P, Q) ≤ 0.5 * (KL(P||Q) + KL(Q||P)))" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      js = Distance.js_divergence(p, q)
      kl_pq = Distance.kl_divergence(p, q)
      kl_qp = Distance.kl_divergence(q, p)

      # JS should be ≤ symmetric KL (by construction)
      assert js <= 0.5 * (kl_pq + kl_qp) + @tolerance
    end

    test "non-normalized inputs are normalized" do
      p = Nx.tensor([2.0, 1.5, 1.5])
      q = Nx.tensor([2.0, 1.5, 1.5])

      js = Distance.js_divergence(p, q)
      assert close_enough?(js, 0.0, @tolerance)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # all_metrics/2 Tests
  # ──────────────────────────────────────────────────────────────────────

  describe "all_metrics/2" do
    test "returns map with all 4 metrics" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      metrics = Distance.all_metrics(p, q)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :kl_divergence)
      assert Map.has_key?(metrics, :cross_entropy)
      assert Map.has_key?(metrics, :hellinger)
      assert Map.has_key?(metrics, :js_divergence)
    end

    test "all metrics are floats" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      metrics = Distance.all_metrics(p, q)

      assert is_float(metrics.kl_divergence)
      assert is_float(metrics.cross_entropy)
      assert is_float(metrics.hellinger)
      assert is_float(metrics.js_divergence)
    end

    test "matches individual metric computations" do
      p = Nx.tensor([0.5, 0.3, 0.2])
      q = Nx.tensor([0.4, 0.35, 0.25])

      metrics = Distance.all_metrics(p, q)

      kl = Distance.kl_divergence(p, q)
      h_pq = Distance.cross_entropy(p, q)
      hellinger = Distance.hellinger(p, q)
      js = Distance.js_divergence(p, q)

      assert close_enough?(metrics.kl_divergence, kl, @tolerance)
      assert close_enough?(metrics.cross_entropy, h_pq, @tolerance)
      assert close_enough?(metrics.hellinger, hellinger, @tolerance)
      assert close_enough?(metrics.js_divergence, js, @tolerance)
    end

    test "identical distributions → all near zero (except cross_entropy)" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.4, 0.3, 0.3])

      metrics = Distance.all_metrics(p, q)

      assert close_enough?(metrics.kl_divergence, 0.0, @tolerance)
      assert metrics.cross_entropy > 0.0  # Entropy of P
      assert close_enough?(metrics.hellinger, 0.0, @tolerance)
      assert close_enough?(metrics.js_divergence, 0.0, @tolerance)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # validate_distributions/3 Tests
  # ──────────────────────────────────────────────────────────────────────

  describe "validate_distributions/3" do
    test "valid normalized distributions → :ok" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.3, 0.2])

      assert :ok = Distance.validate_distributions(p, q)
    end

    test "shape mismatch → error" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.5])

      assert {:error, msg} = Distance.validate_distributions(p, q)
      assert msg =~ "Shape mismatch"
    end

    test "negative values in P → error" do
      p = Nx.tensor([0.5, -0.1, 0.6])
      q = Nx.tensor([0.4, 0.3, 0.3])

      assert {:error, msg} = Distance.validate_distributions(p, q)
      assert msg =~ "negative values"
      assert msg =~ "P"
    end

    test "negative values in Q → error" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, -0.2, 0.7])

      assert {:error, msg} = Distance.validate_distributions(p, q)
      assert msg =~ "negative values"
      assert msg =~ "Q"
    end

    test "P not normalized → error" do
      p = Nx.tensor([0.5, 0.3, 0.1])  # sum = 0.9
      q = Nx.tensor([0.4, 0.3, 0.3])

      assert {:error, msg} = Distance.validate_distributions(p, q)
      assert msg =~ "not normalized"
      assert msg =~ "P"
    end

    test "Q not normalized → error" do
      p = Nx.tensor([0.4, 0.3, 0.3])
      q = Nx.tensor([0.5, 0.3, 0.1])  # sum = 0.9

      assert {:error, msg} = Distance.validate_distributions(p, q)
      assert msg =~ "not normalized"
      assert msg =~ "Q"
    end

    test "custom tolerance is respected" do
      p = Nx.tensor([0.4, 0.3, 0.29])  # sum = 0.99
      q = Nx.tensor([0.4, 0.3, 0.3])

      # With default tolerance (1e-6), should fail
      assert {:error, _} = Distance.validate_distributions(p, q)

      # With custom tolerance (1e-2), should pass
      assert :ok = Distance.validate_distributions(p, q, tolerance: 1.0e-2)
    end

    test "accepts normalized distributions within tolerance" do
      p = Nx.tensor([0.3333333, 0.3333333, 0.3333334])
      q = Nx.tensor([0.5, 0.25, 0.25])

      assert :ok = Distance.validate_distributions(p, q)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Edge Cases & Numerical Stability
  # ──────────────────────────────────────────────────────────────────────

  describe "numerical stability" do
    test "very small probabilities don't cause NaN" do
      p = Nx.tensor([0.99, 0.005, 0.005])
      q = Nx.tensor([0.005, 0.99, 0.005])

      metrics = Distance.all_metrics(p, q)

      refute is_nan?(metrics.kl_divergence)
      refute is_nan?(metrics.cross_entropy)
      refute is_nan?(metrics.hellinger)
      refute is_nan?(metrics.js_divergence)
    end

    test "all zeros are handled gracefully" do
      p = Nx.tensor([0.0, 0.0, 0.0])
      q = Nx.tensor([0.0, 0.0, 0.0])

      metrics = Distance.all_metrics(p, q)

      # After epsilon smoothing and normalization, should be finite
      refute is_nan?(metrics.kl_divergence)
      refute is_nan?(metrics.cross_entropy)
      refute is_nan?(metrics.hellinger)
      refute is_nan?(metrics.js_divergence)
    end

    test "large probability differences are handled" do
      p = Nx.tensor([0.999, 0.001])
      q = Nx.tensor([0.001, 0.999])

      metrics = Distance.all_metrics(p, q)

      # KL should be large but finite
      assert metrics.kl_divergence > 5.0
      refute is_infinite?(metrics.kl_divergence)

      # Hellinger should be close to 1
      assert metrics.hellinger > 0.9
      assert metrics.hellinger <= 1.0
    end

    test "single-bin distribution" do
      p = Nx.tensor([1.0])
      q = Nx.tensor([1.0])

      metrics = Distance.all_metrics(p, q)

      assert close_enough?(metrics.kl_divergence, 0.0, @tolerance)
      assert close_enough?(metrics.hellinger, 0.0, @tolerance)
      assert close_enough?(metrics.js_divergence, 0.0, @tolerance)
    end

    test "many bins (100) are handled efficiently" do
      # Uniform distribution
      p = Nx.broadcast(0.01, {100})
      q = Nx.broadcast(0.01, {100})

      metrics = Distance.all_metrics(p, q)

      assert close_enough?(metrics.kl_divergence, 0.0, @tolerance)
      assert close_enough?(metrics.hellinger, 0.0, @tolerance)
      assert close_enough?(metrics.js_divergence, 0.0, @tolerance)
    end
  end
end
