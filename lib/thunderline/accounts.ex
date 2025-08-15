defmodule Thunderline.Accounts do
  use Ash.Domain,
    otp_app: :thunderline

  resources do
    resource Thunderline.Accounts.Token
    resource Thunderline.Accounts.User
  end
end
