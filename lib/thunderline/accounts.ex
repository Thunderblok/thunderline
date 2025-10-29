defmodule Thunderline.Accounts do
  use Ash.Domain, otp_app: :thunderline, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Thunderline.Accounts.Token
    resource Thunderline.Accounts.User
  end
end
