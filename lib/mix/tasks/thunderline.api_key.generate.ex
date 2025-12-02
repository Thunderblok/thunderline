defmodule Mix.Tasks.Thunderline.ApiKey.Generate do
  @moduledoc """
  Generate an API key for a user.

  ## Usage

      # Generate key with 90-day expiration (default)
      mix thunderline.api_key.generate --user-id <uuid>

      # Custom expiration
      mix thunderline.api_key.generate --user-id <uuid> --expires-in 30d

      # With name and scopes
      mix thunderline.api_key.generate --user-id <uuid> --name "CI Pipeline" --scopes mcp:read,api:write

      # Lookup user by email
      mix thunderline.api_key.generate --email admin@example.com

  ## Options

    * `--user-id` - UUID of the user (required unless --email given)
    * `--email` - Email of the user (alternative to --user-id)
    * `--expires-in` - Expiration period (default: 90d). Format: Nd (days), Nh (hours)
    * `--name` - Optional friendly name for the key
    * `--scopes` - Comma-separated scopes (e.g., mcp:read,api:write)

  ## Output

  The plaintext API key is printed once to stdout. Store it securely—
  it cannot be retrieved again.

  ## Example

      $ mix thunderline.api_key.generate --email admin@example.com --name "MCP Access"

      ✓ API Key generated successfully

      Key ID:     550e8400-e29b-41d4-a716-446655440000
      User:       admin@example.com
      Name:       MCP Access
      Expires:    2025-03-02 12:34:56Z

      ┌─────────────────────────────────────────────────────────────┐
      │ API KEY (store securely - shown only once):                 │
      │ tl_abc123...                                                │
      └─────────────────────────────────────────────────────────────┘

  """

  use Mix.Task

  require Ash.Query

  @shortdoc "Generate an API key for a user"

  @switches [
    user_id: :string,
    email: :string,
    expires_in: :string,
    name: :string,
    scopes: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _errors} = OptionParser.parse(args, strict: @switches)

    with {:ok, user} <- find_user(opts),
         {:ok, expires_at} <- parse_expiration(opts[:expires_in] || "90d"),
         {:ok, api_key, plaintext_key} <- create_api_key(user, expires_at, opts) do
      print_success(api_key, user, plaintext_key)
    else
      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp find_user(opts) do
    cond do
      opts[:user_id] ->
        case Ash.get(Thunderline.Thundergate.Resources.User, opts[:user_id], authorize?: false) do
          {:ok, user} -> {:ok, user}
          {:error, _} -> {:error, "User not found with ID: #{opts[:user_id]}"}
        end

      opts[:email] ->
        Thunderline.Thundergate.Resources.User
        |> Ash.Query.filter(email == ^opts[:email])
        |> Ash.read_one(authorize?: false)
        |> case do
          {:ok, nil} -> {:error, "User not found with email: #{opts[:email]}"}
          {:ok, user} -> {:ok, user}
          {:error, err} -> {:error, "Failed to lookup user: #{inspect(err)}"}
        end

      true ->
        {:error, "Must provide --user-id or --email"}
    end
  end

  defp parse_expiration(duration) do
    case Regex.run(~r/^(\d+)([dh])$/, duration) do
      [_, num, "d"] ->
        days = String.to_integer(num)
        {:ok, DateTime.add(DateTime.utc_now(), days * 24 * 60 * 60, :second)}

      [_, num, "h"] ->
        hours = String.to_integer(num)
        {:ok, DateTime.add(DateTime.utc_now(), hours * 60 * 60, :second)}

      _ ->
        {:error, "Invalid expiration format. Use Nd (days) or Nh (hours), e.g., 90d or 24h"}
    end
  end

  defp create_api_key(user, expires_at, opts) do
    scopes =
      case opts[:scopes] do
        nil -> []
        str -> String.split(str, ",", trim: true)
      end

    params = %{
      user_id: user.id,
      expires_at: expires_at,
      name: opts[:name],
      scopes: scopes
    }

    case Ash.create(Thunderline.Thundergate.Resources.ApiKey, params, authorize?: false) do
      {:ok, api_key} ->
        # The plaintext key is in __metadata__ after GenerateApiKey change
        plaintext_key = api_key.__metadata__[:api_key]
        {:ok, api_key, plaintext_key}

      {:error, err} ->
        {:error, "Failed to create API key: #{inspect(err)}"}
    end
  end

  defp print_success(api_key, user, plaintext_key) do
    Mix.shell().info("""

    ✓ API Key generated successfully

    Key ID:     #{api_key.id}
    User:       #{user.email}
    Name:       #{api_key.name || "(none)"}
    Scopes:     #{format_scopes(api_key.scopes)}
    Expires:    #{Calendar.strftime(api_key.expires_at, "%Y-%m-%d %H:%M:%SZ")}

    ┌─────────────────────────────────────────────────────────────┐
    │ API KEY (store securely - shown only once):                 │
    │ #{String.pad_trailing(plaintext_key || "(unavailable)", 57)} │
    └─────────────────────────────────────────────────────────────┘
    """)
  end

  defp format_scopes([]), do: "(all)"
  defp format_scopes(scopes), do: Enum.join(scopes, ", ")
end
