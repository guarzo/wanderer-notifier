defmodule WandererNotifier.Api.Helpers do
  @moduledoc """
  Common helpers for API controllers: JSON rendering and error handling.
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
end
