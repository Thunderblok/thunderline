defmodule Thunderline.Thundergate.Policies.AdminAccess do
  @moduledoc "Thin helper for admin access checks; integrate with Ash policies."
  @spec allowed?(map) :: boolean
  def allowed?(%{role: role}) when role in [:owner, :steward], do: true
  def allowed?(_), do: false
end
