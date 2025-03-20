defmodule WandererNotifier.Web.Controllers.ApiController do
  @moduledoc """
  API controller for the web interface.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.CorpTools.CorpToolsClient
  alias WandererNotifier.ChartService.TPSChartAdapter
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
            character_tracking_enabled: WandererNotifier.Core.Config.character_tracking_enabled?(),
            character_notifications_enabled: WandererNotifier.Core.Config.character_notifications_enabled?(),
            system_notifications_enabled: WandererNotifier.Core.Config.system_notifications_enabled?()
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

  # Test EVE Corp Tools API integration
  get "/test-corp-tools" do
    case CorpToolsClient.health_check() do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{status: "ok", message: "EVE Corp Tools API is operational"})
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            status: "error",
            message: "EVE Corp Tools API health check failed",
            reason: inspect(reason)
          })
        )
    end
  end

  # Get tracked entities from EVE Corp Tools API
  get "/corp-tools/tracked" do
    case CorpToolsClient.get_tracked_entities() do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            status: "error",
            message: "Failed to get tracked entities",
            reason: inspect(reason)
          })
        )
    end
  end

  # Get optimized TPS data for charts from EVE Corp Tools API
  get "/corp-tools/recent-tps-data" do
    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))

      {:loading, message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(206, Jason.encode!(%{status: "loading", message: message}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            status: "error",
            message: "Failed to get recent TPS data",
            reason: inspect(reason)
          })
        )
    end
  end

  # Refresh TPS data on EVE Corp Tools API
  get "/corp-tools/refresh-tps" do
    case CorpToolsClient.refresh_tps_data() do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", message: "TPS data refresh triggered"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            status: "error",
            message: "Failed to trigger TPS data refresh",
            reason: inspect(reason)
          })
        )
    end
  end

  # Appraise loot using EVE Corp Tools API
  post "/corp-tools/appraise-loot" do
    {:ok, body, conn} = read_body(conn)

    case CorpToolsClient.appraise_loot(body) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            status: "error",
            message: "Failed to appraise loot",
            reason: inspect(reason)
          })
        )
    end
  end

  # Special endpoint to handle all three TPS chart types
  get "/corp-tools/charts/:chart_type" do
    chart_type =
      case conn.params["chart_type"] do
        "kills-by-ship-type" -> :kills_by_ship_type
        "kills-by-month" -> :kills_by_month
        "total-kills-value" -> :total_kills_value
        _ -> :invalid
      end

    if chart_type == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Call the appropriate function based on the chart type
      chart_result =
        case chart_type do
          :kills_by_ship_type -> TPSChartAdapter.generate_kills_by_ship_type_chart()
          :kills_by_month -> TPSChartAdapter.generate_kills_by_month_chart()
          :total_kills_value -> TPSChartAdapter.generate_total_kills_value_chart()
        end

      case chart_result do
        {:ok, url} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{status: "error", message: "Failed to generate chart", reason: reason})
          )
      end
    end
  end

  # Legacy endpoint for kills by ship type (keep for backward compatibility)
  get "/corp-tools/charts/kills-by-ship-type" do
    case TPSChartAdapter.generate_kills_by_ship_type_chart() do
      {:ok, url} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{status: "error", message: "Failed to generate chart", reason: reason})
        )
    end
  end

  # Get chart for kills by month
  get "/corp-tools/charts/kills-by-month" do
    case TPSChartAdapter.generate_kills_by_month_chart() do
      {:ok, url} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{status: "error", message: "Failed to generate chart", reason: reason})
        )
    end
  end

  # Get chart for total kills and value
  get "/corp-tools/charts/total-kills-value" do
    case TPSChartAdapter.generate_total_kills_value_chart() do
      {:ok, url} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{status: "error", message: "Failed to generate chart", reason: reason})
        )
    end
  end

  # Get all TPS charts in a single response
  get "/corp-tools/charts/all" do
    charts = TPSChartAdapter.generate_all_charts()

    if map_size(charts) > 0 do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", charts: charts}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        500,
        Jason.encode!(%{status: "error", message: "Failed to generate any charts"})
      )
    end
  end

  # Send a specific TPS chart to Discord
  get "/corp-tools/charts/send-to-discord/:chart_type" do
    chart_type =
      case conn.params["chart_type"] do
        "kills-by-ship-type" -> :kills_by_ship_type
        "kills-by-month" -> :kills_by_month
        "total-kills-value" -> :total_kills_value
        _ -> :invalid
      end

    if chart_type == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      title =
        case chart_type do
          :kills_by_ship_type -> "Top Ship Types by Kills"
          :kills_by_month -> "Kills by Month"
          :total_kills_value -> "Kills and Value Over Time"
        end

      description =
        case chart_type do
          :kills_by_ship_type ->
            "Shows the top 10 ship types used in kills over the last 12 months"

          :kills_by_month ->
            "Shows the number of kills per month over the last 12 months"

          :total_kills_value ->
            "Shows the number of kills and estimated value over time"
        end

      case TPSChartAdapter.send_chart_to_discord(chart_type, title, description) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", message: "Chart sent to Discord"}))

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: "Failed to send chart to Discord",
              reason: reason
            })
          )
      end
    end
  end

  # Send all TPS charts to Discord
  get "/corp-tools/charts/send-all-to-discord" do
    results = TPSChartAdapter.send_all_charts_to_discord()

    # Check if any of the charts were sent successfully
    any_success = Enum.any?(Map.values(results), fn result -> result == :ok end)

    if any_success do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{status: "ok", message: "Charts sent to Discord", results: results})
      )
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        500,
        Jason.encode!(%{
          status: "error",
          message: "Failed to send any charts to Discord",
          results: results
        })
      )
    end
  end

  # Trigger the TPS chart scheduler manually
  get "/corp-tools/charts/trigger-scheduler" do
    if Process.whereis(WandererNotifier.Schedulers.TPSChartScheduler) do
      WandererNotifier.Schedulers.TPSChartScheduler.execute_now()

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", message: "TPS chart scheduler triggered"}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        500,
        Jason.encode!(%{status: "error", message: "TPS chart scheduler not running"})
      )
    end
  end

  # Debug endpoint to check TPS data structure
  get "/debug-tps-data" do
    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Return the data structure with additional metadata
        debug_info = %{
          status: "ok",
          has_data: not Enum.empty?(Map.keys(data)),
          keys: Map.keys(data),
          ship_types_count:
            if(Map.has_key?(data, "KillsByShipType"),
              do: map_size(data["KillsByShipType"]),
              else: 0
            ),
          months_count:
            if(Map.has_key?(data, "KillsByMonth"), do: map_size(data["KillsByMonth"]), else: 0),
          total_value: Map.get(data, "TotalValue"),
          raw_data: data
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(debug_info))

      {:loading, message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(206, Jason.encode!(%{status: "loading", message: message}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            status: "error",
            message: "Failed to get TPS data",
            reason: inspect(reason)
          })
        )
    end
  end

  # Helper functions
  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil
  defp calculate_percentage(current, limit) when limit > 0, do: min(100, round(current / limit * 100))
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

        # Remove case that can never match with the new implementation
        # The kill processor now always provides a sample kill when no real kills are available

        {:error, :no_kill_id} ->
          %{
            success: false,
            message: "Failed to send test notification: No kill ID found",
            details: "The kill data did not contain a valid kill ID."
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Failed to send test notification: #{inspect(reason)}",
            details: "Check logs for details."
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

    result = send_test_system_notification()

    # Since we now always return {:ok, system_id, system_name} with our sample data implementation
    {:ok, system_id, system_name} = result
    
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
        bot_api_token = Config.bot_api_token()

        # Log what we're doing
        Logger.info("Directly validating license with key and token")

        # Call the license manager client directly
        case WandererNotifier.LicenseManager.Client.validate_bot(bot_api_token, license_key) do
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
            error_message = case reason do
              :not_found -> "License not found"
              :invalid_bot_token -> "Invalid bot token"
              :bot_not_authorized -> "Bot not authorized for this license"
              :request_failed -> "Connection to license server failed"
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

      # Removed unused case that cannot happen with new implementation

      {:error, :no_kill_id} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            success: false,
            message: "Failed to send test notification: No kill ID found",
            details: "The kill data did not contain a valid kill ID."
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
            error: inspect(reason)
          })
        )
    end
  end

  #
  # Helper Functions
  #

  defp get_tracked_systems do
    # Make sure we're using the proper alias
    alias WandererNotifier.Helpers.CacheHelpers
    CacheHelpers.get_tracked_systems()
  end

  #
  # Character Notification
  #
  defp send_test_character_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test character notification")

    # Use CacheHelpers for consistency
    tracked_characters = CacheHelpers.get_tracked_characters()

    # Add additional debug logging
    Logger.debug("Fetched tracked characters from cache: #{inspect(tracked_characters)}")
    Logger.info("Found #{length(tracked_characters)} tracked characters")

    case tracked_characters do
      [] ->
        Logger.info("No tracked characters available, using sample character data")
        # Create a sample character for testing
        sample_character = %{
          "character_id" => "1354830081",
          "name" => "CCP Garthagk",
          "corporationID" => "98356193",
          "corporationName" => "C C P Alliance"
        }
        
        character_id = sample_character["character_id"]
        character_name = sample_character["name"]
        
        Logger.info("Using sample character #{character_name} (ID: #{character_id}) for test notification")
        WandererNotifier.Notifiers.Factory.notify(:send_new_tracked_character_notification, [sample_character])
        
        {:ok, character_id, character_name}

      characters ->
        valid_chars = Enum.filter(characters, &valid_eve_id?/1)
        Logger.debug("Valid characters: #{length(valid_chars)} out of #{length(characters)}")

        case valid_chars do
          [] ->
            Logger.info("No characters with valid numeric EVE IDs, using sample character")
            # Create a sample character for testing
            sample_character = %{
              "character_id" => "1354830081",
              "name" => "CCP Garthagk",
              "corporationID" => "98356193",
              "corporationName" => "C C P Alliance"
            }
            
            character_id = sample_character["character_id"]
            character_name = sample_character["name"]
            
            Logger.info("Using sample character #{character_name} (ID: #{character_id}) for test notification")
            WandererNotifier.Notifiers.Factory.notify(:send_new_tracked_character_notification, [sample_character])
            
            {:ok, character_id, character_name}

          valid_list ->
            character = Enum.random(valid_list)
            {character_id, character_name} = extract_character_details(character)

            Logger.info(
              "Using character #{character_name} (ID: #{character_id}) for test notification"
            )

            result = WandererNotifier.Notifiers.Factory.notify(:send_new_tracked_character_notification, [character])

            case result do
              {:error, :invalid_character_id} ->
                Logger.error("Failed - invalid character ID, falling back to sample")
                # Fall back to sample character on error
                sample_character = %{
                  "character_id" => "1354830081",
                  "name" => "CCP Garthagk",
                  "corporationID" => "98356193",
                  "corporationName" => "C C P Alliance"
                }
                
                character_id = sample_character["character_id"]
                character_name = sample_character["name"]
                
                Logger.info("Using fallback character #{character_name} (ID: #{character_id})")
                WandererNotifier.Notifiers.Factory.notify(:send_new_tracked_character_notification, [sample_character])
                
                {:ok, character_id, character_name}

              _ ->
                {:ok, character_id, character_name}
            end
        end
    end
  end

  #
  # System Notification
  #
  defp send_test_system_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test system notification")

    tracked_systems = get_tracked_systems()
    Logger.info("Found #{length(tracked_systems)} tracked systems")

    case tracked_systems do
      [] ->
        Logger.info("No tracked systems available, using sample system data")
        # Create a sample system for testing
        sample_system = %{
          "id" => "test-123",
          "systemName" => "J123456",
          "alias" => "Test Wormhole",
          "systemId" => 31000123,
          "staticInfo" => %{
            "statics" => ["C247", "D382"],
            "typeDescription" => "Class 5"
          }
        }
        system_id = sample_system["systemId"]
        system_name = sample_system["systemName"]
        
        Logger.info("Using sample system #{system_name} (ID: #{system_id}) for test notification")
        WandererNotifier.Notifiers.Factory.notify(:send_new_system_notification, [sample_system])
        
        {:ok, system_id, system_name}

      systems ->
        system = Enum.random(systems)
        # Debug the system structure to understand what fields are available
        Logger.debug("System data for notification: #{inspect(system)}")
        
        system_id = Map.get(system, "system_id") || 
                    Map.get(system, :system_id) || 
                    Map.get(system, "systemId") || 
                    Map.get(system, "id") || 
                    31000001  # Fallback ID

        system_name =
          Map.get(system, "system_name") ||
            Map.get(system, :alias) ||
            Map.get(system, "name") ||
            Map.get(system, "systemName") ||
            "J000001"  # Fallback name

        Logger.info("Using system #{system_name} (ID: #{system_id}) for test notification")
        
        # Add staticInfo if missing to avoid notifications failing
        system_with_static =
          if !Map.has_key?(system, "staticInfo") && !Map.has_key?(system, :staticInfo) do
            Map.put(system, "staticInfo", %{
              "statics" => [],
              "typeDescription" => "Class 1"  # Default type
            })
          else
            system
          end
        
        WandererNotifier.Notifiers.Factory.notify(:send_new_system_notification, [system_with_static])

        {:ok, system_id, system_name}
    end
  end

  #
  # Validate EVE ID
  #
  defp valid_eve_id?(character) do
    cond do
      is_binary(character["character_id"]) and
          NotificationHelpers.is_valid_numeric_id?(character["character_id"]) ->
        true

      is_binary(character["eve_id"]) and
          NotificationHelpers.is_valid_numeric_id?(character["eve_id"]) ->
        true

      is_map(character["character"]) ->
        is_valid_nested?(character["character"])

      true ->
        false
    end
  end

  defp is_valid_nested?(nested_map) do
    # Because we can't call external functions in a guard,
    # we just do normal boolean checks in the function body:
    cond do
      is_binary(nested_map["eve_id"]) and
          NotificationHelpers.is_valid_numeric_id?(nested_map["eve_id"]) ->
        true

      is_binary(nested_map["character_id"]) and
          NotificationHelpers.is_valid_numeric_id?(nested_map["character_id"]) ->
        true

      is_binary(nested_map["id"]) and
          NotificationHelpers.is_valid_numeric_id?(nested_map["id"]) ->
        true

      true ->
        false
    end
  end

  #
  # Extract character details
  #
  defp extract_character_details(character) do
    character_id =
      cond do
        is_binary(character["character_id"]) and
            NotificationHelpers.is_valid_numeric_id?(character["character_id"]) ->
          character["character_id"]

        is_binary(character["eve_id"]) and
            NotificationHelpers.is_valid_numeric_id?(character["eve_id"]) ->
          character["eve_id"]

        (is_map(character["character"]) && is_binary(character["character"]["eve_id"])) and
            NotificationHelpers.is_valid_numeric_id?(character["character"]["eve_id"]) ->
          character["character"]["eve_id"]

        (is_map(character["character"]) && is_binary(character["character"]["character_id"])) and
            NotificationHelpers.is_valid_numeric_id?(character["character"]["character_id"]) ->
          character["character"]["character_id"]

        (is_map(character["character"]) && is_binary(character["character"]["id"])) and
            NotificationHelpers.is_valid_numeric_id?(character["character"]["id"]) ->
          character["character"]["id"]

        true ->
          nil
      end

    character_name =
      cond do
        character["character_name"] != nil ->
          character["character_name"]

        character["name"] != nil ->
          character["name"]

        is_map(character["character"]) && character["character"]["name"] != nil ->
          character["character"]["name"]

        is_map(character["character"]) && character["character"]["character_name"] != nil ->
          character["character"]["character_name"]

        true ->
          "Character #{character_id}"
      end

    {character_id, character_name}
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
