defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.License
  alias WandererNotifier.Stats
  alias WandererNotifier.Features
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Config
  alias WandererNotifier.Web.TemplateHandler

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, dashboard_html())
  end

  get "/api/status" do
    license_status = License.status()

    # Extract license information
    license_info = %{
      valid: license_status[:valid],
      bot_assigned: license_status[:bot_assigned],
      details: license_status[:details],
      error: license_status[:error],
      error_message: license_status[:error_message]
    }

    # Get application stats
    stats = Stats.get_stats()

    # Get feature limitations
    limits = Features.get_all_limits()

    # Get current usage
    tracked_systems = get_tracked_systems()
    tracked_characters = CacheRepo.get("map:characters") || []

    # Calculate usage percentages
    usage = %{
      tracked_systems: %{
        current: length(tracked_systems),
        limit: limits.tracked_systems,
        percentage: calculate_percentage(length(tracked_systems), limits.tracked_systems)
      },
      tracked_characters: %{
        current: length(tracked_characters),
        limit: limits.tracked_characters,
        percentage: calculate_percentage(length(tracked_characters), limits.tracked_characters)
      },
      notification_history: %{
        limit: limits.notification_history
      }
    }

    # Combine stats, license info, and feature info
    response = %{
      stats: stats,
      license: license_info,
      features: %{
        limits: limits,
        usage: usage,
        enabled: %{
          basic_notifications: Features.enabled?(:basic_notifications),
          tracked_systems_notifications: Features.enabled?(:tracked_systems_notifications),
          tracked_characters_notifications: Features.enabled?(:tracked_characters_notifications),
          backup_kills_processing: Features.enabled?(:backup_kills_processing),
          web_dashboard_full: Features.enabled?(:web_dashboard_full),
          advanced_statistics: Features.enabled?(:advanced_statistics)
        },
        config: %{
          character_tracking_enabled: Config.character_tracking_enabled?(),
          character_notifications_enabled: Config.character_notifications_enabled?(),
          system_notifications_enabled: Config.system_notifications_enabled?()
        }
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to trigger a test kill notification
  get "/api/test-notification" do
    Logger.info("Test notification endpoint called")

    result = WandererNotifier.Service.KillProcessor.send_test_kill_notification()

    response =
      case result do
        {:ok, kill_id} ->
          %{
            success: true,
            message: "Test notification sent for kill_id: #{kill_id}",
            details:
              "The notification was processed through the normal notification path. Check your Discord for the message."
          }

        {:error, :enrichment_failed} ->
          %{
            success: false,
            message: "Failed to send test notification: Could not enrich kill data",
            details:
              "There was an error processing the kill data. Check the application logs for more details."
          }

        {:error, :no_kill_id} ->
          %{
            success: false,
            message: "Failed to send test notification: Invalid kill data",
            details:
              "The kill data does not contain a valid kill ID. Check the application logs for more details."
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Failed to send test notification: #{inspect(reason)}",
            details:
              "There was an error processing the notification. Check the application logs for more details."
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to trigger a test character notification
  get "/api/test-character-notification" do
    Logger.info("Test character notification endpoint called")

    result = send_test_character_notification()

    response =
      case result do
        {:ok, character_id, character_name} ->
          %{
            success: true,
            message:
              "Test character notification sent for character: #{character_name} (ID: #{character_id})",
            details:
              "The notification was processed through the normal notification path. Check your Discord for the message."
          }

        {:error, :no_characters_available} ->
          %{
            success: false,
            message: "Failed to send test notification: No tracked characters available",
            details:
              "The system needs to have tracked characters before test notifications can be sent. Wait for character tracking to update or check your configuration."
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Failed to send test notification: #{inspect(reason)}",
            details:
              "There was an error processing the notification. Check the application logs for more details."
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to trigger a test system notification
  get "/api/test-system-notification" do
    Logger.info("Test system notification endpoint called")

    result = send_test_system_notification()

    response =
      case result do
        {:ok, system_id, system_name} ->
          %{
            success: true,
            message:
              "Test system notification sent for system: #{system_name} (ID: #{system_id})",
            details:
              "The notification was processed through the normal notification path. Check your Discord for the message."
          }

        {:error, :no_systems_available} ->
          %{
            success: false,
            message: "Failed to send test notification: No tracked systems available",
            details:
              "The system needs to have tracked systems before test notifications can be sent. Wait for system tracking to update or check your configuration."
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Failed to send test notification: #{inspect(reason)}",
            details:
              "There was an error processing the notification. Check the application logs for more details."
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to check characters endpoint availability
  get "/api/check-characters-endpoint" do
    Logger.info("Characters endpoint check requested")

    result = WandererNotifier.Map.Characters.check_characters_endpoint_availability()

    response =
      case result do
        {:ok, message} ->
          %{
            success: true,
            message: "Characters endpoint is available",
            details: message
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Characters endpoint is not available",
            details: "Error: #{inspect(reason)}"
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to revalidate the license
  get "/api/revalidate-license" do
    Logger.info("License revalidation requested")

    # Call the License.validate function to revalidate
    result = WandererNotifier.License.validate()

    response =
      case result do
        %{valid: true} ->
          %{
            success: true,
            message: "License validation successful",
            details:
              "The license is valid and has been revalidated with the license server."
          }

        %{valid: false, error_message: error_message} ->
          %{
            success: false,
            message: "License validation failed",
            details: "Error: #{error_message}"
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil
  defp calculate_percentage(current, limit) when limit > 0, do: min(100, round(current / limit * 100))
  defp calculate_percentage(_, _), do: 0

  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  # Helper function to send a test character notification
  defp send_test_character_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test character notification")

    # Get the tracked characters from cache
    tracked_characters = CacheRepo.get("map:characters") || []
    Logger.info("TEST NOTIFICATION: Found #{length(tracked_characters)} tracked characters in cache")

    case tracked_characters do
      [] ->
        Logger.error("TEST NOTIFICATION: No tracked characters available for test notification")
        {:error, :no_characters_available}

      characters ->
        # Select a random character from the list
        character = Enum.random(characters)
        character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
        character_name = Map.get(character, "character_name") || "Unknown Character"

        Logger.info("TEST NOTIFICATION: Using character #{character_name} (ID: #{character_id}) for test notification")

        # Send the notification through the normal notification path
        Logger.info("TEST NOTIFICATION: Processing character through normal notification path")
        WandererNotifier.Discord.Notifier.send_new_tracked_character_notification(character)

        Logger.info("TEST NOTIFICATION: Successfully completed test character notification process")
        {:ok, character_id, character_name}
    end
  end

  # Helper function to send a test system notification
  defp send_test_system_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test system notification")

    # Get the tracked systems from cache
    tracked_systems = get_tracked_systems()
    Logger.info("TEST NOTIFICATION: Found #{length(tracked_systems)} tracked systems in cache")

    case tracked_systems do
      [] ->
        Logger.error("TEST NOTIFICATION: No tracked systems available for test notification")
        {:error, :no_systems_available}

      systems ->
        # Select a random system from the list
        system = Enum.random(systems)

        # Log the full system data for debugging
        Logger.info("TEST NOTIFICATION: Full system data: #{inspect(system, pretty: true)}")

        system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
        system_name = Map.get(system, "system_name") || Map.get(system, :alias) ||
                        Map.get(system, "name") || "Unknown System"
        original_name = Map.get(system, "original_name")
        temporary_name = Map.get(system, "temporary_name")

        Logger.info("TEST NOTIFICATION: Using system #{system_name} (ID: #{system_id}) for test notification")
        Logger.info("TEST NOTIFICATION: System details - original_name: #{inspect(original_name)}, temporary_name: #{inspect(temporary_name)}")

        # Send the notification through the normal notification path
        Logger.info("TEST NOTIFICATION: Processing system through normal notification path")
        WandererNotifier.Discord.Notifier.send_new_system_notification(system)

        Logger.info("TEST NOTIFICATION: Successfully completed test system notification process")
        {:ok, system_id, system_name}
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp dashboard_html do
    TemplateHandler.dashboard_template()
  end

end
