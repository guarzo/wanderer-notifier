defmodule WandererNotifier.Api.Controllers.NotificationController do
  @moduledoc """
  Controller for notification-related endpoints.
  """
  use Plug.Router
  import WandererNotifier.Api.Controller

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.TestNotifier, as: NotificationHelpers

  # Get notification settings
  get "/settings" do
    case get_notification_settings(conn) do
      {:ok, settings} ->
        send_success(conn, settings)

      _error ->
        send_resp(conn, 404, "oops")
    end
  end

  # Send test notification
  post "/test" do
    type = conn.body_params["type"] || "kill"

    result =
      case type do
        "kill" -> NotificationHelpers.send_test_kill_notification()
        "character" -> NotificationHelpers.send_test_character_notification()
        "system" -> NotificationHelpers.send_test_system_notification()
        _ -> {:error, "Invalid notification type"}
      end

    case result do
      {:ok, _} -> send_success(conn, %{message: "Test notification sent"})
      {:error, reason} -> send_error(conn, 400, reason)
    end
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private functions
  defp get_notification_settings(conn) do
    settings = %{
      channels: Config.discord_channel_id(),
      features: Config.features(),
      limits: Config.get_all_limits()
    }

    {:ok, settings}
  rescue
    error ->
      AppLogger.api_error("Error getting notification settings", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      send_error(conn, 500, "An unexpected error occurred")
  end
end
