defmodule Thunderline.Vault do
  @moduledoc "Cloak vault for encrypting sensitive Ash attributes (used by AshCloak)."
  use Cloak.Vault, otp_app: :thunderline
end
