defmodule Thunderline.Thunderbolt.Cerebros.EncoderTest do
  use ExUnit.Case, async: true

  alias Thunderline.Thunderbolt.Cerebros.Encoder

  @moduletag :cerebros

  describe "encode_data/3" do
    test "encodes text data to binary vector" do
      {:ok, binary} = Encoder.encode_data("hello world", :text, bits: 64)

      assert is_binary(binary)
      assert byte_size(binary) == 64
    end

    test "encodes raw binary data" do
      data = <<1, 2, 3, 4, 5>>
      {:ok, binary} = Encoder.encode_data(data, :raw, bits: 32)

      assert is_binary(binary)
      assert byte_size(binary) == 32
    end

    test "encodes tensor/list data" do
      data = [0.1, 0.5, 0.9, 0.3]
      {:ok, binary} = Encoder.encode_data(data, :tensor, bits: 64)

      assert is_binary(binary)
      assert byte_size(binary) == 64
    end

    test "encodes tabular data" do
      data = [
        %{a: 1, b: 2},
        %{a: 3, b: 4}
      ]

      {:ok, binary} = Encoder.encode_data(data, :tabular, bits: 128)

      assert is_binary(binary)
      assert byte_size(binary) == 128
    end

    test "returns error for invalid type" do
      result = Encoder.encode_data("test", :unknown_type)
      assert {:error, _reason} = result
    end

    test "different inputs produce different outputs" do
      {:ok, bin1} = Encoder.encode_data("hello", :text, bits: 64)
      {:ok, bin2} = Encoder.encode_data("world", :text, bits: 64)

      refute bin1 == bin2
    end
  end

  describe "decode_binary/2" do
    test "decodes binary to float vector" do
      binary = :crypto.strong_rand_bytes(64)
      floats = Encoder.decode_binary(binary, chunk_size: 4)

      assert is_list(floats)
      assert length(floats) == 16
      assert Enum.all?(floats, fn f -> is_float(f) and f >= 0.0 and f <= 1.0 end)
    end

    test "roundtrip preserves structure" do
      {:ok, binary} = Encoder.encode_data("test data", :text, bits: 64)
      floats = Encoder.decode_binary(binary)

      assert length(floats) > 0
      assert Enum.all?(floats, &is_float/1)
    end
  end

  describe "encoding_stats/1" do
    test "returns statistics for binary" do
      {:ok, binary} = Encoder.encode_data("hello world", :text, bits: 128)
      stats = Encoder.encoding_stats(binary)

      assert Map.has_key?(stats, :byte_count)
      assert Map.has_key?(stats, :bit_count)
      assert Map.has_key?(stats, :ones_count)
      assert Map.has_key?(stats, :zeros_count)
      assert Map.has_key?(stats, :entropy_approx)
      assert Map.has_key?(stats, :density)

      assert stats.byte_count == 128
      assert stats.bit_count == 1024
      assert stats.ones_count + stats.zeros_count == stats.bit_count
    end
  end
end
