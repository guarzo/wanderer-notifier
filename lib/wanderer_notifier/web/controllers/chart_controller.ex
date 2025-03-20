defmodule WandererNotifier.Web.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.ChartService.TPSChartAdapter
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.CorpTools.CorpToolsClient
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
        corp_tools_enabled: Config.corp_tools_enabled?(),
        map_tools_enabled: Config.map_tools_enabled?()
      })
    )
  end

  # Get character activity data
  get "/character-activity" do
    # Check if map tools functionality is enabled
    if not Config.map_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "Map Tools functionality is not enabled"})
      )
    else
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
    end
  end

  # Generate a chart based on the provided type
  get "/generate" do
    # Check if corp tools functionality is enabled
    if not Config.corp_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "Corp Tools functionality is not enabled"})
      )
    else
      # Extract parameters from the query string
      chart_type =
        case conn.params["type"] do
          "damage_final_blows" -> :damage_final_blows
          "combined_losses" -> :combined_losses
          "kill_activity" -> :kill_activity
          "activity_summary" -> :activity_summary
          "activity_timeline" -> :activity_timeline
          "activity_distribution" -> :activity_distribution
          _ -> :invalid
        end

      _title = conn.params["title"] || "EVE Online Chart"
      _description = conn.params["description"] || "Generated chart"

      if chart_type == :invalid do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
      else
        # Determine which adapter to use based on chart type
        chart_result =
          case chart_type do
            :damage_final_blows ->
              TPSChartAdapter.generate_chart(chart_type)

            :combined_losses ->
              TPSChartAdapter.generate_chart(chart_type)

            :kill_activity ->
              TPSChartAdapter.generate_chart(chart_type)

            :activity_summary ->
              # Get activity data first
              case CharactersClient.get_character_activity() do
                {:ok, data} -> ActivityChartAdapter.generate_activity_summary_chart(data)
                _ -> {:error, "Failed to get activity data"}
              end

            :activity_timeline ->
              # Get activity data first
              case CharactersClient.get_character_activity() do
                {:ok, data} -> ActivityChartAdapter.generate_activity_timeline_chart(data)
                _ -> {:error, "Failed to get activity data"}
              end

            :activity_distribution ->
              # Get activity data first
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.generate_activity_distribution_chart(data)

                _ ->
                  {:error, "Failed to get activity data"}
              end
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
              Jason.encode!(%{
                status: "error",
                message: "Failed to generate chart",
                reason: reason
              })
            )
        end
      end
    end
  end

  # Send a chart to Discord
  get "/send-to-discord" do
    # Check if corp tools functionality is enabled
    if not Config.corp_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "Corp Tools functionality is not enabled"})
      )
    else
      # Extract parameters from the query string
      chart_type =
        case conn.params["type"] do
          "damage_final_blows" -> :damage_final_blows
          "combined_losses" -> :combined_losses
          "kill_activity" -> :kill_activity
          "activity_summary" -> :activity_summary
          "activity_timeline" -> :activity_timeline
          "activity_distribution" -> :activity_distribution
          _ -> :invalid
        end

      title = conn.params["title"] || "EVE Online Chart"
      description = conn.params["description"] || "Generated chart"

      if chart_type == :invalid do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
      else
        # Determine which adapter to use based on chart type
        result =
          case chart_type do
            :damage_final_blows ->
              TPSChartAdapter.send_chart_to_discord(chart_type, title, description)

            :combined_losses ->
              TPSChartAdapter.send_chart_to_discord(chart_type, title, description)

            :kill_activity ->
              TPSChartAdapter.send_chart_to_discord(chart_type, title, description)

            :activity_summary ->
              # Get activity data first for chart generation
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.send_chart_to_discord("activity_summary", data)

                _ ->
                  {:error, "Failed to get activity data"}
              end

            :activity_timeline ->
              # Get activity data first for chart generation
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.send_chart_to_discord("activity_timeline", data)

                _ ->
                  {:error, "Failed to get activity data"}
              end

            :activity_distribution ->
              # Get activity data first for chart generation
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.send_chart_to_discord(
                    "activity_distribution",
                    data
                  )

                _ ->
                  {:error, "Failed to get activity data"}
              end
          end

        case result do
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
  end

  # Special route for sending all activity charts
  get "/activity/send-all" do
    Logger.info("Forwarding request to send all activity charts to Discord")

    # Only allow this if map tools are enabled
    if !Config.map_tools_enabled?() do
      Logger.warning("Map tools are not enabled, cannot send activity charts")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Map tools are not enabled"}))
    else
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

      # Use the ActivityChartAdapter directly to send all charts
      results = ActivityChartAdapter.send_all_charts_to_discord(activity_data)

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
    end
  end

  # Get TPS data for debugging
  get "/debug-tps-structure" do
    # Check if corp tools functionality is enabled
    if not Config.corp_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "Corp Tools functionality is not enabled"})
      )
    else
      case CorpToolsClient.get_tps_data() do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))

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
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
