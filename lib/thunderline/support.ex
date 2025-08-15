defmodule Thunderline.Support do
  @moduledoc """
  Support domain for helpdesk functionality.

  Following the official Ash getting started guide.
  """

  use Ash.Domain

  resources do
    resource Thunderline.Support.Ticket
  end
end
