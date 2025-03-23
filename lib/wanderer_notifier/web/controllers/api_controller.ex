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
  alias WandererNotifier.Services.CharacterKillsService

  # Module attributes
  @api_version "1.0.0"
  @service_start_time System.monotonic_time(:millisecond)

  plug(:match)
  plug(:dispatch)

  ####################
  # Health and Status #
  ####################

  # Health check endpoint
  get "/health" do
    # Get the start time for response time measurement
    start_time = System.monotonic_time(:millisecond)

    # Get the service uptime
    uptime_ms = System.monotonic_time(:millisecond) - @service_start_time
    uptime_seconds = div(uptime_ms, 1000)
    uptime_minutes = div(uptime_seconds, 60)
    uptime_hours = div(uptime_minutes, 60)
    uptime_days = div(uptime_hours, 24)

    # Calculate response time
    response_time = System.monotonic_time(:millisecond) - start_time

    # Prepare the health response
    health_response = %{
      status: "ok",
      version: @api_version,
      uptime: %{
        days: uptime_days,
        hours: rem(uptime_hours, 24),
        minutes: rem(uptime_minutes, 60),
        seconds: rem(uptime_seconds, 60)
      },
      response_time_ms: response_time
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(health_response))
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

  ####################
  # Tracking & Characters #
  ####################

  # Fetch character kills endpoint - simplified for just loading all tracked characters
  get "/character-kills" do
    Logger.info("Character kills fetch endpoint called")

    # Get query parameters
    conn_params = conn.query_params
    all_characters = Map.get(conn_params, "all", "false") |> parse_boolean()
    limit = Map.get(conn_params, "limit", "25") |> parse_integer(25)
    page = Map.get(conn_params, "page", "1") |> parse_integer(1)

    # Check if kill charts is enabled
    if Config.kill_charts_enabled?() do
      if all_characters do
        # Fetch kills for all tracked characters
        Logger.info("Fetching kills for all tracked characters")

        case CharacterKillsService.fetch_and_persist_all_tracked_character_kills(limit, page) do
          {:ok, stats} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              200,
              Jason.encode!(%{
                success: true,
                message: "Character kills fetched and processed successfully",
                details: stats
              })
            )

          {:error, {:domain_error, :zkill, {:api_error, error_msg}}} ->
            # Handle ZKill API errors specifically
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              502,
              Jason.encode!(%{
                success: false,
                message: "ZKill API error",
                details: error_msg
              })
            )

          {:error, reason} ->
            # Better error details
            error_message =
              case reason do
                {:domain_error, domain, details} -> "Error from #{domain}: #{inspect(details)}"
                _ -> inspect(reason)
              end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                success: false,
                message: "Failed to fetch and process character kills",
                details: "Error: #{error_message}"
              })
            )
        end
      else
        # Simplified to redirect to all=true
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            success: false,
            message: "This endpoint only supports fetching all characters",
            details: "Please use ?all=true parameter"
          })
        )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          success: false,
          message: "Kill charts feature is not enabled",
          details: "Enable the ENABLE_KILL_CHARTS environment variable to use this feature"
        })
      )
    end
  end

  # Helper functions
  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil

  defp calculate_percentage(current, limit) when limit > 0,
    do: min(100, round(current / limit * 100))

  defp calculate_percentage(_, _), do: 0

  # Helper functions for parameter parsing

  # Safely parses an integer value with fallback
  defp parse_integer(value, default)
  defp parse_integer(nil, default), do: default
  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  # Parse boolean helper
  defp parse_boolean(value, default \\ false)
  defp parse_boolean(nil, default), do: default
  defp parse_boolean(value, _default) when is_boolean(value), do: value
  defp parse_boolean("true", _default), do: true
  defp parse_boolean("1", _default), do: true
  defp parse_boolean(_, _default), do: false

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
    valid_chars = Enum.filter(tracked_characters, &valid_character_id?/1)
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
        character.character_id

      is_map(character) && Map.has_key?(character, "character_id") ->
        character["character_id"]

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

    # Always prioritize EVE ID
    character_id = extract_character_id(character)

    %{
      "character_id" => character_id,
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
  # Validate character ID
  #
  defp valid_character_id?(character) do
    cond do
      has_valid_direct_id?(character) -> true
      has_valid_nested_character?(character) -> true
      true -> false
    end
  end

  # Check if character has a valid ID directly in its map
  defp has_valid_direct_id?(character) do
    # Only check character_id
    id_keys = ["character_id"]

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
    # Only check character_id keys
    id_keys = ["character_id", "id"]

    Enum.any?(id_keys, fn key ->
      is_binary(nested_map[key]) && NotificationHelpers.valid_numeric_id?(nested_map[key])
    end)
  end

  # Return list of tracked characters
  get "/tracked-characters" do
    try do
      # Get tracked characters with more robust error handling
      tracked_characters =
        try do
          # Use CacheHelpers to get a properly formatted list
          WandererNotifier.Helpers.CacheHelpers.get_tracked_characters()
        rescue
          e ->
            Logger.error("Error getting tracked characters: #{inspect(e)}")
            []
        end

      # Log how many characters we found
      Logger.info("Returning #{length(tracked_characters)} tracked characters")

      # Ensure each character has at least the required ID and name fields
      formatted_characters =
        Enum.map(tracked_characters, fn character ->
          case character do
            # String ID case
            id when is_binary(id) or is_integer(id) ->
              %{
                character_id: to_string(id),
                character_name: "Character #{id}"
              }

            # Map case but needs normalization
            %{} = char_map ->
              # Extract ID from various possible keys
              id =
                char_map[:character_id] || char_map["character_id"] ||
                  char_map[:id] || char_map["id"]

              # Extract name from various possible keys
              name =
                char_map[:character_name] || char_map["character_name"] ||
                  char_map[:name] || char_map["name"] ||
                  "Character #{id}"

              # Return a standardized map
              %{
                character_id: id && to_string(id),
                character_name: name
              }

            # Unknown format, return empty map with log
            other ->
              Logger.warning("Unknown character format: #{inspect(other)}")
              %{character_id: nil, character_name: "Unknown"}
          end
        end)
        |> Enum.filter(fn %{character_id: id} -> id != nil end)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          success: true,
          characters: formatted_characters
        })
      )
    rescue
      e ->
        Logger.error("Error in tracked-characters endpoint: #{inspect(e)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            success: false,
            message: "Internal server error",
            error: inspect(e)
          })
        )
    end
  end

  #####################
  # ZKill Integration  #
  #####################

  # Sync tracked characters from cache to Ash resource
  get "/sync-characters" do
    Logger.info("Triggering sync of tracked characters from cache to Ash resource")

    # Inspect the map cache first
    cached_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []
    Logger.info("Found #{length(cached_characters)} characters in map cache")

    # Log some sample characters to check their format
    if length(cached_characters) > 0 do
      sample = Enum.take(cached_characters, min(5, length(cached_characters)))
      Logger.info("Sample characters from cache: #{inspect(sample)}")
    end

    # Call the sync function
    case WandererNotifier.Resources.TrackedCharacter.sync_from_cache() do
      {:ok, stats} ->
        # Get count after sync
        ash_count_result =
          WandererNotifier.Resources.TrackedCharacter
          |> WandererNotifier.Resources.Api.read()

        ash_count =
          case ash_count_result do
            {:ok, chars} -> length(chars)
            _ -> 0
          end

        Logger.info("After sync: Ash resource now has #{ash_count} characters")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            success: true,
            message: "Characters synced successfully",
            details: Map.put(stats, :ash_count, ash_count)
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            success: false,
            message: "Failed to sync characters",
            details: inspect(reason)
          })
        )
    end
  end

  # Force sync map characters to Ash resource and vice versa
  get "/force-sync-characters" do
    Logger.info("Triggering forced character synchronization")

    # Get all relevant caches
    map_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []

    tracked_characters_cache =
      WandererNotifier.Data.Cache.Repository.get("tracked:characters") || []

    all_from_helper = WandererNotifier.Helpers.CacheHelpers.get_tracked_characters()

    # Get characters from the Ash resource
    ash_result =
      WandererNotifier.Resources.TrackedCharacter
      |> WandererNotifier.Resources.Api.read()

    ash_characters =
      case ash_result do
        {:ok, chars} -> chars
        _ -> []
      end

    # Log the current state of all caches
    Logger.info("Before sync: map:characters has #{length(map_characters)} characters")

    Logger.info(
      "Before sync: tracked:characters has #{length(tracked_characters_cache)} characters"
    )

    Logger.info(
      "Before sync: CacheHelpers.get_tracked_characters() returns #{length(all_from_helper)} characters"
    )

    Logger.info("Before sync: Ash resource has #{length(ash_characters)} characters")

    # Perform the sync operation directly (not in a spawned process)
    sync_result = WandererNotifier.Resources.TrackedCharacter.sync_from_cache()

    # Get counts after sync
    ash_result_after =
      WandererNotifier.Resources.TrackedCharacter
      |> WandererNotifier.Resources.Api.read()

    ash_count_after =
      case ash_result_after do
        {:ok, chars} -> length(chars)
        _ -> 0
      end

    response_data =
      case sync_result do
        {:ok, stats} ->
          %{
            success: true,
            message: "Character synchronization completed successfully",
            details: %{
              map_cache_count: length(map_characters),
              tracked_cache_count: length(tracked_characters_cache),
              helper_combined_count: length(all_from_helper),
              ash_count_before: length(ash_characters),
              ash_count_after: ash_count_after,
              sync_stats: stats
            }
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Character synchronization failed",
            details: %{
              error: inspect(reason),
              map_cache_count: length(map_characters),
              tracked_cache_count: length(tracked_characters_cache),
              helper_combined_count: length(all_from_helper),
              ash_count_before: length(ash_characters),
              ash_count_after: ash_count_after
            }
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response_data))
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
