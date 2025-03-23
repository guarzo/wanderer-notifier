defmodule WandererNotifier.Web.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use Plug.Router
  require Logger
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
        Logger.info("Character activity request with explicit slug: #{slug}")
      else
        configured_slug = Config.map_name()

        Logger.info(
          "Character activity request using configured slug: #{configured_slug || "none"}"
        )
      end

      case CharactersClient.get_character_activity(slug) do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))

        {:error, reason} ->
          # Log the error for server-side debugging
          Logger.error("Error in character activity endpoint: #{inspect(reason)}")

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
    Logger.info("Forwarding request to send all activity charts to Discord")

    # Only allow this if map tools are enabled
    if Config.map_charts_enabled?() do
      Logger.info("Forwarding request to activity controller send-all endpoint")

      # Get character activity data
      activity_data =
        case CharactersClient.get_character_activity() do
          {:ok, data} ->
            Logger.info(
              "Successfully retrieved character activity data: #{inspect(data, limit: 500)}"
            )

            data

          error ->
            Logger.error("Failed to retrieve character activity data: #{inspect(error)}")
            nil
        end

      # Get the appropriate channel ID for activity charts
      channel_id = Config.discord_channel_id_for_activity_charts()
      Logger.info("Using Discord channel ID for activity charts: #{channel_id}")

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
      Logger.warning("Map tools are not enabled, cannot send activity charts")

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
      Logger.info("Generating weekly kills chart")

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

      Logger.info("Sending weekly kills chart to Discord with title: #{title}")

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
      Logger.info("Sending all killmail charts to Discord")

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

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
