defmodule WandererNotifier.Api.Controller do
  @moduledoc """
  Base controller module that provides common functionality
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
