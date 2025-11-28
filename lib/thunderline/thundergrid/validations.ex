defmodule Thunderline.Thundergrid.Validations do
  @moduledoc """
  Shared validations for Thundergrid resources.

  Provides reusable validation modules for:
  - Hex coordinate validation
  - Sub-hex range validation
  - Boundary point validation
  - Zone validation
  - Resource coordinate validation
  - Quantity data validation

  ## Usage in Ash Resources

      validations do
        validate Thunderline.Thundergrid.Validations.ValidHexCoordinates
        validate {Thunderline.Thundergrid.Validations.ValidSubHexRange, []}
      end
  """

  # ========================================
  # Hex Coordinate Validation
  # ========================================

  defmodule ValidHexCoordinates do
    @moduledoc """
    Validates that hex coordinates follow the constraint q + r + s = 0.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      q = Ash.Changeset.get_attribute(changeset, :hex_q)
      r = Ash.Changeset.get_attribute(changeset, :hex_r)
      s = Ash.Changeset.get_attribute(changeset, :hex_s)

      cond do
        is_nil(q) or is_nil(r) ->
          :ok

        is_nil(s) ->
          # s will be computed, so skip validation
          :ok

        q + r + s != 0 ->
          {:error,
           field: :hex_coordinates,
           message: "Hex coordinates must satisfy q + r + s = 0, got q=#{q}, r=#{r}, s=#{s}"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Sub-Hex Range Validation
  # ========================================

  defmodule ValidSubHexRange do
    @moduledoc """
    Validates that sub-hex coordinates are within valid range (-0.5 to 0.5).
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      sub_x = Ash.Changeset.get_attribute(changeset, :sub_hex_x)
      sub_y = Ash.Changeset.get_attribute(changeset, :sub_hex_y)

      errors = []

      errors =
        case sub_x do
          nil ->
            errors

          x when is_struct(x, Decimal) ->
            x_float = Decimal.to_float(x)

            if x_float < -0.5 or x_float > 0.5 do
              [{:sub_hex_x, "must be between -0.5 and 0.5"} | errors]
            else
              errors
            end

          x when is_number(x) ->
            if x < -0.5 or x > 0.5 do
              [{:sub_hex_x, "must be between -0.5 and 0.5"} | errors]
            else
              errors
            end
        end

      errors =
        case sub_y do
          nil ->
            errors

          y when is_struct(y, Decimal) ->
            y_float = Decimal.to_float(y)

            if y_float < -0.5 or y_float > 0.5 do
              [{:sub_hex_y, "must be between -0.5 and 0.5"} | errors]
            else
              errors
            end

          y when is_number(y) ->
            if y < -0.5 or y > 0.5 do
              [{:sub_hex_y, "must be between -0.5 and 0.5"} | errors]
            else
              errors
            end
        end

      case errors do
        [] -> :ok
        [{field, message} | _] -> {:error, field: field, message: message}
      end
    end
  end

  # ========================================
  # Boundary Point Validation
  # ========================================

  defmodule ValidBoundaryPoints do
    @moduledoc """
    Validates that boundary points form a valid boundary geometry.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      points = Ash.Changeset.get_attribute(changeset, :boundary_points)

      cond do
        is_nil(points) ->
          :ok

        not is_list(points) ->
          {:error, field: :boundary_points, message: "must be a list of coordinate points"}

        length(points) < 2 ->
          {:error,
           field: :boundary_points, message: "must have at least 2 points to form a boundary"}

        not Enum.all?(points, &valid_point?/1) ->
          {:error,
           field: :boundary_points,
           message: "all points must have valid hex coordinates (q, r, s keys)"}

        true ->
          :ok
      end
    end

    defp valid_point?(point) when is_map(point) do
      has_q = Map.has_key?(point, "q") or Map.has_key?(point, :q)
      has_r = Map.has_key?(point, "r") or Map.has_key?(point, :r)
      has_q and has_r
    end

    defp valid_point?(_), do: false
  end

  # ========================================
  # Different Zones Validation
  # ========================================

  defmodule DifferentZones do
    @moduledoc """
    Validates that zone_id and adjacent_zone_id are different.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      zone_id = Ash.Changeset.get_attribute(changeset, :zone_id)
      adjacent_zone_id = Ash.Changeset.get_attribute(changeset, :adjacent_zone_id)

      cond do
        is_nil(zone_id) or is_nil(adjacent_zone_id) ->
          :ok

        zone_id == adjacent_zone_id ->
          {:error, field: :adjacent_zone_id, message: "must be different from zone_id"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Resource Coordinates Validation
  # ========================================

  defmodule ValidResourceCoordinates do
    @moduledoc """
    Validates that resource hex coordinates are properly structured.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      coords = Ash.Changeset.get_attribute(changeset, :hex_coordinates)

      cond do
        is_nil(coords) ->
          :ok

        not is_map(coords) ->
          {:error, field: :hex_coordinates, message: "must be a map with q, r, s keys"}

        not (Map.has_key?(coords, "q") or Map.has_key?(coords, :q)) ->
          {:error, field: :hex_coordinates, message: "must include 'q' coordinate"}

        not (Map.has_key?(coords, "r") or Map.has_key?(coords, :r)) ->
          {:error, field: :hex_coordinates, message: "must include 'r' coordinate"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Quantity Data Validation
  # ========================================

  defmodule ValidQuantityData do
    @moduledoc """
    Validates that quantity data has required fields and valid values.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      data = Ash.Changeset.get_attribute(changeset, :quantity_data)

      cond do
        is_nil(data) ->
          :ok

        not is_map(data) ->
          {:error, field: :quantity_data, message: "must be a map"}

        true ->
          current = get_numeric(data, "current_quantity")
          max = get_numeric(data, "max_quantity")

          cond do
            is_nil(current) ->
              {:error, field: :quantity_data, message: "must include 'current_quantity'"}

            is_nil(max) ->
              {:error, field: :quantity_data, message: "must include 'max_quantity'"}

            current < 0 ->
              {:error, field: :quantity_data, message: "current_quantity cannot be negative"}

            max < 0 ->
              {:error, field: :quantity_data, message: "max_quantity cannot be negative"}

            current > max ->
              {:error,
               field: :quantity_data, message: "current_quantity cannot exceed max_quantity"}

            true ->
              :ok
          end
      end
    end

    defp get_numeric(map, key) do
      value = Map.get(map, key) || Map.get(map, String.to_atom(key))

      case value do
        nil -> nil
        v when is_number(v) -> v
        _ -> nil
      end
    end
  end
end
