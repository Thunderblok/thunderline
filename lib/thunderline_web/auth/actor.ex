defmodule ThunderlineWeb.Auth.Actor do
  @moduledoc """
  Helpers for building the minimal actor map used across Thunderline's web layer.

  The resulting map is intended to be lightweight (id/email/role/tenant_id) and can be
  safely stored in Phoenix assigns for sockets, LiveViews, and traditional controllers.
  """

  alias Ecto.UUID
  alias Thunderline.Thundergate.Resources.User

  @type t :: %{
          id: String.t(),
          email: String.t() | nil,
          role: atom(),
          tenant_id: String.t()
        }

  @doc """
  Build an actor struct from an AshAuthentication session map.

  Options:
    * `:allow_demo?` - When true and `DEMO_MODE` is enabled, fall back to a demo actor.
    * `:default` - A zero- or one-arity function invoked when session data is missing.
      Passing `:generate` produces a deterministic default actor similar to prior behaviour.
  """
  @spec from_session(map(), keyword()) :: t() | nil
  def from_session(session, opts \\ [])
  def from_session(session, opts) when is_map(session) do
    allow_demo? = Keyword.get(opts, :allow_demo?, false)
    default = Keyword.get(opts, :default, fn _ -> nil end)

    actor =
      session
      |> get_current_user()
      |> build_actor(session)

    cond do
      actor != nil -> actor
      allow_demo? and demo_mode?() -> demo_actor()
      default == :generate -> generated_actor(session)
      is_function(default, 1) -> default.(session)
      is_function(default, 0) -> default.()
      true -> nil
    end
  end

  def from_session(_session, opts), do: handle_invalid_session(opts)

  @spec build_actor(User.t() | map() | nil, map()) :: t() | nil
  def build_actor(%User{} = user, session) do
    %{
      id: user.id,
      email: user.email,
      role: session_role(session) || :owner,
      tenant_id: session_tenant(session) || default_tenant()
    }
  end

  def build_actor(%{} = map, session) do
    %{
      id: Map.get(map, :id) || Map.get(map, "id") || UUID.generate(),
      email: Map.get(map, :email) || Map.get(map, "email"),
      role: Map.get(map, :role) || Map.get(map, "role") || session_role(session) || :owner,
      tenant_id: Map.get(map, :tenant_id) || Map.get(map, "tenant_id") || session_tenant(session) || default_tenant()
    }
  end

  def build_actor(_unknown, _session), do: nil

  @spec generated_actor(map()) :: t()
  def generated_actor(session) do
    %{
      id: UUID.generate(),
      email: Map.get(session, "email") || "operator@thunderline.local",
      role: session_role(session) || :owner,
      tenant_id: session_tenant(session) || default_tenant()
    }
  end

  @spec demo_actor() :: t()
  def demo_actor do
    %{
      id: UUID.generate(),
      email: "demo@thunderline.local",
      role: :owner,
      tenant_id: "demo"
    }
  end

  @spec session_role(map()) :: atom() | nil
  def session_role(session) when is_map(session) do
    case Map.get(session, "role") || Map.get(session, :role) do
      r when r in ["owner", :owner] -> :owner
      r when r in ["steward", :steward] -> :steward
      r when r in ["system", :system] -> :system
      _ -> nil
    end
  end

  def session_role(_), do: nil

  @spec session_tenant(map()) :: String.t() | nil
  def session_tenant(session) when is_map(session) do
    Map.get(session, "tenant_id") || Map.get(session, :tenant_id)
  end

  def session_tenant(_), do: nil

  defp get_current_user(session) do
    Map.get(session, "current_user") || Map.get(session, :current_user)
  end

  defp handle_invalid_session(opts) do
    if Keyword.get(opts, :allow_demo?, false) and demo_mode?(), do: demo_actor(), else: nil
  end

  defp demo_mode? do
    System.get_env("DEMO_MODE") in ["1", "true", "TRUE"]
  end

  defp default_tenant, do: "default"
end
