# Test Authentication and Channel Access
# This script finds the demo user and generates a valid session token

require Ash.Query
alias Thunderline.Thundergate.Resources.User

IO.puts("\n=== Testing Authentication & Channel Access ===\n")

# Find existing demo user (deselect virtual password field)
IO.puts("Looking for demo user...")
user = User
  |> Ash.Query.filter(email == "demo@thunderline.dev")
  |> Ash.Query.deselect([:password])
  |> Ash.read_one!(authorize?: false)

IO.puts("✓ Found user: #{user.email} (ID: #{user.id})")

# Generate authentication token
IO.puts("\nGenerating authentication token...")
case AshAuthentication.Jwt.token_for_user(user) do
  {:ok, token, _claims} ->
    IO.puts("✓ Generated authentication token\n")
    IO.puts("=== To test in browser ===")
    IO.puts("1. Open http://localhost:4000 in your browser")
    IO.puts("2. Open browser DevTools Console (F12)")
    IO.puts("3. Paste this code to set the auth token:\n")
    IO.puts("   localStorage.setItem('ash_authentication_token', '#{token}');")
    IO.puts("   location.reload();\n")
    IO.puts("4. Then visit: http://localhost:4000/c/demo")
    IO.puts("\n=== Or test with curl ===")
    IO.puts("   curl -i -H 'Authorization: Bearer #{token}' http://localhost:4000/c/demo\n")

  {:error, reason} ->
    IO.puts("\n✗ Failed to generate token: #{inspect(reason)}")
    IO.puts("\nMake sure tokens are enabled in User resource authentication config.")
end
