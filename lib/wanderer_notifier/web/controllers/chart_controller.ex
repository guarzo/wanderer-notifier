defmodule WandererNotifier.Web.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.ChartService.KillmailChartAdapter
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Web.Controllers.ActivityChartController

  plug(:match)
  plug(:dispatch)

  # Forward activity chart requests to the ActivityChartController
  forward("/activity", to: ActivityChartController)

  # Get configuration for charts and map tools
  get "/config" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        map_tools_enabled: Config.map_charts_enabled?(),
        kill_charts_enabled: Config.kill_charts_enabled?()
      })
    )
  end

  # Get character activity data
  get "/character-activity" do
    # Check if map charts functionality is enabled
    if Config.map_charts_enabled?() do
      # Extract slug parameter if provided
      slug = conn.params["slug"]

      # Log the slug for debugging
      if slug do
        AppLogger.api_info("Character activity request", slug: slug)
      else
        configured_slug = Config.map_name()

        AppLogger.api_info(
          "Character activity request",
          slug: configured_slug || "none",
          slug_source: "configured"
        )
      end

      case CharactersClient.get_character_activity(slug) do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))

        {:error, reason} ->
          # Log the error for server-side debugging
          AppLogger.api_error("Error in character activity endpoint", error: inspect(reason))

          # Provide a more user-friendly error message
          error_message =
            case reason do
              "Map slug not provided and not configured" ->
                "Map slug not configured. Please set MAP_NAME in your environment or provide a slug parameter."

              error when is_binary(error) ->
                error

              _ ->
                "An error occurred while fetching character activity data: #{inspect(reason)}"
            end

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: error_message,
              details: inspect(reason)
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "Map Charts functionality is not enabled"})
      )
    end
  end

  # Generate a chart based on the provided type
  get "/generate" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "TPS charts functionality has been removed"})
    )
  end

  # Send a chart to Discord
  get "/send-to-discord" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "TPS charts functionality has been removed"})
    )
  end

  # Special route for sending all activity charts
  get "/activity/send-all" do
    AppLogger.api_info("Forwarding request to send all activity charts to Discord")

    # Only allow this if map tools are enabled
    if Config.map_charts_enabled?() do
      AppLogger.api_info("Forwarding request to activity controller send-all endpoint")

      # Get character activity data
      activity_data =
        case CharactersClient.get_character_activity() do
          {:ok, data} ->
            AppLogger.api_info("Retrieved character activity data",
              preview: inspect(data, limit: 500)
            )

            data

          error ->
            AppLogger.api_error("Failed to retrieve character activity data",
              error: inspect(error)
            )

            nil
        end

      # Get the appropriate channel ID for activity charts
      channel_id = Config.discord_channel_id_for_activity_charts()

      AppLogger.api_debug("Using Discord channel",
        purpose: "activity charts",
        channel_id: channel_id
      )

      # Use the ActivityChartAdapter directly to send all charts
      results = ActivityChartAdapter.send_all_charts_to_discord(activity_data, channel_id)

      # Format the results for proper JSON encoding
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

      # Check if any charts were sent successfully
      success_count = Enum.count(formatted_results, fn result -> result.status == "success" end)

      # Always return success as long as we got a response - a "no data" chart is still a success
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          status: "ok",
          success_count: success_count,
          total_count: length(formatted_results),
          results: formatted_results
        })
      )
    else
      AppLogger.api_warn("Cannot send activity charts", reason: "Map tools not enabled")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Map tools are not enabled"}))
    end
  end

  # Get TPS data for debugging
  get "/debug-tps-structure" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      404,
      Jason.encode!(%{status: "error", message: "TPS charts functionality has been removed"})
    )
  end

  # Killmail chart routes

  # Generate a killmail chart
  get "/killmail/generate/weekly_kills" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Generating weekly kills chart")

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

      case KillmailChartAdapter.generate_weekly_kills_chart(limit) do
        {:ok, chart_url} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              title: "Character Activity Chart",
              chart_url: chart_url
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              status: "error",
              message: "Failed to generate weekly kills chart: #{reason}"
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
    end
  end

  # Send a killmail chart to Discord
  get "/killmail/send-to-discord/weekly_kills" do
    if Config.kill_charts_enabled?() do
      title = conn.params["title"] || "Weekly Character Kills"
      description = conn.params["description"] || "Top 20 characters by kills in the past week"
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

      AppLogger.api_info("Sending weekly kills chart to Discord", title: title)

      case KillmailChartAdapter.send_weekly_kills_chart_to_discord(
             title,
             description,
             channel_id,
             limit
           ) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              message: "Chart sent to Discord successfully"
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              status: "error",
              message: "Failed to send chart to Discord: #{reason}"
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
    end
  end

  # Send all killmail charts to Discord
  get "/killmail/send-all" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Sending all killmail charts to Discord")

      # Currently only weekly kills chart is available
      case KillmailChartAdapter.send_weekly_kills_chart_to_discord() do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              message: "All killmail charts sent to Discord successfully"
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              status: "error",
              message: "Failed to send all killmail charts to Discord: #{reason}"
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
    end
  end

  # Debug endpoint to check killmail and statistics counts
  get "/killmail/debug" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Debug endpoint called for killmail aggregation")

      # Perform diagnostic queries
      try do
        # Check total killmail records
        killmail_query = "SELECT COUNT(*) FROM killmails"
        {:ok, %{rows: [[total_killmails]]}} = WandererNotifier.Repo.query(killmail_query)

        # Check total statistics records
        stats_query = "SELECT COUNT(*) FROM killmail_statistics"
        {:ok, %{rows: [[total_stats]]}} = WandererNotifier.Repo.query(stats_query)

        # Check stats by period
        period_query =
          "SELECT period_type, COUNT(*) FROM killmail_statistics GROUP BY period_type"

        {:ok, period_results} = WandererNotifier.Repo.query(period_query)

        # Check recent killmails
        recent_query =
          "SELECT killmail_id, related_character_name, character_role, kill_time, solar_system_name FROM killmails ORDER BY kill_time DESC LIMIT 5"

        {:ok, recent_results} = WandererNotifier.Repo.query(recent_query)

        # Format the period results
        period_counts =
          period_results.rows
          |> Enum.map(fn [period, count] ->
            {period, count}
          end)
          |> Enum.into(%{})

        # Format recent killmails
        recent_killmails =
          recent_results.rows
          |> Enum.map(fn [killmail_id, character_name, role, kill_time, system_name] ->
            %{
              killmail_id: killmail_id,
              character_name: character_name,
              role: role,
              kill_time: kill_time,
              system_name: system_name
            }
          end)

        # Count tracked characters in database
        char_query = "SELECT COUNT(*) FROM tracked_characters"
        {:ok, %{rows: [[total_chars]]}} = WandererNotifier.Repo.query(char_query)

        # Count characters in cache
        cached_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []

        # Send the diagnostic info
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            status: "ok",
            message: "Diagnostic information for killmail aggregation",
            counts: %{
              killmails: total_killmails,
              statistics: total_stats,
              tracked_characters_db: total_chars,
              tracked_characters_cache: length(cached_characters),
              by_period: period_counts
            },
            recent_killmails: recent_killmails
          })
        )
      rescue
        e ->
          AppLogger.api_error("Error in killmail debug endpoint", error: Exception.message(e))

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: "Error retrieving diagnostic information",
              error: Exception.message(e)
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
    end
  end

  # Force sync tracked characters from cache to the database
  get "/killmail/sync-characters" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_info("Forcing character sync from cache to database")

      cached_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []
      AppLogger.api_info("Found characters in cache", count: length(cached_characters))

      case WandererNotifier.Resources.TrackedCharacter.sync_from_cache() do
        {:ok, result} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              message: "Characters synced successfully",
              details: %{
                characters_in_cache: length(cached_characters),
                synced_successfully: result.successes,
                sync_failures: result.failures
              }
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: "Failed to sync characters",
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
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
    end
  end

  # Force-sync characters (destructive operation that clears and rebuilds)
  get "/killmail/force-sync-characters" do
    if Config.kill_charts_enabled?() do
      AppLogger.api_warn("Forcing destructive character sync from cache to database",
        action: "database-clear"
      )

      case WandererNotifier.Resources.TrackedCharacter.force_sync_from_cache() do
        {:ok, result} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              message: "Characters force-synced successfully (database was cleared first)",
              details: result
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: "Failed to force-sync characters",
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
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
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
      case WandererNotifier.Resources.KillmailAggregation.aggregate_statistics(
             period_type,
             target_date
           ) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              message: "Successfully aggregated #{period_type} killmail data",
              period_type: period_type,
              target_date: Date.to_string(target_date)
            })
          )

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: "Failed to aggregate killmail data: #{inspect(reason)}",
              period_type: period_type,
              target_date: Date.to_string(target_date)
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          status: "error",
          message: "Killmail persistence is not enabled"
        })
      )
    end
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
