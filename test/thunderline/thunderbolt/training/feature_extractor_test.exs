defmodule Thunderline.Thunderbolt.Training.FeatureExtractorTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Training.FeatureExtractor

  describe "extract/2" do
    test "extracts 24-dimensional feature vector from thunderbit" do
      thunderbit = %{
        id: "bit_123",
        pac_id: "pac_456",
        zone: :active,
        category: :task,
        energy: 0.8,
        age_ticks: 1000,
        health: 0.9,
        salience: 0.7,
        chain_depth: 3,
        role: :primary,
        status: :active,
        link_count: 5
      }

      context = %{
        active_bits: [thunderbit],
        pending_bits: [],
        tick: 5000,
        workflow_count: 10,
        entropy: 0.3,
        cerebros_score: 0.75,
        recent_transitions: 15,
        governance_score: 0.8
      }

      {:ok, result} = FeatureExtractor.extract(thunderbit, context)

      # Should return a map with vector, dimension, bit_features, context_features
      assert is_map(result)
      assert result.dimension == 24
      assert length(result.vector) == 24
      assert length(result.bit_features) == 12
      assert length(result.context_features) == 12

      # All features should be normalized to [0, 1]
      assert Enum.all?(result.vector, fn f -> is_number(f) and f >= 0.0 and f <= 1.0 end)

      # Metadata should be populated
      assert result.metadata.bit_id == "bit_123"
      assert result.metadata.category == :task
    end

    test "handles missing optional fields gracefully" do
      minimal_bit = %{
        id: "bit_minimal"
      }

      {:ok, result} = FeatureExtractor.extract(minimal_bit, %{})

      assert result.dimension == 24
      assert length(result.vector) == 24
      assert Enum.all?(result.vector, &is_number/1)
    end

    test "returns error for nil input" do
      # nil bit should return error (Map.get doesn't work on nil)
      {:error, {:extraction_failed, %BadMapError{}}} = FeatureExtractor.extract(nil, %{})
    end
  end

  describe "extract_batch/2" do
    test "extracts features for multiple thunderbits" do
      bits =
        Enum.map(1..3, fn i ->
          %{
            id: "bit_#{i}",
            category: :task,
            energy: 0.5 + i * 0.1
          }
        end)

      context = %{active_bits: bits, tick: 1000}

      {:ok, batch} = FeatureExtractor.extract_batch(bits, context)

      # Returns a map with states, count, dimension
      assert is_map(batch)
      assert batch.count == 3
      assert batch.dimension == 24
      assert length(batch.states) == 3
      assert Enum.all?(batch.states, fn features -> length(features) == 24 end)
    end

    test "handles empty list" do
      {:ok, batch} = FeatureExtractor.extract_batch([], %{})

      assert batch.count == 0
      assert batch.states == []
      assert batch.dimension == 24
    end
  end

  describe "feature_metadata/0" do
    test "returns metadata for all 24 features" do
      metadata = FeatureExtractor.feature_metadata()

      assert is_map(metadata)
      assert metadata.dimension == 24
      assert metadata.bit_feature_dim == 12
      assert metadata.context_feature_dim == 12
      assert length(metadata.names) == 24
      assert length(metadata.ranges) == 24
      assert is_binary(metadata.description)
    end
  end

  describe "feature_names/0" do
    test "returns list of 24 feature names as atoms" do
      names = FeatureExtractor.feature_names()

      assert length(names) == 24
      # Feature names are atoms, not strings
      assert Enum.all?(names, &is_atom/1)
      # Check for expected names
      assert :bit_hash_norm in names
      assert :energy in names
      assert :health in names
      assert :cerebros_score in names
    end
  end

  describe "dimension/0" do
    test "returns 24" do
      assert FeatureExtractor.dimension() == 24
    end
  end

  describe "vector_to_map/1" do
    test "converts vector to labeled map" do
      # Create a simple test vector
      {:ok, result} = FeatureExtractor.extract(%{id: "test"}, %{})

      labeled = FeatureExtractor.vector_to_map(result.vector)

      assert is_map(labeled)
      assert map_size(labeled) == 24
      assert Map.has_key?(labeled, :bit_hash_norm)
      assert Map.has_key?(labeled, :energy)
    end
  end
end
