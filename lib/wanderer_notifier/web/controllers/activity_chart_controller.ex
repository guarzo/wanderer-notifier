defmodule WandererNotifier.Web.Controllers.ActivityChartController do
  @moduledoc """
  Controller for activity chart-related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.CorpTools.ActivityChartAdapter
  alias WandererNotifier.CorpTools.ActivityChartScheduler
  alias WandererNotifier.Map.Client, as: MapClient
  alias WandererNotifier.Config

  plug :match
  plug :dispatch
  
  # Match all requests and parse parameters
  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Jason

  @doc """
  Handles requests to generate activity charts based on type.
  Responds with JSON containing the chart URL.
  """
  get "/generate/:chart_type" do
    # Convert string type to atom
    chart_type_atom = case chart_type do
      "activity_summary" -> :activity_summary
      "activity_timeline" -> :activity_timeline
      "activity_distribution" -> :activity_distribution
      _ -> :invalid
    end

    Logger.info("Generating activity chart type: #{inspect(chart_type)}, parsed as: #{inspect(chart_type_atom)}")

    if chart_type_atom == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Get real data when available, otherwise use mock data
      activity_data = get_real_activity_data() 

      # Generate chart based on type
      chart_result = case chart_type_atom do
        :activity_summary -> ActivityChartAdapter.generate_character_activity_chart(activity_data)
        :activity_timeline -> ActivityChartAdapter.generate_activity_timeline_chart(activity_data)
        :activity_distribution -> ActivityChartAdapter.generate_activity_distribution_chart(activity_data)
      end

      case chart_result do
        {:ok, url} ->
          Logger.info("Generated #{chart_type_atom} chart: #{url}")
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))
        {:error, reason} ->
          Logger.error("Failed to generate #{chart_type_atom} chart: #{inspect(reason)}")
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to generate chart: #{reason}"}))
      end
    end
  end

  @doc """
  Handles requests to send activity charts to Discord.
  Responds with JSON indicating success or failure.
  """
  get "/send-to-discord/:chart_type" do
    # Convert string type to atom
    chart_type_atom = case chart_type do
      "activity_summary" -> :activity_summary
      "activity_timeline" -> :activity_timeline
      "activity_distribution" -> :activity_distribution
      _ -> :invalid
    end

    Logger.info("Sending activity chart to Discord: #{inspect(chart_type)}, parsed as: #{inspect(chart_type_atom)}")
    Logger.info("Query params: #{inspect(conn.query_params)}")

    if chart_type_atom == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Get title and description from query params
      title = conn.query_params["title"] || "Activity Chart"
      description = conn.query_params["description"] || "Generated from character activity data"

      # Get real data when available, otherwise use mock data
      activity_data = get_real_activity_data()

      # Generate chart and send it to Discord (not just relying on cached URL)
      chart_result = case chart_type_atom do
        :activity_summary -> ActivityChartAdapter.generate_character_activity_chart(activity_data)
        :activity_timeline -> ActivityChartAdapter.generate_activity_timeline_chart(activity_data)
        :activity_distribution -> ActivityChartAdapter.generate_activity_distribution_chart(activity_data)
      end

      result = case chart_result do
        {:ok, url} ->
          # Get the notifier and send chart as embed
          notifier = WandererNotifier.NotifierFactory.get_notifier()
          notifier.send_embed(title, description, url)

        {:error, reason} ->
          Logger.error("Failed to generate #{chart_type_atom} chart for Discord: #{inspect(reason)}")
          {:error, reason}
      end

      case result do
        :ok ->
          Logger.info("Sent #{chart_type_atom} chart to Discord")
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", message: "Chart sent to Discord"}))
        {:error, reason} ->
          Logger.error("Failed to send #{chart_type_atom} chart to Discord: #{inspect(reason)}")
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to send chart to Discord: #{reason}"}))
      end
    end
  end

  @doc """
  Handles requests to send all activity charts to Discord.
  Responds with JSON indicating success or failure.
  """
  get "/send-all" do
    Logger.info("Request to send all activity charts to Discord")
    
    # Get real data when available, otherwise use mock data
    activity_data = get_real_activity_data()

    # Trigger the scheduler to send all charts, passing in real data if available
    results = if activity_data != nil do
      ActivityChartAdapter.send_all_charts_to_discord(activity_data)
    else
      ActivityChartAdapter.send_all_charts_to_discord()
    end

    # Log the results
    Enum.each(results, fn {type, result} ->
      case result do
        :ok -> Logger.info("Successfully sent #{type} chart to Discord")
        {:error, reason} -> Logger.error("Failed to send #{type} chart to Discord: #{inspect(reason)}")
      end
    end)

    # Check if any chart was successfully sent
    any_success = Enum.any?(Map.values(results), fn result -> result == :ok end)

    if any_success do
      # Respond with success message
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", message: "Activity charts sent to Discord", results: inspect(results)}))
    else
      # If all charts failed, return error
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to send any activity charts to Discord", results: inspect(results)}))
    end
  end

  @doc """
  Fetches character activity data for display in the UI.
  Responds with JSON containing the activity data.
  """
  get "/character-activity" do
    case get_real_activity_data() || fetch_activity_data() do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", data: %{data: data}}))
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to fetch activity data: #{reason}"}))
      nil ->
        # Fall back to mock data if get_real_activity_data returns nil
        {:ok, mock_data} = fetch_activity_data()
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", data: %{data: mock_data}}))
    end
  end

  # Catch-all route
  match _ do
    Logger.warn("Unmatched route in ActivityChartController: #{inspect(conn.request_path)}")
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Try to get real character activity data from the Map client
  defp get_real_activity_data do
    if Config.map_tools_enabled?() do
      # Try to get the slug from configuration
      slug = Config.map_name()
      
      # Only attempt to fetch data if we have a slug
      if slug && slug != "" do
        Logger.info("Attempting to fetch real character activity data with slug: #{slug}")
        case MapClient.get_character_activity(slug) do
          {:ok, data} -> 
            Logger.info("Successfully fetched real character activity data")
            {:ok, data["data"]}
          {:error, reason} ->
            Logger.error("Failed to fetch real character activity data: #{inspect(reason)}")
            nil
        end
      else
        Logger.info("No map slug configured, using mock data")
        nil
      end
    else
      Logger.info("Map tools not enabled, using mock data")
      nil
    end
  end

  # Helper function to fetch mock activity data
  defp fetch_activity_data do
    # Mock data
    mock_data = [
      %{
        "character" => %{
          "name" => "Pilot Alpha",
          "corporation_ticker" => "CORP",
          "alliance_ticker" => "ALLY"
        },
        "connections" => 42,
        "passages" => 15,
        "signatures" => 23,
        "timestamp" => "2023-07-15T18:30:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Beta",
          "corporation_ticker" => "CORP",
          "alliance_ticker" => "ALLY"
        },
        "connections" => 35,
        "passages" => 22,
        "signatures" => 19,
        "timestamp" => "2023-07-15T19:45:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Gamma",
          "corporation_ticker" => "XCORP",
          "alliance_ticker" => "XALLY"
        },
        "connections" => 27,
        "passages" => 18,
        "signatures" => 31,
        "timestamp" => "2023-07-15T17:15:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Delta",
          "corporation_ticker" => "DCORP",
          "alliance_ticker" => nil
        },
        "connections" => 19,
        "passages" => 7,
        "signatures" => 14,
        "timestamp" => "2023-07-15T20:00:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Epsilon",
          "corporation_ticker" => "ECORP",
          "alliance_ticker" => "EALLY"
        },
        "connections" => 31,
        "passages" => 12,
        "signatures" => 8,
        "timestamp" => "2023-07-15T18:00:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Zeta",
          "corporation_ticker" => "ZCORP",
          "alliance_ticker" => "ZALLY"
        },
        "connections" => 15,
        "passages" => 9,
        "signatures" => 11,
        "timestamp" => "2023-07-15T21:30:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Eta",
          "corporation_ticker" => "HCORP",
          "alliance_ticker" => "HALLY"
        },
        "connections" => 22,
        "passages" => 17,
        "signatures" => 25,
        "timestamp" => "2023-07-15T22:15:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Theta",
          "corporation_ticker" => "TCORP",
          "alliance_ticker" => nil
        },
        "connections" => 9,
        "passages" => 5,
        "signatures" => 13,
        "timestamp" => "2023-07-15T23:00:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Iota",
          "corporation_ticker" => "ICORP",
          "alliance_ticker" => "IALY"
        },
        "connections" => 18,
        "passages" => 14,
        "signatures" => 20,
        "timestamp" => "2023-07-16T00:30:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Kappa",
          "corporation_ticker" => "KCORP",
          "alliance_ticker" => "KALLY"
        },
        "connections" => 25,
        "passages" => 19,
        "signatures" => 17,
        "timestamp" => "2023-07-16T01:45:00Z"
      }
    ]

    {:ok, mock_data}
  end
end 