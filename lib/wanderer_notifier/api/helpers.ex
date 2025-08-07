defmodule WandererNotifier.Api.Helpers do
  @moduledoc """
  Common helpers for API controllers: JSON rendering and error handling.
  """
  import Plug.Conn
  require Logger

  alias WandererNotifier.Infrastructure.Http.Utils.JsonUtils

  @success_status 200
  @error_key :error

  @doc """
  Sends a JSON response with the given status and data.
  """
  @spec send_json_response(Plug.Conn.t(), integer(), any()) :: Plug.Conn.t()
  def send_json_response(conn, status, data) do
    case JsonUtils.encode(data) do
      {:ok, json} ->
        conn
        |> put_resp_content_type("application/json", "utf-8")
        |> send_resp(status, json)
        |> halt()

      {:error, reason} ->
        # Log the error
        Logger.error("JSON encoding failed", reason: inspect(reason), data: inspect(data))

        # Send a 500 error with a safe message
        error_response =
          JsonUtils.encode!(%{error: "Internal server error: JSON encoding failed"})

        conn
        |> put_resp_content_type("application/json", "utf-8")
        |> send_resp(500, error_response)
        |> halt()
    end
  rescue
    e ->
      # Log the unexpected error and return a safe error response
      Logger.error("Unexpected error in send_json_response", error: inspect(e))

      # Do not re-encode with JsonUtils.encode! to avoid potential infinite loop
      conn
      |> put_resp_content_type("application/json", "utf-8")
      |> send_resp(500, "{\"error\":\"Critical server error\"}")
      |> halt()
  end

  @doc """
  Sends a 200 OK JSON response.
  """
  @spec send_success(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def send_success(conn, data), do: send_json_response(conn, @success_status, data)

  @doc """
  Sends an error response with the given status and message.
  """
  @spec send_error(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def send_error(conn, status, message),
    do: send_json_response(conn, status, %{@error_key => message})
end
