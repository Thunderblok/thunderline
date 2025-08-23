defmodule Thunderline.Thundercom.Mailer do
  @moduledoc """
  Mailer stub for Thunderline application.
  Swoosh dependency was removed, so this is a placeholder.
  """

  def deliver(email) do
    {:ok, email}
  end

  def deliver!(email) do
    email
  end
end
