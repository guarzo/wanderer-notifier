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
  alias WandererNotifier.NotifierFactory
  alias WandererNotifier.Helpers.NotificationHelpers
  alias WandererNotifier.Web.Controllers.ChartController

  plug(Plug.Logger)

  # Serve JavaScript and CSS files with correct MIME types
  plug Plug.Static,
    at: "/assets",
    from: {:wanderer_notifier, "priv/static/app/assets"},
    headers: %{
      "access-control-allow-origin" => "*",
      "cache-control" => "public, max-age=0"
    }

  # Serve static assets directly
  plug Plug.Static,
    at: "/",
    from: {:wanderer_notifier, "priv/static/app"},
    only: ~w(index.html vite.svg favicon.ico test.html),
    headers: %{
      "access-control-allow-origin" => "*",
      "cache-control" => "public, max-age=0"
    }

  # Serve your React build from priv/static/app if desired
  plug Plug.Static,
    at: "/",
    from: :wanderer_notifier,
    only: ~w(app images css js favicon.ico robots.txt)

  plug :match
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug :dispatch

  # React app routes - these need to be before other routes to ensure proper SPA routing
  get "/charts" do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_file(200, "priv/static/app/index.html")
  end

  # Handle client-side routing for the React app
  get "/charts/*path" do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_file(200, "priv/static/app/index.html")
  end

  # Legacy TPS charts page - redirects to the new React dashboard
  get "/tps-charts" do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_file(200, "priv/templates/tps_charts.html.eex")
  end

  #
  # HEALTH CHECK ENDPOINT
  #

  get "/health" do
    # Check if critical services are running
    cache_available = case Cachex.stats(:wanderer_notifier_cache) do
      {:ok, _stats} -> true
      _ -> false
    end

    # Check if the service GenServer is alive
    service_alive = case Process.whereis(WandererNotifier.Service) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end

    # If critical services are running, return 200 OK
    if cache_available and service_alive do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", cache: cache_available, service: service_alive}))
    else
      # If any critical service is down, return 503 Service Unavailable
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(503, Jason.encode!(%{status: "error", cache: cache_available, service: service_alive}))
    end
  end

  #
  # CHART ROUTES
  #

  # Forward chart requests to the ChartController
  forward "/charts", to: ChartController

  #
  # API ROUTES (JSON)
  #

  get "/api/status" do
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
      limits = Features.get_all_limits()

      # Add error handling for tracked systems and characters
      tracked_systems = try do
        get_tracked_systems()
      rescue
        e ->
          Logger.error("Error getting tracked systems: #{inspect(e)}")
          []
      end

      tracked_characters = try do
        CacheRepo.get("map:characters") || []
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
    rescue
      e ->
        Logger.error("Error processing /api/status: #{inspect(e)}")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Internal server error", details: inspect(e)}))
    end
  end

  get "/api/test-notification" do
    Logger.info("Test notification endpoint called")

    result = WandererNotifier.Service.KillProcessor.send_test_kill_notification()

    response =
      case result do
        {:ok, kill_id} ->
          %{
            success: true,
            message: "Test notification sent for kill_id: #{kill_id}",
            details: "Check your Discord for the message."
          }

        {:error, :no_kills_available} ->
          %{
            success: false,
            message: "Failed to send test notification: No kills available",
            details: "No recent kills found in cache or from zKillboard API."
          }

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

  get "/api/test-character-notification" do
    Logger.info("Test character notification endpoint called")

    result = send_test_character_notification()

    response =
      case result do
        {:ok, character_id, character_name} ->
          %{
            success: true,
            message: "Test character notification sent for #{character_name} (ID: #{character_id})",
            details: "Check your Discord for the message."
          }

        {:error, :no_characters_available} ->
          %{
            success: false,
            message: "No tracked characters available",
            details: "Wait for character tracking or check your configuration."
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

  get "/api/test-system-notification" do
    Logger.info("Test system notification endpoint called")

    result = send_test_system_notification()

    response =
      case result do
        {:ok, system_id, system_name} ->
          %{
            success: true,
            message: "Test system notification sent for #{system_name} (ID: #{system_id})",
            details: "Check your Discord for the message."
          }

        {:error, :no_systems_available} ->
          %{
            success: false,
            message: "No tracked systems available",
            details: "Wait for system tracking or check your configuration."
          }

        {:error, reason} ->
          %{
            success: false,
            message: "Failed to send test system notification: #{inspect(reason)}",
            details: "Check logs for details."
          }
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

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

  get "/api/revalidate-license" do
    Logger.info("License revalidation requested")

    result = WandererNotifier.License.validate()

    response =
      case result do
        %{valid: true} ->
          %{
            success: true,
            message: "License validation successful",
            details: "License is valid and was revalidated with the server."
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

  get "/api/recent-kills" do
    Logger.info("Recent kills endpoint called")

    recent_kills = WandererNotifier.Service.KillProcessor.get_recent_kills()

    response = %{
      success: true,
      kills: recent_kills || []
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Handle test kill notification
  post "/api/test-kill" do
    case WandererNotifier.Service.KillProcessor.send_test_kill_notification() do
      {:ok, kill_id} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{success: true, message: "Test kill notification sent", kill_id: kill_id}))

      {:error, :no_kills_available} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{
             success: false,
             message: "Failed to send test notification: No kills available",
             details: "No recent kills found in cache or from zKillboard API."
           }))

      {:error, :no_kill_id} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{
             success: false,
             message: "Failed to send test notification: No kill ID found",
             details: "The kill data did not contain a valid kill ID."
           }))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{success: false, message: "Failed to send test notification", error: inspect(reason)}))
    end
  end

  #
  # Catch-all: serve the React index.html from priv/static/app
  #
  match _ do
    Logger.info("Serving React app for path: #{conn.request_path}")

    index_path = Path.join(:code.priv_dir(:wanderer_notifier), "static/app/index.html")
    Logger.info("Serving index.html from: #{index_path}")

    if File.exists?(index_path) do
      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> Plug.Conn.send_file(200, index_path)
    else
      Logger.error("Index file not found at: #{index_path}")
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not found: #{conn.request_path}")
    end
  end

  #
  # Helper Functions
  #

  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil
  defp calculate_percentage(current, limit) when limit > 0, do: min(100, round(current / limit * 100))
  defp calculate_percentage(_, _), do: 0

  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  #
  # Character Notification
  #
  defp send_test_character_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test character notification")
    tracked_characters = CacheRepo.get("map:characters") || []
    Logger.info("Found #{length(tracked_characters)} tracked characters")

    case tracked_characters do
      [] ->
        Logger.error("No tracked characters available")
        {:error, :no_characters_available}

      characters ->
        valid_chars = Enum.filter(characters, &valid_eve_id?/1)

        case valid_chars do
          [] ->
            Logger.error("No characters with valid numeric EVE IDs")
            {:error, :no_valid_characters_available}

          valid_list ->
            character = Enum.random(valid_list)
            {character_id, character_name} = extract_character_details(character)

            Logger.info("Using character #{character_name} (ID: #{character_id}) for test notification")
            result = NotifierFactory.notify(:send_new_tracked_character_notification, [character])

            case result do
              {:error, :invalid_character_id} ->
                Logger.error("Failed - invalid character ID")
                {:error, :invalid_character_id}

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
        Logger.error("No tracked systems available")
        {:error, :no_systems_available}

      systems ->
        system = Enum.random(systems)
        system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
        system_name =
          Map.get(system, "system_name") ||
            Map.get(system, :alias) ||
            Map.get(system, "name") ||
            "Unknown System"

        Logger.info("Using system #{system_name} (ID: #{system_id}) for test notification")
        NotifierFactory.notify(:send_new_system_notification, [system])

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
      (is_binary(nested_map["eve_id"]) and
         NotificationHelpers.is_valid_numeric_id?(nested_map["eve_id"])) ->
        true

      (is_binary(nested_map["character_id"]) and
         NotificationHelpers.is_valid_numeric_id?(nested_map["character_id"])) ->
        true

      (is_binary(nested_map["id"]) and
         NotificationHelpers.is_valid_numeric_id?(nested_map["id"])) ->
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

        is_map(character["character"]) && is_binary(character["character"]["eve_id"]) and
          NotificationHelpers.is_valid_numeric_id?(character["character"]["eve_id"]) ->
          character["character"]["eve_id"]

        is_map(character["character"]) && is_binary(character["character"]["character_id"]) and
          NotificationHelpers.is_valid_numeric_id?(character["character"]["character_id"]) ->
          character["character"]["character_id"]

        is_map(character["character"]) && is_binary(character["character"]["id"]) and
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
end
