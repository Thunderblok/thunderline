defmodule Thunderline.Thunderbit.IO do
  @moduledoc """
  Thunderbit I/O Specification Types

  Defines the types of data that can flow between Thunderbits and validates
  I/O compatibility for composition.

  ## I/O Types

  | Type | Description | Example |
  |------|-------------|---------|
  | `:event` | Discrete happenings with payload | `%{type: :user_input, payload: "hello"}` |
  | `:tensor` | Numerical arrays (Nx tensors) | `Nx.tensor([1.0, 2.0, 3.0])` |
  | `:message` | Structured messages | `%{to: "agent1", body: "..."}` |
  | `:context` | Contextual state map | `%{pac_id: "...", zone: "..."}` |
  | `:signal` | Raw external signals | Binary data, sensor readings |

  ## Usage

      iex> IO.compatible?(:event, :event)
      true

      iex> IO.validate_output(output, spec)
      :ok | {:error, :shape_mismatch}
  """

  alias Thunderline.Thunderbit.Category

  # ===========================================================================
  # Types
  # ===========================================================================

  @type io_type :: :event | :tensor | :message | :context | :signal

  @type io_spec :: %{
          name: atom(),
          type: io_type(),
          shape: term(),
          topic: String.t() | nil,
          required: boolean()
        }

  @type io_value :: term()

  @type validation_error ::
          :type_mismatch
          | :shape_mismatch
          | :missing_required
          | :unknown_type

  # ===========================================================================
  # Type Definitions
  # ===========================================================================

  @io_types %{
    event: %{
      description: "Discrete happenings with type and payload",
      shape: :map,
      required_fields: [:type],
      optional_fields: [:payload, :timestamp, :source]
    },
    tensor: %{
      description: "Numerical arrays (Nx tensors)",
      shape: :tensor,
      required_fields: [],
      optional_fields: []
    },
    message: %{
      description: "Structured messages between agents",
      shape: :map,
      required_fields: [],
      optional_fields: [:to, :from, :body, :metadata]
    },
    context: %{
      description: "Contextual state map",
      shape: :map,
      required_fields: [],
      optional_fields: []
    },
    signal: %{
      description: "Raw external signals",
      shape: :any,
      required_fields: [],
      optional_fields: []
    }
  }

  @doc "Returns all I/O types"
  def types, do: Map.keys(@io_types)

  @doc "Returns metadata for an I/O type"
  def type_info(type) when is_map_key(@io_types, type) do
    {:ok, Map.get(@io_types, type)}
  end

  def type_info(_), do: {:error, :unknown_type}

  # ===========================================================================
  # Type Compatibility
  # ===========================================================================

  @doc """
  Checks if two I/O types are compatible for connection.

  Some types can be automatically coerced:
  - `:signal` → `:event` (parsing)
  - `:event` → `:message` (wrapping)
  - `:context` → `:map` fields (extraction)
  """
  @spec compatible?(io_type(), io_type()) :: boolean()
  def compatible?(same, same), do: true
  def compatible?(:signal, :event), do: true
  def compatible?(:event, :message), do: true
  def compatible?(:context, :event), do: true
  def compatible?(:event, :context), do: true
  def compatible?(_, :any), do: true
  def compatible?(:any, _), do: true
  def compatible?(_, _), do: false

  @doc """
  Checks if an output spec can connect to an input spec.
  """
  @spec specs_compatible?(io_spec(), io_spec()) :: boolean()
  def specs_compatible?(output_spec, input_spec) do
    compatible?(output_spec.type, input_spec.type) and
      shapes_compatible?(output_spec.shape, input_spec.shape)
  end

  defp shapes_compatible?(:any, _), do: true
  defp shapes_compatible?(_, :any), do: true
  defp shapes_compatible?({:dynamic}, _), do: true
  defp shapes_compatible?(_, {:dynamic}), do: true
  defp shapes_compatible?(same, same), do: true
  defp shapes_compatible?(_, _), do: false

  # ===========================================================================
  # Validation
  # ===========================================================================

  @doc """
  Validates that a value matches an I/O spec.
  """
  @spec validate(io_value(), io_spec()) :: :ok | {:error, validation_error()}
  def validate(value, spec) do
    with :ok <- validate_type(value, spec.type),
         :ok <- validate_shape(value, spec.shape) do
      :ok
    end
  end

  defp validate_type(value, :event) when is_map(value), do: :ok
  defp validate_type(value, :message) when is_map(value), do: :ok
  defp validate_type(value, :context) when is_map(value), do: :ok
  defp validate_type(value, :tensor) when is_struct(value, Nx.Tensor), do: :ok
  defp validate_type(_, :signal), do: :ok
  defp validate_type(_, :any), do: :ok
  defp validate_type(_, _), do: {:error, :type_mismatch}

  defp validate_shape(_value, :any), do: :ok
  defp validate_shape(_value, :map), do: :ok
  defp validate_shape(_value, {:dynamic}), do: :ok

  defp validate_shape(tensor, expected_shape) when is_struct(tensor, Nx.Tensor) do
    actual_shape = Nx.shape(tensor)

    if shapes_match?(expected_shape, actual_shape) do
      :ok
    else
      {:error, :shape_mismatch}
    end
  end

  defp validate_shape(_, _), do: :ok

  defp shapes_match?({:dynamic}, _), do: true

  defp shapes_match?(expected, actual) when is_tuple(expected) and is_tuple(actual) do
    Tuple.to_list(expected) == Tuple.to_list(actual)
  end

  defp shapes_match?(_, _), do: true

  @doc """
  Validates all outputs against their specs.
  """
  @spec validate_outputs(map(), [io_spec()]) :: :ok | {:error, [{atom(), validation_error()}]}
  def validate_outputs(outputs, specs) do
    errors =
      specs
      |> Enum.filter(& &1.required)
      |> Enum.map(fn spec ->
        value = Map.get(outputs, spec.name)

        cond do
          is_nil(value) -> {spec.name, :missing_required}
          validate(value, spec) != :ok -> {spec.name, validate(value, spec)}
          true -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  # ===========================================================================
  # Category I/O Queries
  # ===========================================================================

  @doc """
  Returns the input specs for a category.
  """
  @spec inputs_for(Category.id()) :: [io_spec()]
  def inputs_for(category_id) do
    case Category.get(category_id) do
      {:ok, cat} -> cat.inputs
      _ -> []
    end
  end

  @doc """
  Returns the output specs for a category.
  """
  @spec outputs_for(Category.id()) :: [io_spec()]
  def outputs_for(category_id) do
    case Category.get(category_id) do
      {:ok, cat} -> cat.outputs
      _ -> []
    end
  end

  @doc """
  Checks if a category can produce output compatible with another category's input.
  """
  @spec categories_io_compatible?(Category.id(), Category.id()) :: boolean()
  def categories_io_compatible?(from_cat, to_cat) do
    outputs = outputs_for(from_cat)
    inputs = inputs_for(to_cat)

    # At least one output must be compatible with at least one input
    Enum.any?(outputs, fn output ->
      Enum.any?(inputs, fn input ->
        specs_compatible?(output, input)
      end)
    end)
  end

  # ===========================================================================
  # Event Construction
  # ===========================================================================

  @doc """
  Creates a standard event structure.
  """
  @spec event(atom(), term(), keyword()) :: map()
  def event(type, payload, opts \\ []) do
    %{
      type: type,
      payload: payload,
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      source: Keyword.get(opts, :source),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a message structure.
  """
  @spec message(String.t() | nil, term(), keyword()) :: map()
  def message(to, body, opts \\ []) do
    %{
      to: to,
      from: Keyword.get(opts, :from),
      body: body,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Wraps an event in a message.
  """
  @spec event_to_message(map(), keyword()) :: map()
  def event_to_message(event, opts \\ []) do
    message(Keyword.get(opts, :to), event, opts)
  end
end
