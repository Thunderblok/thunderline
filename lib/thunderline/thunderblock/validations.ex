defmodule Thunderline.Thunderblock.Validations do
  @moduledoc """
  Shared validations for Thunderblock and Thunderlink resources.

  Provides reusable validation modules for:
  - Slug validation (URL-safe identifiers)
  - Resource limits structure validation
  - Config structure validation
  - Permissions structure validation
  - Hierarchy validation

  ## Usage in Ash Resources

      validations do
        validate Thunderline.Thunderblock.Validations.ValidSlug, field: :home_slug
        validate Thunderline.Thunderblock.Validations.ValidResourceLimits
      end
  """

  # ========================================
  # Slug Validation
  # ========================================

  defmodule ValidSlug do
    @moduledoc """
    Validates that a slug field is URL-safe.
    Configurable via `field` option.
    """
    use Ash.Resource.Validation

    @slug_regex ~r/^[a-z0-9][a-z0-9\-_]*[a-z0-9]$|^[a-z0-9]$/

    @impl true
    def init(opts) do
      field = Keyword.get(opts, :field, :slug)
      {:ok, %{field: field}}
    end

    @impl true
    def validate(changeset, opts, _context) do
      field = opts[:field] || :slug
      value = Ash.Changeset.get_attribute(changeset, field)

      cond do
        is_nil(value) ->
          :ok

        not is_binary(value) ->
          {:error, field: field, message: "must be a string"}

        String.length(value) < 1 ->
          {:error, field: field, message: "cannot be empty"}

        String.length(value) > 100 ->
          {:error, field: field, message: "cannot exceed 100 characters"}

        not Regex.match?(@slug_regex, value) ->
          {:error,
           field: field,
           message:
             "must be lowercase alphanumeric with hyphens/underscores, cannot start/end with special characters"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Resource Limits Validation
  # ========================================

  defmodule ValidResourceLimits do
    @moduledoc """
    Validates that resource_limits map has valid structure and values.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      limits = Ash.Changeset.get_attribute(changeset, :resource_limits)

      cond do
        is_nil(limits) ->
          :ok

        not is_map(limits) ->
          {:error, field: :resource_limits, message: "must be a map"}

        true ->
          validate_limit_values(limits)
      end
    end

    defp validate_limit_values(limits) do
      errors =
        Enum.reduce(limits, [], fn {key, value}, acc ->
          cond do
            not is_number(value) and not is_nil(value) ->
              [{key, "must be a number or nil"} | acc]

            is_number(value) and value < 0 ->
              [{key, "cannot be negative"} | acc]

            true ->
              acc
          end
        end)

      case errors do
        [] -> :ok
        [{key, message} | _] -> {:error, field: :resource_limits, message: "#{key} #{message}"}
      end
    end
  end

  # ========================================
  # Config Structure Validation
  # ========================================

  defmodule ValidConfigStructure do
    @moduledoc """
    Validates that config maps have valid structure.
    Configurable via `field` option.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts) do
      field = Keyword.get(opts, :field, :config)
      {:ok, %{field: field}}
    end

    @impl true
    def validate(changeset, opts, _context) do
      field = opts[:field] || :config
      value = Ash.Changeset.get_attribute(changeset, field)

      cond do
        is_nil(value) ->
          :ok

        not is_map(value) ->
          {:error, field: field, message: "must be a map"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Permissions Structure Validation
  # ========================================

  defmodule ValidPermissions do
    @moduledoc """
    Validates that permissions map has valid structure.
    """
    use Ash.Resource.Validation

    @valid_permission_values [:allow, :deny, :inherit, true, false]

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      permissions = Ash.Changeset.get_attribute(changeset, :permissions)

      cond do
        is_nil(permissions) ->
          :ok

        not is_map(permissions) ->
          {:error, field: :permissions, message: "must be a map"}

        true ->
          validate_permission_values(permissions)
      end
    end

    defp validate_permission_values(permissions) do
      invalid =
        Enum.find(permissions, fn {_key, value} ->
          not (value in @valid_permission_values)
        end)

      case invalid do
        nil ->
          :ok

        {key, _value} ->
          {:error,
           field: :permissions,
           message: "#{key} must be one of: #{inspect(@valid_permission_values)}"}
      end
    end
  end

  # ========================================
  # Channel Permissions Validation
  # ========================================

  defmodule ValidChannelPermissions do
    @moduledoc """
    Validates channel permission overrides structure.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      overrides = Ash.Changeset.get_attribute(changeset, :permission_overrides)

      cond do
        is_nil(overrides) ->
          :ok

        not is_map(overrides) ->
          {:error, field: :permission_overrides, message: "must be a map"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Attachments Validation
  # ========================================

  defmodule ValidAttachments do
    @moduledoc """
    Validates that attachments array has valid structure.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      attachments = Ash.Changeset.get_attribute(changeset, :attachments)

      cond do
        is_nil(attachments) ->
          :ok

        not is_list(attachments) ->
          {:error, field: :attachments, message: "must be a list"}

        not Enum.all?(attachments, &valid_attachment?/1) ->
          {:error, field: :attachments, message: "all attachments must have url and type fields"}

        true ->
          :ok
      end
    end

    defp valid_attachment?(att) when is_map(att) do
      has_url = Map.has_key?(att, "url") or Map.has_key?(att, :url)
      has_type = Map.has_key?(att, "type") or Map.has_key?(att, :type)
      has_url and has_type
    end

    defp valid_attachment?(_), do: false
  end

  # ========================================
  # Hierarchy Validation
  # ========================================

  defmodule ValidHierarchy do
    @moduledoc """
    Validates that hierarchy/level values are valid.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts) do
      field = Keyword.get(opts, :field, :hierarchy_level)
      max = Keyword.get(opts, :max, 100)
      {:ok, %{field: field, max: max}}
    end

    @impl true
    def validate(changeset, opts, _context) do
      field = opts[:field] || :hierarchy_level
      max = opts[:max] || 100
      value = Ash.Changeset.get_attribute(changeset, field)

      cond do
        is_nil(value) ->
          :ok

        not is_integer(value) ->
          {:error, field: field, message: "must be an integer"}

        value < 0 ->
          {:error, field: field, message: "cannot be negative"}

        value > max ->
          {:error, field: field, message: "cannot exceed #{max}"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Child Specs Validation
  # ========================================

  defmodule ValidChildSpecs do
    @moduledoc """
    Validates supervision tree child specs structure.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      specs = Ash.Changeset.get_attribute(changeset, :child_specs)

      cond do
        is_nil(specs) ->
          :ok

        not is_list(specs) ->
          {:error, field: :child_specs, message: "must be a list"}

        not Enum.all?(specs, &valid_child_spec?/1) ->
          {:error,
           field: :child_specs, message: "all child specs must have id and start fields"}

        true ->
          :ok
      end
    end

    defp valid_child_spec?(spec) when is_map(spec) do
      has_id = Map.has_key?(spec, "id") or Map.has_key?(spec, :id)
      has_start = Map.has_key?(spec, "start") or Map.has_key?(spec, :start)
      has_id and has_start
    end

    defp valid_child_spec?(_), do: false
  end

  # ========================================
  # Federation Config Validation
  # ========================================

  defmodule ValidFederationConfig do
    @moduledoc """
    Validates federation socket configuration structure.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      config = Ash.Changeset.get_attribute(changeset, :federation_config)

      cond do
        is_nil(config) ->
          :ok

        not is_map(config) ->
          {:error, field: :federation_config, message: "must be a map"}

        true ->
          :ok
      end
    end
  end

  # ========================================
  # Target Specification Validation
  # ========================================

  defmodule ValidTargetSpec do
    @moduledoc """
    Validates target specification for federation sockets.
    """
    use Ash.Resource.Validation

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def validate(changeset, _opts, _context) do
      target = Ash.Changeset.get_attribute(changeset, :target_specification)

      cond do
        is_nil(target) ->
          :ok

        not is_map(target) ->
          {:error, field: :target_specification, message: "must be a map"}

        not (Map.has_key?(target, "host") or Map.has_key?(target, :host)) ->
          {:error, field: :target_specification, message: "must include 'host' field"}

        true ->
          :ok
      end
    end
  end
end
