defmodule WandererNotifier.Application do
  @moduledoc """
  The WandererNotifier OTP application.
  """
  use Application
  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.NotifierFactory
  alias WandererNotifier.Helpers.CacheHelpers

  @impl true
  def start(_type, _args) do
    Logger.info("Starting WandererNotifier...")

    # Get the environment from system environment variable
    env = System.get_env("MIX_ENV", "prod") |> String.to_atom()

    # Start ExSync in development mode
    if env == :dev do
      Logger.info("Starting ExSync for hot code reloading")
      # Handle the case where ExSync is not available
      case Application.ensure_all_started(:exsync) do
        {:ok, _} -> Logger.info("ExSync started successfully")
        {:error, _} -> Logger.warning("ExSync not available, continuing without hot reloading")
      end
    end

    # Set the environment in the application configuration
    Application.put_env(:wanderer_notifier, :env, env)

    Logger.info("Starting WandererNotifier application...")
    Logger.info("Environment: #{env}")

    # Log configuration details
    license_key = Config.license_key()
    license_manager_url = Config.license_manager_api_url()
    # Bot API token is determined by the environment

    Logger.info("License Key configured: #{if license_key && license_key != "", do: "Yes", else: "No"}")
    Logger.info("License Manager URL: #{license_manager_url || "Not configured"}")
    Logger.info("Bot API Token: #{if env == :prod, do: "Using production token", else: "Using environment token"}")

    # Log notification configuration
    character_tracking_enabled = Config.character_tracking_enabled?()
    character_notifications_enabled = Config.character_notifications_enabled?()
    system_notifications_enabled = Config.system_notifications_enabled?()

    Logger.info("Character tracking enabled: #{character_tracking_enabled}")
    Logger.info("Character notifications enabled: #{character_notifications_enabled}")
    Logger.info("System notifications enabled: #{system_notifications_enabled}")

    # Start the license validation service first
    children = [
      # Start the Cache Repository
      WandererNotifier.Cache.Repository,

      # Start the License validation service
      WandererNotifier.License,

      # Start the Stats tracking service
      WandererNotifier.Stats,

      # Start the Web server
      {Plug.Cowboy, scheme: :http, plug: WandererNotifier.Web.Router, options: [port: Config.web_port(), ip: {0, 0, 0, 0}]},

      # Start the main service that handles ZKill websocket
      {WandererNotifier.Service, []}
    ]

    Logger.info("Starting supervisor with #{length(children)} children...")
    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Supervisor started successfully with PID: #{inspect(pid)}")

        # Schedule license validation to run asynchronously
        Process.send_after(self(), :validate_license, 1000)

        # Check cache status after startup
        Process.send_after(self(), :check_cache_status, 2000)

        # Send a test notification after a short delay
        Process.send_after(self(), :send_test_notification, 5000)

        {:ok, pid}

      error ->
        Logger.error("Failed to start supervisor: #{inspect(error)}")
        error
    end
  end

  # Handle license validation asynchronously
  def handle_info(:validate_license, _state) do
    try do
      # Use a timeout to prevent blocking
      case GenServer.call(WandererNotifier.License, :validate, 3000) do
        license_status when is_map(license_status) ->
          if license_status.valid do
            Logger.info("License validation successful - License is valid")
          else
            error_message = license_status.error_message || "Unknown license error"
            Logger.error("License validation failed: #{error_message}")
            Logger.warning("The application will continue to run in limited mode")
          end
        _ ->
          Logger.error("License validation returned unexpected result")
      end
    rescue
      e ->
        Logger.error("License validation error: #{inspect(e)}")
        Logger.warning("The application will continue to run in limited mode")
    catch
      :exit, {:timeout, _} ->
        Logger.error("License validation timed out")
        Logger.warning("The application will continue to run in limited mode")
      type, reason ->
        Logger.error("License validation error: #{inspect(type)}, #{inspect(reason)}")
        Logger.warning("The application will continue to run in limited mode")
    end

    {:noreply, nil}
  end

  # This is not part of the Application behaviour, but we handle it for the test notification
  def handle_info(:send_test_notification, _state) do
    Logger.info("Sending test notification...")
    NotifierFactory.notify(:send_message, ["Test notification from WandererNotifier. If you see this, notifications are working!"])
    {:noreply, nil}
  end

  # Check cache status
  def handle_info(:check_cache_status, _state) do
    Logger.info("Checking cache status...")

    # Check if cache is available
    cache_available = case Cachex.stats(:wanderer_notifier_cache) do
      {:ok, _stats} -> true
      _ -> false
    end

    Logger.info("Cache available: #{cache_available}")

    # Get systems count
    systems = get_tracked_systems()
    Logger.info("Cache status - Systems: #{length(systems)}")

    # Get characters count
    characters = CacheRepo.get("map:characters") || []
    Logger.info("Cache status - Characters: #{length(characters)}")

    {:noreply, nil}
  end

  @doc """
  Validates the license and bot assignment.
  If the license is invalid, logs an error but allows the application to continue with limited functionality.
  """
  def validate_license_and_bot_assignment do
    Logger.info("Starting license validation process...")
    license_status = WandererNotifier.License.validate()

    if license_status.valid do
      Logger.info("License validation successful - License is valid")
      :ok
    else
      error_message = license_status.error_message || "Unknown license error"
      Logger.error("License validation failed: #{error_message}")
      Logger.warning("The application will continue to run in limited mode")
      :ok
    end
  end

  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  @doc """
  Called when a file is changed and code is reloaded in development.
  This replaces the functionality in DevCallbacks.
  """
  def reload(modules) do
    Logger.info("Reloaded modules: #{inspect(modules)}")
    :ok
  end
end
