defmodule Thunderline.Thunderbolt.CA.PerturbationTest do
  @moduledoc """
  Tests for HC-55 Perturbation Layer - SLiM-style decorrelation.
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.CA.Perturbation

  describe "configuration" do
    test "new/0 returns default config" do
      config = Perturbation.new()

      assert config.strategy == :gaussian
      assert config.sigma == 0.01
      assert config.dropout_p == 0.1
      assert config.adaptive == true
    end

    test "new/1 merges options" do
      config = Perturbation.new(strategy: :uniform, sigma: 0.05)

      assert config.strategy == :uniform
      assert config.sigma == 0.05
    end
  end

  describe "perturb/2" do
    test "gaussian perturbation adds noise" do
      config = Perturbation.new(strategy: :gaussian, sigma: 1.0, adaptive: false)

      results =
        for _ <- 1..100 do
          Perturbation.perturb(config, 0.0)
        end

      # Should have some variance
      mean = Enum.sum(results) / length(results)
      variance = Enum.map(results, fn x -> (x - mean) * (x - mean) end) |> Enum.sum()

      assert variance > 0
    end

    test "uniform perturbation stays in bounds" do
      config = Perturbation.new(strategy: :uniform, sigma: 1.0, adaptive: false)

      results =
        for _ <- 1..100 do
          Perturbation.perturb(config, 0.0)
        end

      assert Enum.all?(results, fn x -> x >= -1.0 and x <= 1.0 end)
    end

    test "salt_pepper perturbation produces binary noise" do
      config = Perturbation.new(strategy: :salt_pepper, sigma: 1.0, adaptive: false)

      results =
        for _ <- 1..100 do
          Perturbation.perturb(config, 0.0)
        end

      # Should only have +1.0 or -1.0 values
      assert Enum.all?(results, fn x -> x == 1.0 or x == -1.0 end)
    end
  end

  describe "perturb_list/2" do
    test "perturbs all elements" do
      config = Perturbation.new(strategy: :gaussian, sigma: 0.5, adaptive: false)
      values = [1.0, 2.0, 3.0, 4.0, 5.0]

      result = Perturbation.perturb_list(config, values)

      assert length(result) == 5
      # At least some should be different (with high probability)
      differences = Enum.zip(values, result) |> Enum.count(fn {v, r} -> v != r end)
      assert differences > 0
    end
  end

  describe "perturb_grid/2" do
    test "perturbs 2D grid" do
      config = Perturbation.new(strategy: :gaussian, sigma: 0.5, adaptive: false)
      grid = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]

      result = Perturbation.perturb_grid(config, grid)

      assert length(result) == 3
      assert Enum.all?(result, &(length(&1) == 2))
    end
  end

  describe "perturb_binary/2" do
    test "flips some bits" do
      config = Perturbation.new(sigma: 0.3, adaptive: false)
      states = [0, 1, 0, 1, 0, 1, 0, 1]

      results =
        for _ <- 1..50 do
          Perturbation.perturb_binary(config, states)
        end

      # At least one result should have flipped bits
      has_flips = Enum.any?(results, fn r ->
        Enum.zip(states, r) |> Enum.any?(fn {s, r} -> s != r end)
      end)

      assert has_flips
    end

    test "maintains binary values" do
      config = Perturbation.new(sigma: 0.5, adaptive: false)
      states = [0, 1, 0, 1]

      result = Perturbation.perturb_binary(config, states)

      assert Enum.all?(result, fn x -> x == 0 or x == 1 end)
    end
  end

  describe "dropout/2" do
    test "zeros some values" do
      config = Perturbation.new(dropout_p: 0.5)
      values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]

      results =
        for _ <- 1..20 do
          Perturbation.dropout(config, values)
        end

      # At least one result should have zeros
      has_zeros = Enum.any?(results, fn r -> Enum.member?(r, 0.0) end)
      assert has_zeros
    end
  end

  describe "perturb_layer/3" do
    test "applies depth-dependent scaling" do
      config = Perturbation.new(sigma: 0.1, adaptive: false)
      values = [1.0, 1.0, 1.0, 1.0]

      # Earlier layer
      early_results =
        for _ <- 1..100 do
          Perturbation.perturb_layer(config, values, layer_index: 0, total_layers: 10)
        end

      # Later layer
      late_results =
        for _ <- 1..100 do
          Perturbation.perturb_layer(config, values, layer_index: 9, total_layers: 10)
        end

      # Compute variance
      early_variance = compute_variance(List.flatten(early_results))
      late_variance = compute_variance(List.flatten(late_results))

      # Later layers should have higher variance
      assert late_variance > early_variance
    end
  end

  describe "correlation/2" do
    test "returns 1.0 for identical vectors" do
      xs = [1.0, 2.0, 3.0, 4.0, 5.0]
      corr = Perturbation.correlation(xs, xs)

      assert_in_delta corr, 1.0, 0.001
    end

    test "returns -1.0 for perfectly anticorrelated vectors" do
      xs = [1.0, 2.0, 3.0, 4.0, 5.0]
      ys = [5.0, 4.0, 3.0, 2.0, 1.0]
      corr = Perturbation.correlation(xs, ys)

      assert_in_delta corr, -1.0, 0.001
    end

    test "returns ~0 for uncorrelated vectors" do
      xs = [1.0, 2.0, 3.0, 4.0, 5.0]
      ys = [3.0, 1.0, 4.0, 2.0, 5.0]
      corr = Perturbation.correlation(xs, ys)

      # Should be low but not necessarily 0
      assert abs(corr) < 0.5
    end
  end

  describe "decorrelation_score/2" do
    test "returns 0 for identical vectors" do
      xs = [1.0, 2.0, 3.0]
      score = Perturbation.decorrelation_score(xs, xs)

      assert_in_delta score, 0.0, 0.001
    end

    test "returns high score for well-decorrelated vectors" do
      xs = [1.0, 2.0, 3.0, 4.0, 5.0]
      # Random perturbation should decorrelate
      ys = [2.5, 1.1, 4.2, 3.8, 2.0]
      score = Perturbation.decorrelation_score(xs, ys)

      assert score > 0.5
    end
  end

  describe "telemetry" do
    test "emits perturbation telemetry" do
      test_pid = self()

      :telemetry.attach(
        "test-perturb",
        [:thunderline, :bolt, :ca, :perturbation],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:perturbation_telemetry, measurements, metadata})
        end,
        nil
      )

      config = Perturbation.new(adaptive: false)
      Perturbation.perturb(config, 1.0)

      assert_receive {:perturbation_telemetry, measurements, metadata}, 1000

      assert is_float(measurements.sigma)
      assert metadata.mode == :scalar

      :telemetry.detach("test-perturb")
    end
  end

  # Helper function
  defp compute_variance(values) do
    n = length(values)
    mean = Enum.sum(values) / n
    Enum.map(values, fn x -> (x - mean) * (x - mean) end) |> Enum.sum() |> Kernel./(n)
  end
end
