defmodule WandererNotifier.Application do
  @moduledoc """
  The WandererNotifier OTP application.
  """
  use Application
  require Logger
  alias WandererNotifier.Config

  @impl true
  def start(_type, _args) do
    Logger.info("Starting WandererNotifier application...")
    Logger.info("Environment: #{Mix.env()}")

    # Log configuration details
    license_key = Config.license_key()
    license_manager_url = Config.license_manager_api_url()
    bot_id = Config.bot_id()

    Logger.info("License Key configured: #{if license_key && license_key != "", do: "Yes", else: "No"}")
    Logger.info("License Manager URL: #{license_manager_url || "Not configured"}")
    Logger.info("Bot ID configured: #{if bot_id && bot_id != "", do: "Yes", else: "No"}")

    # Start the license validation service first
    children = [
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
        validate_license_and_bot_assignment()
        {:ok, pid}

      error ->
        Logger.error("Failed to start supervisor: #{inspect(error)}")
        error
    end
  end

  @doc """
  Validates the license and bot assignment.
  If the license is invalid, logs an error but allows the application to continue with limited functionality.
  """
  def validate_license_and_bot_assignment do
    Logger.info("Starting license validation process...")
    license_status = WandererNotifier.License.validate()
    
    cond do
      # Both license is valid and bot is assigned
      license_status.valid && license_status.bot_assigned ->
        Logger.info("License validation successful - License is valid and bot is properly assigned")
        :ok
        
      # License is valid but bot is not assigned
      license_status.valid && !license_status.bot_assigned ->
        Logger.warning("License is valid but bot is not assigned to this license")
        Logger.warning("The application will continue to run, but some features may be limited")
        :ok
        
      # License is not valid
      !license_status.valid ->
        error_message = license_status.error_message || "Unknown license error"
        Logger.error("License validation failed: #{error_message}")
        Logger.warning("The application will continue to run in limited mode")
        :ok
    end
  end
end
