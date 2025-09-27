defmodule ThunderlineWeb.AuthController do
  @moduledoc """
  Authentication controller integrating AshAuthentication with Phoenix.

  Handles success/failure flows & sign out. On success we persist the user
  in the session and redirect to the main dashboard.
  """
  use ThunderlineWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias Thunderline.Thundergate.Resources.User
  alias Thunderline.Thunderlink.Resources.{Community, Channel}
  alias Thunderline.Thunderlink.Domain
  require Ash.Query

  # Override success to store user & redirect
  @impl true
  def success(conn, _activity, %User{} = user, _token) do
    conn = conn |> store_in_session(user) |> assign(:current_user, user)

    {community_slug, channel_slug} = default_channel_slugs()

    target =
      if community_slug && channel_slug, do: ~p"/c/#{community_slug}/#{channel_slug}", else: ~p"/"

    conn
    |> put_flash(:info, "Signed in successfully")
    |> redirect(to: target)
  end

  # Override failure for feedback
  @impl true
  def failure(conn, {strategy, phase}, reason) do
    msg = "Auth #{strategy}:#{phase} failed"

    conn
    |> put_flash(:error, msg)
    |> put_status(:unauthorized)
    |> render("failure.html", message: msg, reason: inspect(reason))
  end

  # Sign-out clears all tokens & session
  @impl true
  def sign_out(conn, _params) do
    conn
    |> clear_session(:thunderline)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/sign-in")
  end

  # Pick first community & its first channel to land user in chat after login.
  defp default_channel_slugs do
    community =
      Community
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.Query.limit(1)
      |> Ash.read_one(domain: Domain)

    with {:ok, community} <- community_result(community) do
      channel =
        Channel
        # Filter community channels by community id & active status. Using expression atoms directly (no pin).
        # Use Ash.Query.filter macro (requires Ash.Query) with pinned community id
        |> Ash.Query.filter(community_id == ^community.id and status == :active)
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.Query.limit(1)
        |> Ash.read_one(domain: Domain)

      case channel_result(channel) do
        {:ok, channel} -> {community.community_slug, channel.channel_slug}
        _ -> {community.community_slug, nil}
      end
    else
      _ -> {nil, nil}
    end
  end

  defp community_result({:ok, %Community{} = c}), do: {:ok, c}
  defp community_result(%Community{} = c), do: {:ok, c}
  defp community_result(_), do: :error

  defp channel_result({:ok, %Channel{} = c}), do: {:ok, c}
  defp channel_result(%Channel{} = c), do: {:ok, c}
  defp channel_result(_), do: :error
end
