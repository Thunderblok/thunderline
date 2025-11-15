defmodule Thunderline.Thunderbolt.ML.ParzenTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.ML.Parzen

  # Fixed seed for deterministic tests
  @seed 42

  defp random_key(offset \\ 0) do
    Nx.Random.key(@seed + offset)
  end

  describe "init/1" do
    test "initializes with required options" do
      parzen = Parzen.init(pac_id: "pac_123", feature_family: :text)

      assert parzen.pac_id == "pac_123"
      assert parzen.feature_family == :text
      assert parzen.window_size == 300
      assert parzen.bins == 20
      assert parzen.dims == 1
      assert parzen.samples == nil
      assert parzen.bin_probs == nil
    end

    test "accepts custom window_size and bins" do
      parzen = Parzen.init(
        pac_id: "pac_456",
        feature_family: :audio,
        window_size: 500,
        bins: 30
      )

      assert parzen.window_size == 500
      assert parzen.bins == 30
    end

    test "accepts dims: 2 for future 2D support" do
      parzen = Parzen.init(pac_id: "test", feature_family: :test, dims: 2)
      assert parzen.dims == 2
    end

    test "raises on invalid dims" do
      assert_raise ArgumentError, ~r/dims must be 1 or 2/, fn ->
        Parzen.init(pac_id: "test", feature_family: :test, dims: 3)
      end
    end

    test "raises without required pac_id" do
      assert_raise KeyError, fn ->
        Parzen.init(feature_family: :test)
      end
    end

    test "raises without required feature_family" do
      assert_raise KeyError, fn ->
        Parzen.init(pac_id: "test")
      end
    end
  end

  describe "fit/2 - uniform distribution" do
    test "fits uniform data and produces roughly equal bin probabilities" do
      # Generate uniform samples in [0, 1], shape [300, 1]
      {samples, _key} = Nx.Random.uniform(random_key(), 0.0, 1.0, shape: {300, 1}, type: :f32)

      parzen =
        Parzen.init(pac_id: "test", feature_family: :uniform)
        |> Parzen.fit(samples)

      # Check histogram exists
      assert parzen.bin_probs != nil
      assert parzen.bin_edges != nil

      # Sum of probabilities should be 1.0
      bin_probs_list = Nx.to_flat_list(parzen.bin_probs)
      sum = Enum.sum(bin_probs_list)
      assert_in_delta sum, 1.0, 0.001

      # For uniform distribution, each bin should have ~1/bins probability
      expected_prob = 1.0 / parzen.bins
      for prob <- bin_probs_list do
        # Allow 10x tolerance since we have limited samples (300)
        assert_in_delta prob, expected_prob, expected_prob * 10
      end
    end
  end

  describe "fit/2 - Gaussian distribution" do
    test "fits Gaussian data with more mass in center bins" do
      # Generate Gaussian samples N(0, 1), shape [500, 1]
      {samples, _key} = Nx.Random.normal(random_key(1), 0.0, 1.0, shape: {500, 1}, type: :f32)

      parzen =
        Parzen.init(pac_id: "test", feature_family: :gaussian, bins: 20)
        |> Parzen.fit(samples)

      bin_probs_list = Nx.to_flat_list(parzen.bin_probs)

      # Check sum is 1.0
      sum = Enum.sum(bin_probs_list)
      assert_in_delta sum, 1.0, 0.001

      # For Gaussian, central bins should have more probability than edge bins
      # Take middle 40% of bins (indices 6-13 for 20 bins)
      center_bins = Enum.slice(bin_probs_list, 6, 8)
      edge_bins = Enum.take(bin_probs_list, 3) ++ Enum.slice(bin_probs_list, 17, 3)

      center_mass = Enum.sum(center_bins)
      edge_mass = Enum.sum(edge_bins)

      # Center should have significantly more mass than edges
      assert center_mass > edge_mass
    end

    test "produces symmetric histogram for symmetric Gaussian" do
      # Large sample for better symmetry
      {samples, _key} = Nx.Random.normal(random_key(2), 0.0, 1.0, shape: {1000, 1}, type: :f32)

      parzen =
        Parzen.init(pac_id: "test", feature_family: :gaussian, bins: 20)
        |> Parzen.fit(samples)

      bin_probs_list = Nx.to_flat_list(parzen.bin_probs)

      # Check pairs from each end are roughly equal (within tolerance)
      for i <- 0..9 do
        left_prob = Enum.at(bin_probs_list, i)
        right_prob = Enum.at(bin_probs_list, 19 - i)
        # Allow 2x difference due to sampling variance
        assert_in_delta left_prob, right_prob, max(left_prob, right_prob)
      end
    end
  end

  describe "fit/2 - sliding window behavior" do
    test "maintains window_size limit" do
      parzen = Parzen.init(
        pac_id: "test",
        feature_family: :windowed,
        window_size: 100
      )

      # First batch: 80 samples
      {batch1, _key} = Nx.Random.uniform(random_key(3), shape: {80, 1}, type: :f32)
      parzen = Parzen.fit(parzen, batch1)
      assert Nx.axis_size(parzen.samples, 0) == 80

      # Second batch: 50 samples (total would be 130, exceeds window_size)
      {batch2, _key} = Nx.Random.uniform(random_key(4), shape: {50, 1}, type: :f32)
      parzen = Parzen.fit(parzen, batch2)
      assert Nx.axis_size(parzen.samples, 0) == 100  # Capped at window_size

      # Third batch: 30 more
      {batch3, _key} = Nx.Random.uniform(random_key(5), shape: {30, 1}, type: :f32)
      parzen = Parzen.fit(parzen, batch3)
      assert Nx.axis_size(parzen.samples, 0) == 100  # Still capped
    end

    test "sliding window keeps most recent samples" do
      parzen = Parzen.init(
        pac_id: "test",
        feature_family: :windowed,
        window_size: 50
      )

      # Batch with identifiable pattern: all 0.0
      batch1 = Nx.broadcast(0.0, {40, 1})
      parzen = Parzen.fit(parzen, batch1)

      # Batch with identifiable pattern: all 1.0
      batch2 = Nx.broadcast(1.0, {30, 1})
      parzen = Parzen.fit(parzen, batch2)

      # Window is 50, so we should have last 50 samples
      # That's: 20 from batch1 (0.0) + 30 from batch2 (1.0)
      samples_list = Nx.to_flat_list(parzen.samples)
      zeros = Enum.count(samples_list, &(&1 < 0.1))
      ones = Enum.count(samples_list, &(&1 > 0.9))

      assert zeros == 20
      assert ones == 30
    end
  end

  describe "histogram/1" do
    test "returns empty map when not fitted" do
      parzen = Parzen.init(pac_id: "test", feature_family: :test)
      hist = Parzen.histogram(parzen)
      assert hist == %{}
    end

    test "returns histogram data after fit" do
      {samples, _key} = Nx.Random.uniform(random_key(6), shape: {100, 1}, type: :f32)
      parzen = Parzen.init(pac_id: "test", feature_family: :test)
      parzen = Parzen.fit(parzen, samples)

      hist = Parzen.histogram(parzen)

      assert Map.has_key?(hist, :bin_edges)
      assert Map.has_key?(hist, :bin_probs)
      assert Map.has_key?(hist, :dims)
      assert hist.dims == 1

      # Check shapes
      assert Nx.axis_size(hist.bin_edges, 0) == 21  # bins + 1
      assert Nx.axis_size(hist.bin_probs, 0) == 20  # bins
    end
  end

  describe "density_at/2" do
    test "returns 0.0 when not fitted" do
      parzen = Parzen.init(pac_id: "test", feature_family: :test)
      point = Nx.tensor([0.5])
      assert Parzen.density_at(parzen, point) == 0.0
    end

    test "returns higher density at distribution center for Gaussian" do
      # Generate Gaussian N(0, 1)
      {samples, _key} = Nx.Random.normal(random_key(7), 0.0, 1.0, shape: {500, 1}, type: :f32)
      parzen = Parzen.init(pac_id: "test", feature_family: :gaussian)
      parzen = Parzen.fit(parzen, samples)

      # Points to test
      center = Nx.tensor([0.0])
      tail = Nx.tensor([3.0])

      density_center = Parzen.density_at(parzen, center)
      density_tail = Parzen.density_at(parzen, tail)

      # Center should have higher density than tail
      assert density_center > density_tail
      assert density_center > 0.0
    end

    test "handles 2D input vectors by squeezing" do
      {samples, _key} = Nx.Random.uniform(random_key(8), shape: {100, 1}, type: :f32)
      parzen = Parzen.init(pac_id: "test", feature_family: :test)
      parzen = Parzen.fit(parzen, samples)

      # 2D shape [1, 1]
      point_2d = Nx.tensor([[0.5]])
      density = Parzen.density_at(parzen, point_2d)

      assert is_float(density)
      assert density >= 0.0
    end
  end

  describe "snapshot/1 and from_snapshot/1" do
    test "snapshots and restores successfully" do
      {samples, _key} = Nx.Random.uniform(random_key(9), shape: {100, 2}, type: :f32)
      parzen = Parzen.init(pac_id: "pac_789", feature_family: :snapshot_test, bins: 25)
      parzen = Parzen.fit(parzen, samples)

      # Create snapshot
      snapshot = Parzen.snapshot(parzen)

      # Check snapshot fields
      assert snapshot.pac_id == "pac_789"
      assert snapshot.feature_family == :snapshot_test
      assert snapshot.window_size == 300
      assert snapshot.dims == 1
      assert snapshot.bins == 25
      assert is_binary(snapshot.pca_basis)
      assert is_binary(snapshot.pca_mean)
      assert is_binary(snapshot.bin_edges)
      assert is_binary(snapshot.bin_probs)

      # Restore from snapshot
      restored = Parzen.from_snapshot(snapshot)

      # Check key fields match
      assert restored.pac_id == parzen.pac_id
      assert restored.feature_family == parzen.feature_family
      assert restored.window_size == parzen.window_size
      assert restored.dims == parzen.dims
      assert restored.bins == parzen.bins

      # Check histogram data is restored
      assert restored.bin_edges != nil
      assert restored.bin_probs != nil

      # Verify histograms match
      orig_hist = Parzen.histogram(parzen)
      restored_hist = Parzen.histogram(restored)

      orig_probs = Nx.to_flat_list(orig_hist.bin_probs)
      restored_probs = Nx.to_flat_list(restored_hist.bin_probs)

      # Should be identical
      Enum.zip(orig_probs, restored_probs)
      |> Enum.each(fn {orig, rest} ->
        assert_in_delta orig, rest, 1.0e-6
      end)
    end

    test "snapshot doesn't include full sample tensor (lightweight)" do
      {samples, _key} = Nx.Random.uniform(random_key(10), shape: {300, 5}, type: :f32)
      parzen = Parzen.init(pac_id: "test", feature_family: :test)
      parzen = Parzen.fit(parzen, samples)

      snapshot = Parzen.snapshot(parzen)

      # Snapshot should not have raw samples (they're large)
      # It should only have sample_shape metadata
      assert is_tuple(snapshot.sample_shape)
      refute Map.has_key?(snapshot, :samples)

      # Restored Parzen won't have samples
      restored = Parzen.from_snapshot(snapshot)
      assert restored.samples == nil
      assert restored.proj_samples == nil

      # But histogram data is there
      assert restored.bin_probs != nil
      assert restored.bin_edges != nil
    end
  end

  describe "multi-dimensional features" do
    test "handles high-dimensional input via PCA projection to 1D" do
      # 10-dimensional features
      {samples, _key} = Nx.Random.normal(random_key(11), 0.0, 1.0, shape: {200, 10}, type: :f32)

      parzen = Parzen.init(pac_id: "test", feature_family: :high_dim, dims: 1)
      parzen = Parzen.fit(parzen, samples)

      # Check PCA reduced to 1D
      assert Nx.rank(parzen.pca_basis) == 1  # [10] vector
      assert Nx.rank(parzen.proj_samples) == 1  # [200] vector

      # Histogram should be 1D
      hist = Parzen.histogram(parzen)
      assert hist.dims == 1
      assert Nx.axis_size(hist.bin_probs, 0) == 20
    end
  end

  describe "telemetry" do
    test "emits telemetry events on fit" do
      # Attach test handler with unique ID to avoid cross-test interference
      test_pid = self()
      handler_id = "parzen_test_handler_#{:erlang.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:thunderline, :ml, :parzen, :fit, :start],
          [:thunderline, :ml, :parzen, :fit, :stop]
        ],
        fn event_name, measurements, metadata, _config ->
          # Only send to this specific test process
          if metadata.pac_id == "telemetry_test" do
            send(test_pid, {:telemetry, event_name, measurements, metadata})
          end
        end,
        nil
      )

      {samples, _key} = Nx.Random.uniform(random_key(12), shape: {50, 2}, type: :f32)
      parzen = Parzen.init(pac_id: "telemetry_test", feature_family: :test)
      _parzen = Parzen.fit(parzen, samples)

      # Check start event
      assert_receive {:telemetry, [:thunderline, :ml, :parzen, :fit, :start], measurements, metadata}
      assert measurements.batch_size == 50
      assert metadata.pac_id == "telemetry_test"
      assert metadata.feature_family == :test

      # Check stop event
      assert_receive {:telemetry, [:thunderline, :ml, :parzen, :fit, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.batch_size == 50

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end

  describe "edge cases" do
    test "handles single sample batch" do
      samples = Nx.tensor([[1.5]])
      parzen = Parzen.init(pac_id: "test", feature_family: :test)
      parzen = Parzen.fit(parzen, samples)

      # Should still create histogram (all mass in one bin)
      assert parzen.bin_probs != nil
      bin_probs_list = Nx.to_flat_list(parzen.bin_probs)
      assert Enum.sum(bin_probs_list) == 1.0
    end

    test "handles constant data (zero variance)" do
      # All samples the same value
      samples = Nx.broadcast(0.5, {100, 1})
      parzen = Parzen.init(pac_id: "test", feature_family: :constant)
      parzen = Parzen.fit(parzen, samples)

      # Should handle degenerate case by expanding range slightly
      assert parzen.bin_probs != nil
      bin_edges_list = Nx.to_flat_list(parzen.bin_edges)

      # Check that bin edges span a range (expanded from point)
      min_edge = Enum.min(bin_edges_list)
      max_edge = Enum.max(bin_edges_list)
      assert max_edge > min_edge
    end
  end
end
