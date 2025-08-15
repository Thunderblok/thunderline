defmodule Thunderline.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Thunderline.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:thunderline, :token_signing_secret)
  end
end
