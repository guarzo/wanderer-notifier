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
    case Jason.encode(data) do
      {:ok, json} ->
        conn
        |> put_resp_content_type("application/json", "utf-8")
        |> send_resp(status, json)

      {:error, reason} ->
        # Log the error
        require Logger
        Logger.error("JSON encoding failed: #{inspect(reason)}, data: #{inspect(data)}")

        # Send a 500 error with a safe message
        conn
        |> put_resp_content_type("application/json", "utf-8")
        |> send_resp(500, Jason.encode!(%{error: "Internal server error: JSON encoding failed"}))
    end
  rescue
    e ->
      # Log the unexpected error and return a safe error response
      require Logger
      Logger.error("Unexpected error in send_json_response: #{inspect(e)}")

      # Do not re-encode with Jason.encode! to avoid potential infinite loop
      conn
      |> put_resp_content_type("application/json", "utf-8")
      |> send_resp(500, "{\"error\":\"Critical server error\"}")
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
  Returns an error tuple if the body is empty.
  """
  def parse_body(conn) do
    case Map.get(conn, :body_params) do
      %Plug.Conn.Unfetched{aspect: :body_params} ->
        {:error, :unparsed_body}

      nil ->
        {:error, :no_body_params}

      params when is_map(params) ->
        if map_size(params) > 0 do
          {:ok, params}
        else
          {:error, :empty_body}
        end
    end
  end
end
