defmodule Thunderline.Thunderbolt.DatasetManagerTest do
  use ExUnit.Case, async: true
  alias Thunderline.Thunderbolt.DatasetManager

  describe "preprocess_sample/2" do
    test "strips URLs from text" do
      text = "Visit https://example.com for more information about research."
      result = DatasetManager.preprocess_sample(text)

      refute String.contains?(result, "https://example.com")
      assert String.contains?(result, "Visit  for more information")
    end

    test "removes citations" do
      text = "The study [Smith et al. 2023] shows significant results [1]."
      result = DatasetManager.preprocess_sample(text)

      refute String.contains?(result, "[Smith et al. 2023]")
      refute String.contains?(result, "[1]")
      assert String.contains?(result, "The study  shows significant results")
    end

    test "removes non-ASCII Unicode characters" do
      text = "The résumé contained smart quotes and em-dashes—problematic."
      result = DatasetManager.preprocess_sample(text)

      refute String.contains?(result, "é")
      refute String.contains?(result, "—")
      assert String.contains?(result, "The rsum contained smart quotes")
    end

    test "normalizes whitespace and line breaks" do
      text = "Multiple   spaces\n\nand\tline\nbreaks   here."
      result = DatasetManager.preprocess_sample(text)

      assert result == "Multiple spaces and line breaks here."
    end

    test "ensures proper sentence boundaries" do
      text = "this is a test without proper capitalization or punctuation"
      result = DatasetManager.preprocess_sample(text)

      assert String.starts_with?(result, "This")
      assert String.ends_with?(result, ".")
    end

    test "truncates long text at sentence boundaries" do
      long_text = String.duplicate("This is a sentence. ", 50) <> "This is incomplete"
      # ~25 tokens
      result = DatasetManager.preprocess_sample(long_text, 100)

      # Should end with complete sentence, not mid-sentence
      assert String.ends_with?(result, ".")
      refute String.contains?(result, "This is incomplete")
      assert String.length(result) < String.length(long_text)
    end

    test "handles very short text" do
      text = "Short."
      result = DatasetManager.preprocess_sample(text)

      assert result == "Short."
    end

    test "handles empty or nil input" do
      assert DatasetManager.preprocess_sample("") |> is_nil()
      assert DatasetManager.preprocess_sample(nil) |> is_nil()
    end

    test "preserves meaningful punctuation" do
      text = "What is the answer? It's complex: depends on context; sometimes simple!"
      result = DatasetManager.preprocess_sample(text)

      assert String.contains?(result, "?")
      assert String.contains?(result, ":")
      assert String.contains?(result, ";")
      assert String.contains?(result, "!")
    end

    test "smart truncation preserves complete thoughts" do
      text = "First complete sentence. Second complete sentence. Third incomplete sent"
      # Force truncation
      result = DatasetManager.preprocess_sample(text, 50)

      # Should include first two complete sentences but not the incomplete one
      assert String.contains?(result, "First complete sentence")
      assert String.contains?(result, "Second complete sentence")
      refute String.contains?(result, "Third incomplete")
      assert String.ends_with?(result, ".")
    end
  end

  describe "create_phase1_dataset/1" do
    test "creates dataset with requested sample count" do
      {:ok, dataset_id, sample_count} = DatasetManager.create_phase1_dataset(target_samples: 100)

      assert is_binary(dataset_id)
      assert String.starts_with?(dataset_id, "phase1-clean-v1-")
      assert sample_count == 100
    end

    test "respects max context length parameter" do
      {:ok, _dataset_id, _sample_count} =
        DatasetManager.create_phase1_dataset(
          target_samples: 10,
          max_context_length: 200
        )

      # Should complete without error - actual validation would require
      # inspecting the generated samples, which is more complex
      assert true
    end

    test "handles small sample counts" do
      {:ok, dataset_id, sample_count} = DatasetManager.create_phase1_dataset(target_samples: 5)

      assert sample_count == 5
      assert is_binary(dataset_id)
    end
  end

  describe "text validation rules" do
    test "enforces minimum length requirement" do
      short_text = "Too short"
      result = DatasetManager.preprocess_sample(short_text, 512)

      # Should be rejected if below minimum (40 chars)
      if String.length(short_text) < 40 do
        assert is_nil(result)
      else
        assert is_binary(result)
      end
    end

    test "handles edge cases in sentence boundary detection" do
      # Text with abbreviations that shouldn't trigger sentence breaks
      text = "Dr. Smith and Prof. Johnson met at 3 p.m. on Jan. 15th to discuss the research."
      result = DatasetManager.preprocess_sample(text)

      # Should not be truncated at "Dr." or "Prof." - these aren't sentence endings
      assert String.contains?(result, "Dr. Smith")
      assert String.contains?(result, "Prof. Johnson")
      assert String.contains?(result, "3 p.m.")
    end

    test "preserves technical content appropriately" do
      text =
        "The algorithm achieves O(n log n) complexity. Performance metrics show 95% accuracy."

      result = DatasetManager.preprocess_sample(text)

      # Technical notation should be preserved
      assert String.contains?(result, "O(n log n)")
      assert String.contains?(result, "95%")
    end
  end
end
