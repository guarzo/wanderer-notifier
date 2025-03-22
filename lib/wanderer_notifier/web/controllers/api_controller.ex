defmodule WandererNotifier.Web.Controllers.ApiController do
  @moduledoc """
  API controller for the web interface.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Helpers.NotificationHelpers
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.License

  plug(:match)
  plug(:dispatch)

  # Health check endpoint
  get "/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok"}))
  end

  # Status endpoint for the dashboard
  get "/status" do
    try do
      license_status = WandererNotifier.Core.License.status()

      license_info = %{
        valid: license_status[:valid],
        bot_assigned: license_status[:bot_assigned],
        details: license_status[:details],
        error: license_status[:error],
        error_message: license_status[:error_message]
      }

      stats = WandererNotifier.Core.Stats.get_stats()
      features = WandererNotifier.Core.Features
      limits = features.get_all_limits()

      # Add error handling for tracked systems and characters
      tracked_systems =
        try do
          WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()
        rescue
          e ->
            Logger.error("Error getting tracked systems: #{inspect(e)}")
            []
        end

      tracked_characters =
        try do
          WandererNotifier.Data.Cache.Repository.get("map:characters") || []
        rescue
          e ->
            Logger.error("Error getting tracked characters: #{inspect(e)}")
            []
        end

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

      response = %{
        stats: stats,
        license: license_info,
        features: %{
          limits: limits,
          usage: usage,
          enabled: %{
            basic_notifications: features.enabled?(:basic_notifications),
            tracked_systems_notifications: features.enabled?(:tracked_systems_notifications),
            tracked_characters_notifications:
              features.enabled?(:tracked_characters_notifications),
            backup_kills_processing: features.enabled?(:backup_kills_processing),
            web_dashboard_full: features.enabled?(:web_dashboard_full),
            advanced_statistics: features.enabled?(:advanced_statistics)
          },
          config: %{
            character_tracking_enabled:
              WandererNotifier.Core.Config.character_tracking_enabled?(),
            character_notifications_enabled:
              WandererNotifier.Core.Config.character_notifications_enabled?(),
            system_notifications_enabled:
              WandererNotifier.Core.Config.system_notifications_enabled?()
          }
        }
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    rescue
      e ->
        Logger.error("Error processing /api/status: #{inspect(e)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Internal server error", details: inspect(e)}))
    end
  end

  # Placeholder for all CorpTools-related endpoints (functionality removed)
  match "/test-corp-tools" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Catch-all for all corp-tools endpoints
  match "/corp-tools/*_" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Special endpoint to handle all three TPS chart types
  get "/corp-tools/charts/:chart_type" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Legacy endpoint for kills by ship type (keep for backward compatibility)
  get "/corp-tools/charts/kills-by-ship-type" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Get chart for kills by month
  get "/corp-tools/charts/kills-by-month" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Get chart for total kills and value
  get "/corp-tools/charts/total-kills-value" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Get all TPS charts in a single response
  get "/corp-tools/charts/all" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Send a specific TPS chart to Discord
  get "/corp-tools/charts/send-to-discord/:chart_type" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Send all TPS charts to Discord
  get "/corp-tools/charts/send-all-to-discord" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Trigger the TPS chart scheduler manually
  get "/corp-tools/charts/trigger-scheduler" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Debug endpoint to check TPS data structure
  get "/debug-tps-data" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "CorpTools functionality has been removed"})
    )
  end

  # Helper functions
  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil

  defp calculate_percentage(current, limit) when limit > 0,
    do: min(100, round(current / limit * 100))

  defp calculate_percentage(_, _), do: 0

  # Test kill notification endpoint
  get "/test-notification" do
    Logger.info("Test notification endpoint called")

    result = WandererNotifier.Services.KillProcessor.send_test_kill_notification()

    response =
      case result do
        {:ok, kill_id} ->
          %{
            success: true,
            message: "Test notification sent for kill_id: #{kill_id}",
            details: "Check your Discord for the message."
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Test character notification endpoint
  get "/test-character-notification" do
    Logger.info("Test character notification endpoint called")

    result = send_test_character_notification()

    # Handle the result (should always return {:ok, character_id, character_name} with our changes)
    {:ok, character_id, character_name} = result

    response = %{
      success: true,
      message: "Test character notification sent for #{character_name} (ID: #{character_id})",
      details: "Check your Discord for the message."
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Test system notification endpoint
  get "/test-system-notification" do
    Logger.info("Test system notification endpoint called")

    # Directly call the normal notification pathway instead of using custom test data
    result = NotificationHelpers.send_test_system_notification()

    # Get result data - system ID and name for response
    {:ok, system_id, system_name} = result

    # Send API response
    response = %{
      success: true,
      message: "Test system notification sent for #{system_name} (ID: #{system_id})",
      details: "Check your Discord for the message."
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Check characters endpoint availability
  get "/check-characters-endpoint" do
    Logger.info("Characters endpoint check requested")

    alias WandererNotifier.Api.Map.CharactersClient
    result = CharactersClient.check_characters_endpoint_availability()

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

  # Revalidate license
  get "/revalidate-license" do
    Logger.info("License revalidation requested")

    # Use a more direct approach to avoid potential state issues
    result =
      try do
        # Get the license manager directly
        license_key = Config.license_key()
        notifier_api_token = Config.notifier_api_token()

        # Log what we're doing
        Logger.info("Performing manual license validation")

        # Call the license manager client directly
        case WandererNotifier.LicenseManager.Client.validate_bot(notifier_api_token, license_key) do
          {:ok, response} ->
            # Get validation status directly from response
            license_valid = response["license_valid"] || false

            # Update the GenServer state
            GenServer.call(License, :validate)

            if license_valid do
              %{
                success: true,
                message: "License validation successful",
                details: "License is valid and was revalidated with the server."
              }
            else
              error_msg = response["message"] || "License not valid"
              # Return an explicit error - make sure the success field is false
              %{
                success: false,
                message: "License validation failed: #{error_msg}",
                details: "Error: #{error_msg}"
              }
            end

          {:error, reason} ->
            Logger.error("Direct license validation failed: #{inspect(reason)}")

            error_message =
              case reason do
                :not_found -> "License not found"
                :invalid_notifier_token -> "Invalid notifier token"
                :notifier_not_authorized -> "Notifier not authorized for this license"
                :request_failed -> "Connection to license server failed"
                :api_error -> "API error from license server"
                _ -> "Validation error: #{inspect(reason)}"
              end

            %{
              success: false,
              message: "License validation failed",
              details: "Error: #{error_message}"
            }
        end
      rescue
        e ->
          Logger.error("Exception during license revalidation: #{inspect(e)}")

          %{
            success: false,
            message: "License validation failed",
            details: "Error: #{inspect(e)}"
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  # Get recent kills
  get "/recent-kills" do
    Logger.info("Recent kills endpoint called")

    recent_kills = WandererNotifier.Services.KillProcessor.get_recent_kills()

    response = %{
      success: true,
      kills: recent_kills || []
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Handle test kill notification
  post "/test-kill" do
    case WandererNotifier.Services.KillProcessor.send_test_kill_notification() do
      {:ok, kill_id} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            success: true,
            message: "Test kill notification sent",
            kill_id: kill_id
          })
        )
    end
  end

  #
  # Helper Functions
  #

  #
  # Character Notification
  #
  defp send_test_character_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test character notification")

    # Get tracked characters or use sample if none are available
    tracked_characters = get_and_log_tracked_characters()

    tracked_characters
    |> get_valid_character_for_notification()
    |> send_character_notification()
  end

  # Get tracked characters and log their count
  defp get_and_log_tracked_characters do
    tracked_characters = CacheHelpers.get_tracked_characters()
    Logger.debug("Fetched tracked characters from cache: #{inspect(tracked_characters)}")
    Logger.info("Found #{length(tracked_characters)} tracked characters")
    tracked_characters
  end

  # Find a valid character or return a sample one
  defp get_valid_character_for_notification(tracked_characters) do
    valid_chars = Enum.filter(tracked_characters, &valid_eve_id?/1)
    Logger.debug("Valid characters: #{length(valid_chars)} out of #{length(tracked_characters)}")

    if Enum.empty?(valid_chars) do
      create_sample_character()
    else
      Enum.random(valid_chars)
    end
  end

  # Create a standard sample character for testing
  defp create_sample_character do
    Logger.info("Using sample character for notification")

    %{
      "character_id" => "1354830081",
      "character_name" => "CCP Garthagk",
      "corporation_id" => 98_356_193,
      "corporation_ticker" => "CCP"
    }
  end

  # Send notification with the provided character
  defp send_character_notification(character) do
    {character_id, character_name} = extract_character_details(character)
    Logger.info("Using character #{character_name} (ID: #{character_id}) for test notification")

    # Format the character for notification
    formatted_character = format_character_for_notification(character)

    # Send the notification
    WandererNotifier.Notifiers.Factory.notify(
      :send_new_tracked_character_notification,
      [formatted_character]
    )

    {:ok, character_id, character_name}
  end

  # Extract character details
  defp extract_character_details(character) do
    character_id = extract_character_id(character)
    character_name = extract_character_name(character)

    Logger.info(
      "[APIController] Extracted character details - ID: #{character_id}, Name: #{character_name}"
    )

    {character_id, character_name}
  end

  # Extract character ID from character data
  defp extract_character_id(character) do
    cond do
      is_struct(character) && character.__struct__ == WandererNotifier.Data.Character ->
        character.eve_id

      is_map(character) && Map.has_key?(character, "character_id") ->
        character["character_id"]

      is_map(character) && Map.has_key?(character, "eve_id") ->
        character["eve_id"]

      true ->
        nil
    end
  end

  # Extract character name from character data
  defp extract_character_name(character) do
    cond do
      is_struct(character) && character.__struct__ == WandererNotifier.Data.Character ->
        character.name

      is_map(character) && Map.has_key?(character, "character_name") ->
        character["character_name"]

      is_map(character) && Map.has_key?(character, "name") ->
        character["name"]

      true ->
        "Unknown"
    end
  end

  # Helper to format character data consistently for notification
  defp format_character_for_notification(character) do
    require Logger

    Logger.debug(
      "[APIController] Formatting character for notification: #{inspect(character, pretty: true, limit: 300)}"
    )

    %{
      "character_id" => extract_character_id(character),
      "character_name" => extract_character_name(character),
      "corporation_id" => extract_corporation_id(character),
      "corporation_ticker" => extract_corporation_ticker(character)
    }
  end

  # Extract corporation ID from character data
  defp extract_corporation_id(character) do
    cond do
      is_struct(character) && character.__struct__ == WandererNotifier.Data.Character ->
        character.corporation_id

      is_map(character) && Map.has_key?(character, "corporation_id") ->
        character["corporation_id"]

      true ->
        nil
    end
  end

  # Extract corporation ticker from character data
  defp extract_corporation_ticker(character) do
    cond do
      is_struct(character) && character.__struct__ == WandererNotifier.Data.Character ->
        character.corporation_ticker

      is_map(character) && Map.has_key?(character, "corporation_ticker") ->
        character["corporation_ticker"]

      is_map(character) && Map.has_key?(character, "corporation_name") ->
        character["corporation_name"]

      true ->
        nil
    end
  end

  #
  # Validate EVE ID
  #
  defp valid_eve_id?(character) do
    cond do
      has_valid_direct_id?(character) -> true
      has_valid_nested_character?(character) -> true
      true -> false
    end
  end

  # Check if character has a valid ID directly in its map
  defp has_valid_direct_id?(character) do
    id_keys = ["character_id", "eve_id"]

    Enum.any?(id_keys, fn key ->
      is_binary(character[key]) && NotificationHelpers.valid_numeric_id?(character[key])
    end)
  end

  # Check if character has a valid nested character map
  defp has_valid_nested_character?(character) do
    is_map(character["character"]) && valid_nested?(character["character"])
  end

  # Check if nested map has a valid ID
  defp valid_nested?(nested_map) do
    id_keys = ["eve_id", "character_id", "id"]

    Enum.any?(id_keys, fn key ->
      is_binary(nested_map[key]) && NotificationHelpers.valid_numeric_id?(nested_map[key])
    end)
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
