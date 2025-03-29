defmodule WandererNotifier.Web.Controllers.ApiController do
  @moduledoc """
  API controller for the web interface.
  """
  use Plug.Router
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.{Config, License, Stats}
  alias WandererNotifier.Data.Cache.Repository
  alias WandererNotifier.Helpers.{CacheHelpers, NotificationHelpers}
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Repo
  alias WandererNotifier.Resources.{KillmailPersistence, TrackedCharacter}
  alias WandererNotifier.Services.{CharacterKillsService, KillmailComparison, Service}

  # Module attributes
  @api_version "1.0.0"
  @service_start_time System.monotonic_time(:millisecond)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

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
      license_status = License.status()

      license_info = %{
        valid: license_status[:valid],
        bot_assigned: license_status[:bot_assigned],
        details: license_status[:details],
        error: license_status[:error],
        error_message: license_status[:error_message]
      }

      stats = Stats.get_stats()
      features = Features
      limits = features.get_all_limits()

      # Add error handling for tracked systems and characters
      tracked_systems = get_tracked_systems_safely()
      tracked_characters = get_tracked_characters_safely()

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
            kill_charts: features.kill_charts_enabled?(),
            map_charts: features.map_charts_enabled?()
          },
          config: %{
            character_tracking_enabled: Features.character_tracking_enabled?(),
            character_notifications_enabled: Features.character_notifications_enabled?(),
            system_notifications_enabled: Features.system_notifications_enabled?()
          }
        }
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    rescue
      e ->
        AppLogger.api_error("Error processing status endpoint",
          error: inspect(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Internal server error", details: inspect(e)}))
    end
  end

  # Helper function to safely get tracked systems
  defp get_tracked_systems_safely do
    CacheHelpers.get_tracked_systems()
  rescue
    e ->
      AppLogger.api_error("Error retrieving tracked systems",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      []
  end

  # Helper function to safely get tracked characters
  defp get_tracked_characters_safely do
    Repository.get("map:characters") || []
  rescue
    e ->
      AppLogger.api_error("Error retrieving tracked characters",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      []
  end

  # Database statistics endpoint for the dashboard
  get "/db-stats" do
    try do
      # Check if kill charts is enabled
      if Features.kill_charts_enabled?() do
        # Check if database operations are enabled
        if TrackedCharacter.database_enabled?() do
          # Get killmail statistics
          killmail_stats = KillmailPersistence.get_tracked_kills_stats()

          # Get database health status
          db_health =
            case Repo.health_check() do
              {:ok, ping_time} -> %{status: "connected", ping_ms: ping_time}
              {:error, reason} -> %{status: "error", reason: inspect(reason)}
            end

          # Combine all DB statistics
          db_stats = %{
            killmail: killmail_stats,
            db_health: db_health
          }

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{success: true, stats: db_stats}))
        else
          # Database is disabled but kill charts is enabled (unusual state)
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              success: true,
              stats: %{
                killmail: %{tracked_characters: 0, total_kills: 0},
                db_health: %{status: "disabled", reason: "Database operations are disabled"}
              }
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
            message: "Kill charts functionality is not enabled"
          })
        )
      end
    rescue
      e ->
        AppLogger.api_error("Error processing db-stats endpoint",
          error: inspect(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            success: false,
            error: "Internal server error",
            details: inspect(e)
          })
        )
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

  # New endpoint for getting kill stats
  get "/character-kills/stats" do
    AppLogger.api_info("Character kills stats endpoint called")

    # Check if kill charts is enabled
    if Features.kill_charts_enabled?() do
      # Get stats using KillmailPersistence
      stats = KillmailPersistence.get_tracked_kills_stats()

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          success: true,
          tracked_characters: stats.tracked_characters,
          total_kills: stats.total_kills
        })
      )
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          success: false,
          message: "Kill charts feature is not enabled",
          tracked_characters: 0,
          total_kills: 0
        })
      )
    end
  end

  # Fetch character kills endpoint - simplified for just loading all tracked characters
  get "/character-kills" do
    AppLogger.api_info("Character kills fetch endpoint called")

    # Get query parameters
    conn_params = conn.query_params
    all_characters = Map.get(conn_params, "all", "false") |> parse_boolean()
    limit = Map.get(conn_params, "limit", "25") |> parse_integer(25)
    page = Map.get(conn_params, "page", "1") |> parse_integer(1)

    # Check if kill charts is enabled
    if Features.kill_charts_enabled?() do
      if all_characters do
        # Fetch kills for all tracked characters
        AppLogger.api_info("Fetching kills for all tracked characters",
          limit: limit,
          page: page
        )

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

          {:error, :no_tracked_characters} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              404,
              Jason.encode!(%{
                success: false,
                message: "No tracked characters found"
              })
            )

          {:error, :no_successful_results} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                success: false,
                message: "Failed to process any character kills successfully"
              })
            )

          {:error, reason} ->
            AppLogger.api_error("Failed to fetch character kills",
              error: inspect(reason)
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                success: false,
                message: "Failed to fetch character kills",
                details: inspect(reason)
              })
            )
        end
      else
        # Handle case for single character ID
        character_id = Map.get(conn_params, "character_id")

        if character_id do
          # Convert string to integer if possible
          character_id_int =
            case Integer.parse(character_id) do
              {id, _} -> id
              :error -> character_id
            end

          AppLogger.api_info("Fetching kills for character ID #{character_id_int}")

          case CharacterKillsService.fetch_and_persist_character_kills(
                 character_id_int,
                 limit,
                 page
               ) do
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

            {:error, reason} ->
              AppLogger.api_error("Failed to fetch character kills",
                character_id: character_id_int,
                error: inspect(reason)
              )

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(
                500,
                Jason.encode!(%{
                  success: false,
                  message: "Failed to fetch character kills",
                  details: inspect(reason)
                })
              )
          end
        else
          # No character ID provided and all=false
          AppLogger.api_warn("No character ID provided for kills fetch")

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              success: false,
              message: "No character ID provided"
            })
          )
        end
      end
    else
      AppLogger.api_info("Kill charts feature is not enabled for kills fetch")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          success: false,
          message: "Kill charts feature is not enabled"
        })
      )
    end
  end

  # Get aggregation statistics
  get "/killmail-aggregation-stats" do
    AppLogger.api_info("Killmail aggregation stats requested")

    # Check if kill charts is enabled
    if Features.kill_charts_enabled?() do
      # Check if database operations are enabled
      if TrackedCharacter.database_enabled?() do
        try do
          # Get total statistics count
          query = "SELECT COUNT(*) FROM killmail_statistics"
          {:ok, %{rows: [[total_stats]]}} = Repo.query(query)

          # Get count of characters with aggregated stats
          query = "SELECT COUNT(DISTINCT character_id) FROM killmail_statistics"
          {:ok, %{rows: [[aggregated_characters]]}} = Repo.query(query)

          # Get the most recent aggregation date
          query = "SELECT MAX(inserted_at) FROM killmail_statistics"
          {:ok, %{rows: [[last_aggregation]]}} = Repo.query(query)

          # Format the date nicely if it exists
          formatted_date =
            if last_aggregation do
              # Convert to human-readable format
              DateTime.from_naive!(last_aggregation, "Etc/UTC")
              |> DateTime.to_string()
            else
              nil
            end

          AppLogger.api_info("Retrieved aggregation statistics",
            total_stats: total_stats,
            aggregated_characters: aggregated_characters,
            last_update: formatted_date
          )

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              success: true,
              stats: %{
                total_stats: total_stats,
                aggregated_characters: aggregated_characters,
                last_aggregation: formatted_date
              }
            })
          )
        rescue
          e ->
            AppLogger.api_error("Failed to fetch aggregation statistics",
              error: Exception.message(e),
              stacktrace: Exception.format_stacktrace(__STACKTRACE__)
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                success: false,
                message: "Error fetching aggregation statistics",
                error: Exception.message(e)
              })
            )
        end
      else
        # Database operations are disabled
        AppLogger.api_info("Database operations are disabled for aggregation stats")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            success: true,
            message: "Database operations are disabled",
            stats: %{
              total_stats: 0,
              aggregated_characters: 0,
              last_aggregation: nil
            }
          })
        )
      end
    else
      AppLogger.api_info("Kill charts feature not enabled for aggregation stats")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          success: false,
          message: "Kill charts feature is not enabled"
        })
      )
    end
  end

  # Sync tracked characters from cache to database
  get "/sync-tracked-characters" do
    AppLogger.api_info("Sync tracked characters endpoint called")

    if Features.kill_charts_enabled?() do
      # Try to sync characters
      case TrackedCharacter.sync_from_cache() do
        {:ok, result} ->
          # Get the counts from the result
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              success: true,
              message: "Successfully synced tracked characters",
              details: %{
                successes: result.successes,
                failures: result.failures
              }
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              success: false,
              message: "Failed to sync tracked characters",
              details: inspect(reason)
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
          message: "Kill charts feature is not enabled"
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
    AppLogger.api_info("Test notification endpoint called")

    # Use NotificationHelpers instead of CharacterKillsService
    result = NotificationHelpers.send_test_kill_notification()

    response =
      case result do
        {:ok, kill_id} ->
          %{
            success: true,
            message: "Test notification sent for kill_id: #{kill_id}",
            details: "Check your Discord for the message."
          }
        {:error, reason} ->
          %{
            success: false,
            message: "Failed to send test notification",
            details: reason
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Test character notification endpoint
  get "/test-character-notification" do
    AppLogger.api_info("Test character notification endpoint called")

    result = NotificationHelpers.send_test_character_notification()

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
    AppLogger.api_info("Test system notification endpoint called")

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
    AppLogger.api_info("Characters endpoint check requested")

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
    AppLogger.api_info("License revalidation requested")

    # Use a more direct approach to avoid potential state issues
    result =
      try do
        # Get the license manager directly
        license_key = Config.license_key()
        notifier_api_token = Config.notifier_api_token()

        # Log what we're doing
        AppLogger.api_info("Performing license validation",
          license_key_length: String.length(license_key || ""),
          has_api_token: notifier_api_token != nil
        )

        alias WandererNotifier.LicenseManager.Client, as: LicenseClient
        # Call the license manager client directly
        case LicenseClient.validate_bot(notifier_api_token, license_key) do
          {:ok, response} ->
            # Get validation status directly from response
            license_valid = response["license_valid"] || false

            # Update the GenServer state
            GenServer.call(License, :validate)

            AppLogger.api_info("License validation completed",
              success: license_valid,
              message: response["message"]
            )

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
            AppLogger.api_error("License validation failed",
              reason: inspect(reason)
            )

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
          AppLogger.api_error("Exception during license revalidation: #{inspect(e)}")

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
    AppLogger.api_info("Recent kills endpoint called")

    # Use Service module to get recent kills
    recent_kills = Service.get_recent_kills()

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
    # Use NotificationHelpers instead of CharacterKillsService
    case NotificationHelpers.send_test_kill_notification() do
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
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            success: false,
            message: "Failed to send test notification",
            error: reason
          })
        )
    end
  end

  #
  # Helper Functions
  #

  # Removed unused function send_test_character_notification

  # Removed unused function get_and_log_tracked_characters

  # Removed unused function get_valid_character_for_notification

  # Removed unused function create_sample_character

  # Removed unused function send_character_notification

  # Removed unused function extract_character_details

  # Removed unused character ID and validation functions

  # Return list of tracked characters
  get "/characters" do
    try do
      # Get tracked characters with more robust error handling
      tracked_characters =
        try do
          # Use CacheHelpers to get a properly formatted list
          CacheHelpers.get_tracked_characters()
        rescue
          e ->
            AppLogger.api_error("Error getting tracked characters: #{inspect(e)}")
            []
        end

      # Log how many characters we found
      AppLogger.api_info("Returning #{length(tracked_characters)} tracked characters")

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
              AppLogger.api_warn("Unknown character format: #{inspect(other)}")
              %{character_id: nil, character_name: "Unknown"}
          end
        end)
        |> Enum.filter(fn %{character_id: id} -> id != nil end)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(formatted_characters))
    rescue
      e ->
        AppLogger.api_error("Error in characters endpoint: #{inspect(e)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!([]))
    end
  end

  #####################
  # ZKill Integration  #
  #####################

  # Sync tracked characters from cache to Ash resource
  get "/sync-characters" do
    AppLogger.api_info("Triggering sync of tracked characters from cache to Ash resource")

    # Inspect the map cache first
    cached_characters = Repository.get("map:characters") || []
    AppLogger.api_info("Found #{length(cached_characters)} characters in map cache")

    # Log some sample characters to check their format
    if length(cached_characters) > 0 do
      sample = Enum.take(cached_characters, min(5, length(cached_characters)))
      AppLogger.api_info("Sample characters from cache: #{inspect(sample)}")
    end

    # Call the sync function
    case TrackedCharacter.sync_from_cache() do
      {:ok, stats} ->
        # Get count after sync
        ash_count_result = TrackedCharacter.list_all()

        ash_count =
          case ash_count_result do
            {:ok, chars} -> length(chars)
            _ -> 0
          end

        AppLogger.api_info("After sync: Ash resource now has #{ash_count} characters")

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
    AppLogger.api_info("Triggering forced character synchronization")

    # Get all relevant caches
    map_characters = Repository.get("map:characters") || []

    tracked_characters_cache =
      Repository.get("tracked:characters") || []

    all_from_helper = CacheHelpers.get_tracked_characters()

    # Get characters from the Ash resource
    ash_result =
      TrackedCharacter.list_all()

    ash_characters =
      case ash_result do
        {:ok, chars} -> chars
        _ -> []
      end

    # Log the current state of all caches
    AppLogger.api_info("Before sync: map:characters has #{length(map_characters)} characters")

    AppLogger.api_info(
      "Before sync: tracked:characters has #{length(tracked_characters_cache)} characters"
    )

    AppLogger.api_info(
      "Before sync: CacheHelpers.get_tracked_characters() returns #{length(all_from_helper)} characters"
    )

    AppLogger.api_info("Before sync: Ash resource has #{length(ash_characters)} characters")

    # Perform the sync operation directly (not in a spawned process)
    sync_result = TrackedCharacter.sync_from_cache()

    # Get counts after sync
    ash_result_after = TrackedCharacter.list_all()

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

  # Compare kills for a character in the last 24 hours
  get "/kills/compare" do
    try do
      # Log raw query parameters
      AppLogger.api_info("Raw query parameters received", %{
        params: conn.query_params,
        param_details: %{
          character_id: %{
            value: conn.query_params["character_id"],
            type: get_type(conn.query_params["character_id"])
          },
          start_date: %{
            value: conn.query_params["start_date"],
            type: get_type(conn.query_params["start_date"])
          },
          end_date: %{
            value: conn.query_params["end_date"],
            type: get_type(conn.query_params["end_date"])
          },
          include_breakdown: %{
            value: conn.query_params["include_breakdown"],
            type: get_type(conn.query_params["include_breakdown"])
          }
        }
      })

      # Extract and validate parameters
      character_id = conn.query_params["character_id"]
      start_date = conn.query_params["start_date"]
      end_date = conn.query_params["end_date"]
      include_breakdown = conn.query_params["include_breakdown"] == "true"

      AppLogger.api_info("Kill comparison requested", %{
        character_id: character_id,
        start_date: start_date,
        end_date: end_date,
        include_breakdown: include_breakdown
      })

      # Parse parameters with better error handling
      with {character_id_int, ""} <- Integer.parse(character_id),
           {:ok, start_datetime} <- parse_date_string(start_date),
           {:ok, end_datetime} <- parse_date_string(end_date) do
        AppLogger.api_info("Parsed parameters for kill comparison", %{
          character_id: character_id_int,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        })

        case KillmailComparison.compare_killmails(
               character_id_int,
               start_datetime,
               end_datetime
             ) do
          {:ok, comparison_result} ->
            # Add character breakdown if requested
            result_with_breakdown =
              if include_breakdown do
                # Fetch all characters
                case TrackedCharacter.list_all() do
                  {:ok, characters} ->
                    # For each character, calculate data
                    character_breakdowns =
                      generate_character_breakdowns(
                        characters,
                        start_datetime,
                        end_datetime
                      )

                    # Add to response
                    Map.put(comparison_result, :character_breakdown, character_breakdowns)

                  _ ->
                    # If we can't get characters, just return the regular result
                    comparison_result
                end
              else
                comparison_result
              end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(result_with_breakdown))

          {:error, reason} ->
            AppLogger.api_error("Error comparing kills", %{
              error: inspect(reason),
              character_id: character_id_int
            })

            # Return empty results with error message
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                kills_found: [],
                kills_missing: [],
                total_kills: 0,
                coverage_percentage: 0,
                error: "Failed to fetch kills: #{inspect(reason)}"
              })
            )
        end
      else
        :error ->
          AppLogger.api_error("Invalid character ID format", character_id: character_id)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              error: "Invalid character ID format",
              success: false
            })
          )

        {:error, reason} ->
          AppLogger.api_error("Invalid date format", error: inspect(reason))

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              error: "Invalid date format. Expected ISO-8601 format (e.g. 2024-03-24T18:42:00Z)",
              success: false
            })
          )
      end
    rescue
      e ->
        AppLogger.api_error("Error in kills/compare endpoint", error: Exception.message(e))

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            error: "Internal server error",
            success: false,
            details: Exception.message(e)
          })
        )
    end
  end

  # Analyze missing kills
  post "/kills/analyze-missing" do
    try do
      # Log request info
      AppLogger.api_info("Received analyze-missing request", %{
        headers: conn.req_headers,
        content_type: get_req_header(conn, "content-type"),
        content_length: get_req_header(conn, "content-length"),
        method: conn.method,
        request_path: conn.request_path,
        body_params: conn.body_params
      })

      character_id = conn.body_params["character_id"]
      kill_ids = conn.body_params["kill_ids"]

      if is_nil(character_id) or is_nil(kill_ids) do
        AppLogger.api_error("Missing required parameters", %{
          character_id: character_id,
          has_kill_ids: not is_nil(kill_ids)
        })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            error: "Missing required parameters",
            details: "Both character_id and kill_ids are required"
          })
        )
      else
        AppLogger.api_info("Analyzing missing kills", %{
          character_id: character_id,
          kill_ids_count: length(kill_ids)
        })

        case KillmailComparison.analyze_missing_kills(
               character_id,
               kill_ids
             ) do
          {:ok, analysis} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(analysis))

          # Update to handle a potential error case more generically
          # The warning suggests this function only returns {:ok, term()} currently
          error ->
            AppLogger.api_error("Failed to analyze missing kills", %{
              error: inspect(error),
              character_id: character_id
            })

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                error: "Failed to analyze missing kills",
                details: inspect(error)
              })
            )
        end
      end
    rescue
      e ->
        AppLogger.api_error("Error in analyze-missing endpoint", error: Exception.message(e))

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            error: "Internal server error",
            success: false,
            details: Exception.message(e)
          })
        )
    end
  end

  # Compare kills for all characters within a date range
  get "/kills/compare-all" do
    try do
      # Log raw query parameters
      AppLogger.api_info("Raw query parameters received for compare-all", %{
        params: conn.query_params,
        param_details: %{
          start_date: %{
            value: conn.query_params["start_date"],
            type: get_type(conn.query_params["start_date"])
          },
          end_date: %{
            value: conn.query_params["end_date"],
            type: get_type(conn.query_params["end_date"])
          }
        }
      })

      # Extract and validate parameters
      start_date = conn.query_params["start_date"]
      end_date = conn.query_params["end_date"]

      AppLogger.api_info("Kill comparison for all characters requested", %{
        start_date: start_date,
        end_date: end_date
      })

      # Parse parameters with better error handling
      with {:ok, start_datetime} <- parse_date_string(start_date),
           {:ok, end_datetime} <- parse_date_string(end_date) do
        AppLogger.api_info("Parsed parameters for all characters comparison", %{
          start_datetime: start_datetime,
          end_datetime: end_datetime
        })

        # Calculate a cache key based on the time range
        cache_key =
          "kill_comparison:all:#{DateTime.to_iso8601(start_datetime)}:#{DateTime.to_iso8601(end_datetime)}"

        # Try to get data from cache first
        case Repository.get(cache_key) do
          nil ->
            # Not in cache, generate the data
            AppLogger.api_info("Cache miss for kill comparison data, generating fresh data")

            # Fetch all tracked characters
            case TrackedCharacter.list_all() do
              {:ok, characters} ->
                # Generate comparison data for each character using the KillmailComparison service
                character_comparisons =
                  KillmailComparison.generate_character_breakdowns(
                    characters,
                    start_datetime,
                    end_datetime
                  )

                # Cache the generated data for 1 hour (3600 seconds)
                # This provides a reasonable balance between freshness and performance
                cache_ttl = 3600

                comparison_data = %{
                  character_breakdown: character_comparisons,
                  count: length(character_comparisons),
                  time_range: %{
                    start_date: DateTime.to_iso8601(start_datetime),
                    end_date: DateTime.to_iso8601(end_datetime)
                  },
                  cached_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                  cache_expires_at:
                    DateTime.utc_now()
                    |> DateTime.add(cache_ttl, :second)
                    |> DateTime.to_iso8601()
                }

                # Store in cache
                Repository.set(cache_key, comparison_data, cache_ttl)
                AppLogger.api_info("Cached comparison data", ttl_seconds: cache_ttl)

                # Return the freshly generated data
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(200, Jason.encode!(comparison_data))

              {:error, reason} ->
                AppLogger.api_error("Error fetching characters", %{
                  error: inspect(reason)
                })

                conn
                |> put_resp_content_type("application/json")
                |> send_resp(
                  500,
                  Jason.encode!(%{
                    error: "Failed to fetch tracked characters",
                    details: inspect(reason),
                    success: false
                  })
                )
            end

          cached_data ->
            # Cache hit - return the cached data
            AppLogger.api_info("Cache hit for kill comparison data",
              cached_at: cached_data[:cached_at],
              expires_at: cached_data[:cache_expires_at]
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(cached_data))
        end
      else
        {:error, reason} ->
          AppLogger.api_error("Invalid date format", error: inspect(reason))

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              error: "Invalid date format. Expected ISO-8601 format (e.g. 2024-03-24T18:42:00Z)",
              success: false
            })
          )
      end
    rescue
      e ->
        AppLogger.api_error("Error in kills/compare-all endpoint", error: Exception.message(e))

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            error: "Internal server error",
            success: false,
            details: Exception.message(e)
          })
        )
    end
  end

  # Get cached comparison data with pre-generated timeframes
  get "/kills/compare-cache" do
    try do
      cache_type = conn.query_params["type"] || "1h"

      # Define time ranges based on the requested type
      {start_datetime, end_datetime} =
        case cache_type do
          "1h" -> {DateTime.utc_now() |> DateTime.add(-3600, :second), DateTime.utc_now()}
          "4h" -> {DateTime.utc_now() |> DateTime.add(-14_400, :second), DateTime.utc_now()}
          "12h" -> {DateTime.utc_now() |> DateTime.add(-43_200, :second), DateTime.utc_now()}
          "24h" -> {DateTime.utc_now() |> DateTime.add(-86_400, :second), DateTime.utc_now()}
          "7d" -> {DateTime.utc_now() |> DateTime.add(-604_800, :second), DateTime.utc_now()}
          _ -> {DateTime.utc_now() |> DateTime.add(-3600, :second), DateTime.utc_now()}
        end

      AppLogger.api_info("Requested cached comparison data", %{
        type: cache_type,
        start_time: DateTime.to_iso8601(start_datetime),
        end_time: DateTime.to_iso8601(end_datetime)
      })

      # Generate the cache key
      cache_key = "kill_comparison:#{cache_type}"

      # Check if data exists in cache already
      case Repository.get(cache_key) do
        nil ->
          # Not in cache - generate and store it using the KillmailComparison service
          case KillmailComparison.generate_and_cache_comparison_data(
                 cache_type,
                 start_datetime,
                 end_datetime
               ) do
            {:ok, comparison_data} ->
              # Return the cached data
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(comparison_data))

            {:error, reason} ->
              AppLogger.api_error("Failed to generate comparison data", %{
                error: inspect(reason)
              })

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(
                500,
                Jason.encode!(%{
                  error: "Failed to generate comparison data",
                  details: inspect(reason),
                  success: false
                })
              )
          end

        cached_data ->
          # Return the cached data
          AppLogger.api_info("Cache hit for pre-generated comparison data", type: cache_type)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(cached_data))
      end
    rescue
      e ->
        AppLogger.api_error("Error in kills/compare-cache endpoint", error: Exception.message(e))

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            error: "Internal server error",
            success: false,
            details: Exception.message(e)
          })
        )
    end
  end

  # Helper function to parse date strings - expects ISO8601 format with timezone
  defp parse_date_string(date_str) do
    AppLogger.api_info("Parsing ISO8601 date string", %{
      raw_string: date_str
    })

    # First try parsing with NaiveDateTime to handle milliseconds
    case NaiveDateTime.from_iso8601(date_str) do
      {:ok, naive_dt} ->
        # Convert to UTC DateTime
        {:ok, DateTime.from_naive!(naive_dt, "Etc/UTC")}

      {:error, _} ->
        # Fallback to DateTime.from_iso8601 if NaiveDateTime fails
        case DateTime.from_iso8601(date_str) do
          {:ok, datetime, _offset} ->
            AppLogger.api_info("Successfully parsed ISO8601 date", %{
              datetime: inspect(datetime)
            })

            {:ok, datetime}

          {:error, reason} ->
            AppLogger.api_error("Failed to parse ISO8601 date", %{
              error: inspect(reason),
              raw_string: date_str
            })

            {:error, :invalid_format}
        end
    end
  end

  # Helper function to get the type of a value
  defp get_type(value) when is_binary(value), do: "string"
  defp get_type(value) when is_integer(value), do: "integer"
  defp get_type(value) when is_float(value), do: "float"
  defp get_type(value) when is_boolean(value), do: "boolean"
  defp get_type(value) when is_nil(value), do: "nil"
  defp get_type(value) when is_map(value), do: "map"
  defp get_type(value) when is_list(value), do: "list"
  defp get_type(value), do: inspect(value.__struct__)

  # Helper function to delegate to the KillmailComparison service
  defp generate_character_breakdowns(characters, start_datetime, end_datetime) do
    KillmailComparison.generate_character_breakdowns(
      characters,
      start_datetime,
      end_datetime
    )
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
