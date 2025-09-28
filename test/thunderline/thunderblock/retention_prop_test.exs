defmodule Thunderline.Thunderblock.RetentionPropTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Thunderline.Thunderblock.Retention

  property "normalize_unit handles casing and whitespace" do
    check all(unit <- member_of(["SEC", " sec", "minutes ", "HoUrS", "days", "W", "weeks"]),
              max_runs: 100) do
      assert {:ok, _seconds} = Retention.normalize_unit(unit)
    end
  end

  property "normalize_unit rejects unknown units" do
    check all(unit <- string(:alphanumeric, min_length: 1), max_runs: 50) do
      sanitized = unit |> String.trim() |> String.downcase()

      unless sanitized in ["s", "sec", "secs", "second", "seconds", "m", "min", "mins", "minute",
                            "minutes", "h", "hr", "hrs", "hour", "hours", "d", "day", "days",
                            "w", "week", "weeks"] do
        assert {:error, :unknown_unit} = Retention.normalize_unit(unit)
      end
    end
  end
end
