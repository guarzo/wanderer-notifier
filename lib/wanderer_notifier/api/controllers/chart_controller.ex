defmodule WandererNotifier.Api.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use WandererNotifier.Api.Controllers.BaseController

  alias WandererNotifier.Api.Character.Activity
  alias WandererNotifier.Api.Controllers.ActivityChartController
  alias WandererNotifier.ChartService.{ActivityChartAdapter, KillmailChartAdapter}
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.NeoClient, as: DiscordClient
  alias WandererNotifier.Resources.{Api, KillmailAggregation, TrackedCharacter}

  # Forward activity chart requests to the ActivityChartController
  forward("/activity", to: ActivityChartController)

  # Get configuration for charts and map tools
  get "/config" do
    config = %{
      kill_charts_enabled: Features.kill_charts_enabled?()
    }

    send_success_response(conn, config)
  end

  # Get character activity data
  get "/character-activity" do
    AppLogger.api_info("Character activity data request received")

    case Activity.fetch_activity_data() do
      {:ok, data} ->
        case Activity.process_activity_data(data) do
          {:ok, processed_data} ->
            send_success_response(conn, processed_data)

          {:error, reason} ->
            send_error_response(conn, 500, "Error processing activity data: #{reason}")
        end

      {:error, reason} ->
        error_message =
          case reason do
            "Map slug not provided and not configured" ->
              "Map slug not configured. Please set MAP_NAME in your environment or provide a slug parameter."

            error when is_binary(error) ->
              error

            _ ->
              "An error occurred while fetching character activity data: #{inspect(reason)}"
          end

        send_error_response(conn, 500, error_message)
    end
  end

  # Generate a chart based on the provided type
  get "/generate" do
    send_error_response(conn, 404, "TPS charts functionality has been removed")
  end

  # Send a chart to Discord
  get "/send-to-discord" do
    send_error_response(conn, 404, "TPS charts functionality has been removed")
  end

  # Special route for sending all activity charts
  get "/activity/send-all" do
    AppLogger.api_info("Forwarding request to send all activity charts to Discord")

    if Config.map_charts_enabled?() do
      AppLogger.api_info("Forwarding request to activity controller send-all endpoint")

      case Activity.fetch_activity_data() do
        {:ok, activity_data} ->
          channel_id = Config.discord_channel_id_for_activity_charts()
          results = ActivityChartAdapter.send_all_charts_to_discord(activity_data, channel_id)

          formatted_results =
            Enum.map(results, fn {chart_type, result} ->
              case result do
                {:ok, url, title} ->
                  %{chart_type: chart_type, status: "success", url: url, title: title}

                {:error, reason} ->
                  %{chart_type: chart_type, status: "error", message: reason}

                _ ->
                  %{chart_type: chart_type, status: "error", message: "Unknown result format"}
              end
            end)

          success_count =
            Enum.count(formatted_results, fn result -> result.status == "success" end)

          send_success_response(conn, %{
            success_count: success_count,
            total_count: length(formatted_results),
            results: formatted_results
          })

        {:error, reason} ->
          send_error_response(conn, 500, "Failed to fetch activity data: #{inspect(reason)}")
      end
    else
      send_error_response(conn, 404, "Map tools are not enabled")
    end
  end

  # Get TPS data for debugging
  get "/debug-tps-structure" do
    send_error_response(conn, 404, "TPS charts functionality has been removed")
  end

  # Killmail chart routes

  # Generate a killmail chart
  get "/killmail/generate/weekly_kills" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Generating weekly kills chart")

      # Note: We're ignoring the limit parameter as it's now handled internally
      case KillmailChartAdapter.generate_weekly_kills_chart() do
        {:ok, image_data} when is_binary(image_data) ->
          conn
          |> put_resp_content_type("image/png")
          |> send_resp(200, image_data)

        {:error, reason} ->
          send_error_response(conn, 400, "Failed to generate weekly kills chart: #{reason}")
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Generate kill validation chart
  get "/killmail/generate/validation" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Generating kill validation chart")

      case KillmailChartAdapter.generate_kill_validation_chart() do
        {:ok, image_data} when is_binary(image_data) ->
          conn
          |> put_resp_content_type("image/png")
          |> send_resp(200, image_data)

        {:error, reason} ->
          send_error_response(conn, 400, "Failed to generate kill validation chart: #{reason}")
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Generate a weekly ISK destroyed chart
  get "/killmail/generate/weekly_isk" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Generating weekly ISK destroyed chart")

      # Parse limit parameter with default of 20
      limit =
        case conn.params["limit"] do
          nil ->
            20

          val when is_binary(val) ->
            case Integer.parse(val) do
              {num, _} -> num
              :error -> 20
            end

          _ ->
            20
        end

      case KillmailChartAdapter.generate_weekly_isk_chart(limit) do
        {:ok, image_data} when is_binary(image_data) ->
          conn
          |> put_resp_content_type("image/png")
          |> send_resp(200, image_data)

        {:error, reason} ->
          send_error_response(
            conn,
            400,
            "Failed to generate weekly ISK destroyed chart: #{reason}"
          )
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Send a killmail chart to Discord
  get "/killmail/send-to-discord/weekly_kills" do
    if Config.kill_charts_enabled?() do
      title = conn.params["title"] || "Weekly Character Kills"
      _description = conn.params["description"] || "Top 20 characters by kills in the past week"
      channel_id = conn.params["channel_id"]

      # Parse limit parameter with default of 20
      _limit =
        case conn.params["limit"] do
          nil ->
            20

          val when is_binary(val) ->
            case Integer.parse(val) do
              {num, _} -> num
              :error -> 20
            end

          _ ->
            20
        end

      AppLogger.api_info("Sending weekly kills chart to Discord", title: title)

      # Get the current date and calculate the most recent week start
      today = Date.utc_today()
      days_since_monday = Date.day_of_week(today) - 1
      date_from = Date.add(today, -days_since_monday)
      date_to = Date.add(date_from, 6)

      case KillmailChartAdapter.send_weekly_kills_chart_to_discord(
             channel_id,
             date_from,
             date_to
           ) do
        {:ok, _} ->
          send_success_response(conn, %{
            status: "ok",
            message: "Chart sent to Discord successfully"
          })

        {:error, reason} ->
          send_error_response(conn, 400, "Failed to send chart to Discord: #{reason}")
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Send a weekly ISK destroyed chart to Discord
  get "/killmail/send-to-discord/weekly_isk" do
    if Config.kill_charts_enabled?() do
      title = conn.params["title"] || "Weekly ISK Destroyed"

      description =
        conn.params["description"] || "Top 20 characters by ISK destroyed in the past week"

      channel_id = conn.params["channel_id"]

      # Parse limit parameter with default of 20
      limit =
        case conn.params["limit"] do
          nil ->
            20

          val when is_binary(val) ->
            case Integer.parse(val) do
              {num, _} -> num
              :error -> 20
            end

          _ ->
            20
        end

      AppLogger.api_info("Sending weekly ISK destroyed chart to Discord", title: title)

      case KillmailChartAdapter.send_weekly_isk_chart_to_discord(
             title,
             description,
             channel_id,
             limit
           ) do
        :ok ->
          send_success_response(conn, %{
            status: "ok",
            message: "ISK destroyed chart sent to Discord successfully"
          })

        {:ok, %{title: _}} ->
          # Handle the case where a tuple with title is returned
          send_success_response(conn, %{
            status: "ok",
            message: "ISK destroyed chart sent to Discord successfully"
          })

        {:error, reason} ->
          send_error_response(
            conn,
            400,
            "Failed to send ISK destroyed chart to Discord: #{reason}"
          )
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Send a kill validation chart to Discord
  get "/killmail/send-to-discord/validation" do
    if Config.kill_charts_enabled?() do
      title = conn.params["title"] || "Kill Validation"

      description =
        conn.params["description"] || "Comparison of kills in ZKillboard API vs Database"

      channel_id = conn.params["channel_id"]

      AppLogger.api_info("Sending kill validation chart to Discord", title: title)

      # Generate the chart
      case KillmailChartAdapter.generate_kill_validation_chart() do
        {:ok, image_data} when is_binary(image_data) ->
          # Use Discord client to send the file directly
          case DiscordClient.send_file(
                 "validation.png",
                 image_data,
                 title,
                 description,
                 channel_id,
                 %{"title" => title, "color" => 3_447_003}
               ) do
            :ok ->
              send_success_response(conn, %{
                status: "ok",
                message: "Validation chart sent to Discord successfully"
              })

            {:error, reason} ->
              send_error_response(
                conn,
                400,
                "Failed to send validation chart to Discord: #{reason}"
              )
          end

        {:error, reason} ->
          send_error_response(
            conn,
            400,
            "Failed to generate validation chart: #{reason}"
          )
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Send all killmail charts to Discord
  get "/killmail/send-all" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Sending all killmail charts to Discord")

      # Get the current date and calculate the most recent week start
      today = Date.utc_today()
      days_since_monday = Date.day_of_week(today) - 1
      date_from = Date.add(today, -days_since_monday)
      date_to = Date.add(date_from, 6)

      # Get the appropriate channel ID for kill charts
      channel_id = Config.discord_channel_id_for(:kill_charts)

      # Send both the weekly kills chart and the weekly ISK destroyed chart
      case KillmailChartAdapter.send_weekly_kills_chart_to_discord(channel_id, date_from, date_to) do
        {:ok, _} ->
          send_success_response(conn, %{
            status: "ok",
            message: "All killmail charts sent to Discord successfully"
          })

        {:error, reason} ->
          send_error_response(
            conn,
            400,
            "Failed to send killmail charts to Discord: #{inspect(reason)}"
          )
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Debug endpoint to check killmail and statistics counts
  get "/killmail/debug" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Debug endpoint called for killmail aggregation")
      import Ash.Query
      alias WandererNotifier.Resources.Api
      alias WandererNotifier.Resources.Killmail
      alias WandererNotifier.Resources.KillmailCharacterInvolvement
      alias WandererNotifier.Resources.KillmailStatistic
      alias WandererNotifier.Resources.TrackedCharacter

      # Perform diagnostic queries
      try do
        # First check if database operations are enabled
        if TrackedCharacter.database_enabled?() do
          # Check total killmail records using Ash
          total_killmails =
            case Api.read(Killmail |> aggregate(:count, :id, :total)) do
              {:ok, [%{total: count}]} -> count
              _ -> 0
            end

          # Check total statistics records using Ash
          total_stats =
            case Api.read(KillmailStatistic |> aggregate(:count, :id, :total)) do
              {:ok, [%{total: count}]} -> count
              _ -> 0
            end

          # Check total involvement records using Ash
          total_involvements =
            case Api.read(KillmailCharacterInvolvement |> aggregate(:count, :id, :total)) do
              {:ok, [%{total: count}]} -> count
              _ -> 0
            end

          # Check stats by period using Ash - fixed group_by call
          period_results =
            case Api.read(
                   KillmailStatistic
                   |> Ash.Query.filter(true)
                   |> Ash.Query.aggregate(:count, :id, group_by: [:period_type])
                 ) do
              {:ok, results} ->
                results
                |> Enum.map(fn result ->
                  {Atom.to_string(result.period_type), result.count}
                end)
                |> Enum.into(%{})

              _ ->
                %{}
            end

          # Get recent killmails using Ash
          recent_killmails =
            case Api.read(
                   Killmail
                   |> sort(kill_time: :desc)
                   |> limit(5)
                   |> select([
                     :id,
                     :killmail_id,
                     :kill_time,
                     :solar_system_name,
                     :victim_name,
                     :victim_ship_name,
                     :total_value
                   ])
                 ) do
              {:ok, killmails} ->
                Enum.map(killmails, fn km ->
                  %{
                    id: km.id,
                    killmail_id: km.killmail_id,
                    kill_time: km.kill_time,
                    system_name: km.solar_system_name,
                    victim_name: km.victim_name,
                    victim_ship: km.victim_ship_name,
                    total_value: km.total_value
                  }
                end)

              _ ->
                []
            end

          # Count tracked characters using Ash
          total_chars =
            case Api.read(TrackedCharacter |> aggregate(:count, :id, :total)) do
              {:ok, [%{total: count}]} -> count
              _ -> 0
            end

          # Count characters in cache
          cached_characters = CacheRepo.get("map:characters") || []

          # Send the diagnostic info
          send_success_response(conn, %{
            status: "ok",
            message: "Diagnostic information for killmail aggregation",
            counts: %{
              killmails: total_killmails,
              character_involvements: total_involvements,
              statistics: total_stats,
              tracked_characters_db: total_chars,
              tracked_characters_cache: length(cached_characters),
              by_period: period_results
            },
            recent_killmails: recent_killmails
          })
        else
          # Database is disabled, return limited diagnostic info
          cached_characters = CacheRepo.get("map:characters") || []

          send_success_response(conn, %{
            status: "ok",
            message: "Limited diagnostic information (database operations disabled)",
            counts: %{
              tracked_characters_cache: length(cached_characters)
            },
            database_status: "disabled"
          })
        end
      rescue
        e ->
          AppLogger.api_error("Error in killmail debug endpoint",
            error: Exception.message(e),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          )

          send_error_response(
            conn,
            500,
            "Error retrieving diagnostic information: #{Exception.message(e)}"
          )
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Force sync tracked characters from cache to the database
  get "/killmail/sync-characters" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Forcing character sync from cache to database")

      cached_characters = CacheRepo.get("map:characters") || []
      AppLogger.api_info("Found characters in cache", count: length(cached_characters))

      case TrackedCharacter.sync_from_cache() do
        {:ok, result} ->
          send_success_response(conn, %{
            status: "ok",
            message: "Characters synced successfully",
            details: %{
              characters_in_cache: length(cached_characters),
              synced_successfully: result.successes,
              sync_failures: result.failures
            }
          })

        {:error, reason} ->
          send_error_response(conn, 500, "Failed to sync characters: #{inspect(reason)}")
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Force-sync characters (destructive operation that clears and rebuilds)
  get "/killmail/force-sync-characters" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_warn("Forcing destructive character sync from cache to database",
        action: "database-clear"
      )

      case TrackedCharacter.force_sync_from_cache() do
        {:ok, result} ->
          send_success_response(conn, %{
            status: "ok",
            message: "Characters force-synced successfully (database was cleared first)",
            details: result
          })

        {:error, reason} ->
          send_error_response(conn, 500, "Failed to force-sync characters: #{inspect(reason)}")
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Trigger manual aggregation of killmail data
  get "/killmail/aggregate" do
    if Config.kill_charts_enabled?() do
      # Get the aggregation type from query params, defaulting to "weekly"
      period_type_str = Map.get(conn.params, "type", "weekly")

      # Convert to atom safely
      period_type =
        case period_type_str do
          "daily" -> :daily
          "weekly" -> :weekly
          "monthly" -> :monthly
          # Default to weekly
          _ -> :weekly
        end

      AppLogger.api_info("Manually triggering killmail aggregation", period_type: period_type)

      # Calculate appropriate date based on period type
      today = Date.utc_today()

      target_date =
        case period_type do
          :daily ->
            today

          :weekly ->
            # Get the start of the current week (Monday)
            days_since_monday = Date.day_of_week(today) - 1
            Date.add(today, -days_since_monday)

          :monthly ->
            # Start of the current month
            %{today | day: 1}
        end

      # Run the aggregation
      case KillmailAggregation.aggregate_statistics(
             period_type,
             target_date
           ) do
        :ok ->
          send_success_response(conn, %{
            status: "ok",
            message: "Successfully aggregated #{period_type} killmail data",
            period_type: period_type,
            target_date: Date.to_string(target_date)
          })

        {:error, reason} ->
          send_error_response(conn, 500, "Failed to aggregate killmail data: #{inspect(reason)}")
      end
    else
      send_error_response(conn, 403, "Killmail persistence is not enabled")
    end
  end

  # Catch-all route
  match _ do
    send_error_response(conn, 404, "Not found")
  end
end
