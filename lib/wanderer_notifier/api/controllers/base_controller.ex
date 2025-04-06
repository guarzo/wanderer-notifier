defmodule WandererNotifier.Api.Controllers.BaseController do
  @moduledoc """
  Base controller that provides common functionality for all API controllers.
  """
  import Plug.Conn

  defmacro __using__(_opts) do
    quote do
      use Plug.Router
      import Plug.Conn
      import WandererNotifier.Api.Controllers.BaseController

      # Common plugs
      plug(Plug.Parsers,
        parsers: [:json],
        pass: ["application/json"],
        json_decoder: Jason
      )

      plug(:match)
      plug(:dispatch)
    end
  end

  @doc """
  Sends a JSON response with the given status and body.
  """
  def send_json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  @doc """
  Sends a standard error response.
  """
  def send_error_response(conn, status, message) do
    send_json_response(conn, status, %{error: message})
  end

  @doc """
  Sends a standard success response.
  """
  def send_success_response(conn, data) do
    send_json_response(conn, 200, %{status: "ok", data: data})
  end

  @doc """
  Handles common error cases and sends appropriate responses.
  """
  def handle_error(conn, error, opts) do
    alias WandererNotifier.Logger.Logger, as: AppLogger

    try do
      # Log the error with appropriate context
      AppLogger.api_error("Error in controller", %{
        error: inspect(error),
        path: conn.request_path,
        method: conn.method,
        params: conn.params,
        opts: inspect(opts)
      })

      # Return appropriate error response
      case error do
        %{message: message} ->
          send_error_response(conn, 500, message)

        message when is_binary(message) ->
          send_error_response(conn, 500, message)

        _ ->
          send_error_response(conn, 500, "An unexpected error occurred")
      end
    rescue
      e ->
        AppLogger.api_error("Error handling controller error", %{
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        send_error_response(conn, 500, "An unexpected error occurred")
    end
  end
end
