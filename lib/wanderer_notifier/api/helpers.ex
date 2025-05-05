defmodule WandererNotifier.Api.Helpers do
  @moduledoc """
  Common helpers for API controllers: JSON rendering, error handling, and request parsing.
  """
  import Plug.Conn

  @doc """
  Sends a JSON response with the given status and data.
  """
  def send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  @doc """
  Sends a 200 OK JSON response.
  """
  def send_success(conn, data), do: send_json_response(conn, 200, data)

  @doc """
  Sends an error response with the given status and message.
  """
  def send_error(conn, status, message), do: send_json_response(conn, status, %{error: message})

  @doc """
  Renders a map or struct as JSON with the given status (default 200).
  """
  def render_json(conn, data, status \\ 200), do: send_json_response(conn, status, data)

  @doc """
  Parses the JSON body from the connection (assumes Plug.Parsers ran).
  Returns the parsed body params map.
  """
  def parse_body(conn), do: conn.body_params
end
