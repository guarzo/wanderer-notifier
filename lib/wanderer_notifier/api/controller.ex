defmodule WandererNotifier.Api.Controller do
  @moduledoc """
  Deprecated: Use WandererNotifier.Api.Helpers for response helpers.
  This module is kept for backward compatibility only.
  """

  import Plug.Conn

  @doc """
  Sends a JSON response
  """
  def send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  @doc """
  Sends a success response
  """
  def send_success(conn, data) do
    send_json_response(conn, 200, data)
  end

  @doc """
  Sends an error response
  """
  def send_error(conn, status, message) do
    send_json_response(conn, status, %{error: message})
  end
end
