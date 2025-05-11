defmodule WandererNotifier.Api.Helpers do
  @moduledoc """
  Common helpers for API controllers: JSON rendering, error handling, and request parsing.
  """
  import Plug.Conn

  @success_status 200
  @error_key :error

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
  def send_success(conn, data), do: send_json_response(conn, @success_status, data)

  @doc """
  Sends an error response with the given status and message.
  """
  def send_error(conn, status, message),
    do: send_json_response(conn, status, %{@error_key => message})

  @doc """
  Parses the JSON body from the connection.
  Checks if body_params has been populated by Plug.Parsers middleware,
  and returns the parsed body or an error tuple if the body hasn't been parsed.
  """
  def parse_body(conn) do
    case Map.get(conn, :body_params) do
      %Plug.Conn.Unfetched{aspect: :body_params} ->
        {:error, :unparsed_body}

      nil ->
        {:error, :no_body_params}

      params when is_map(params) ->
        {:ok, params}
    end
  end
end
