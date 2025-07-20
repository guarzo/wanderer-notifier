defmodule WandererNotifier.Application.Services.Application.Service do
  @moduledoc """
  Core application service for managing application state and configuration.

  This GenServer manages the application lifecycle and provides access to
  configuration and statistics. Most configuration access is delegated to
  the API module for better separation of concerns.
  """

  use GenServer

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  # --- GenServer Callbacks ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.processor_info("Starting application service")

    # Stats is already supervised by the main application supervisor
    # No need to start it here

    # Return initial state
    {:ok, %{started_at: System.system_time(:second)}}
  end

  @impl true
  def handle_call(:health, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  @impl true
  def handle_info({:zkill_message, _message}, state) do
    # This GenServer should not be receiving zkill messages
    # Log and ignore them
    AppLogger.processor_warn("Application.Service received unexpected zkill message - ignoring")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    AppLogger.processor_warn("Application.Service received unexpected message",
      message: inspect(msg)
    )

    {:noreply, state}
  end

  # --- Public API ---

  @doc """
  Checks the health of the application service.
  """
  def health do
    GenServer.call(__MODULE__, :health)
  end

  @doc """
  Checks if the service is running.
  """
  def running? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end

  # --- Configuration Delegation ---
  # All configuration access is delegated to the API module for separation of concerns

  defdelegate env(), to: WandererNotifier.Application.Services.Application.API
  defdelegate version(), to: WandererNotifier.Application.Services.Application.API
  defdelegate license_status(), to: WandererNotifier.Application.Services.Application.API
  defdelegate license_key(), to: WandererNotifier.Application.Services.Application.API
  defdelegate license_manager_api_url(), to: WandererNotifier.Application.Services.Application.API
  defdelegate license_manager_api_key(), to: WandererNotifier.Application.Services.Application.API
  defdelegate api_token(), to: WandererNotifier.Application.Services.Application.API
  defdelegate api_key(), to: WandererNotifier.Application.Services.Application.API
  defdelegate api_base_url(), to: WandererNotifier.Application.Services.Application.API
  defdelegate notifier_api_token(), to: WandererNotifier.Application.Services.Application.API
  defdelegate map_url(), to: WandererNotifier.Application.Services.Application.API
  defdelegate map_token(), to: WandererNotifier.Application.Services.Application.API
  defdelegate map_name(), to: WandererNotifier.Application.Services.Application.API
  defdelegate map_api_key(), to: WandererNotifier.Application.Services.Application.API
  defdelegate discord_channel_id(), to: WandererNotifier.Application.Services.Application.API

  defdelegate discord_system_kill_channel_id(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate discord_character_kill_channel_id(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate discord_system_channel_id(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate discord_character_channel_id(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate discord_charts_channel_id(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate discord_bot_token(), to: WandererNotifier.Application.Services.Application.API
  defdelegate discord_webhook_url(), to: WandererNotifier.Application.Services.Application.API
  defdelegate debug_logging_enabled?(), to: WandererNotifier.Application.Services.Application.API
  defdelegate enable_debug_logging(), to: WandererNotifier.Application.Services.Application.API
  defdelegate disable_debug_logging(), to: WandererNotifier.Application.Services.Application.API
  defdelegate set_debug_logging(state), to: WandererNotifier.Application.Services.Application.API
  defdelegate dev_mode?(), to: WandererNotifier.Application.Services.Application.API
  defdelegate notification_features(), to: WandererNotifier.Application.Services.Application.API

  defdelegate notification_feature_enabled?(flag),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate features(), to: WandererNotifier.Application.Services.Application.API
  defdelegate feature_enabled?(flag), to: WandererNotifier.Application.Services.Application.API

  defdelegate status_messages_enabled?(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate character_tracking_enabled?(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate system_tracking_enabled?(),
    to: WandererNotifier.Application.Services.Application.API

  defdelegate cache_dir(), to: WandererNotifier.Application.Services.Application.API
  defdelegate cache_name(), to: WandererNotifier.Application.Services.Application.API
  defdelegate port(), to: WandererNotifier.Application.Services.Application.API
  defdelegate host(), to: WandererNotifier.Application.Services.Application.API
  defdelegate scheme(), to: WandererNotifier.Application.Services.Application.API
  defdelegate public_url(), to: WandererNotifier.Application.Services.Application.API

  defdelegate get_env(key, default \\ nil),
    to: WandererNotifier.Application.Services.Application.API

  # --- Statistics Delegation ---

  defdelegate get_all_stats(), to: WandererNotifier.Application.Services.Application.API
  defdelegate increment_counter(type), to: WandererNotifier.Application.Services.Application.API
end
