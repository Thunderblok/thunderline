defmodule ThunderlineWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use Phoenix.Controller, formats: [:html, :json]
  require Logger

  def call(conn, {:error, %Ash.Error.Invalid{errors: errors} = error}) do
    Logger.error("Ash Invalid Error: #{inspect(error, pretty: true)}")
    # Check if this is actually a "not found" error disguised as invalid
    if Enum.any?(errors, &is_not_found_error?/1) do
      conn
      |> put_status(:not_found)
      |> put_view(json: ThunderlineWeb.ErrorJSON)
      |> render(:"404")
    else
      conn
      |> put_status(:bad_request)
      |> put_view(json: ThunderlineWeb.ErrorJSON)
      |> render(:"400", error: format_error(error))
    end
  end

  def call(conn, {:error, %Ash.Error.Query.NotFound{}}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ThunderlineWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, %Ash.Error.Forbidden{} = error}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: ThunderlineWeb.ErrorJSON)
    |> render(:"403", error: format_error(error))
  end

  def call(conn, {:error, %Ash.Error.Unknown{} = error}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: ThunderlineWeb.ErrorJSON)
    |> render(:"500", error: format_error(error))
  end

  def call(conn, {:error, _error}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: ThunderlineWeb.ErrorJSON)
    |> render(:"500")
  end

  defp format_error(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.map(&format_single_error/1)
    |> Enum.join(", ")
  end

  defp format_error(error) do
    format_single_error(error)
  end

  defp format_single_error(%{message: message}) when is_binary(message), do: message
  defp format_single_error(%{error: error}), do: format_single_error(error)
  defp format_single_error(error) when is_binary(error), do: error
  defp format_single_error(_), do: "An error occurred"

  defp is_not_found_error?(%Ash.Error.Query.NotFound{}), do: true
  defp is_not_found_error?(%{error: error}), do: is_not_found_error?(error)
  defp is_not_found_error?(_), do: false
end
