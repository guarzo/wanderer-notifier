defmodule WandererNotifier.Contexts.ExternalAdapters do
  @moduledoc """
  Context module for external service adapters.
  Provides a clean API boundary for all external integrations like HTTP clients,
  Discord notifications, and third-party APIs.
  """

  alias WandererNotifier.Infrastructure.Adapters.ESI.Client
  alias WandererNotifier.Infrastructure.Http, as: HTTP

  # ──────────────────────────────────────────────────────────────────────────────
  # HTTP Client
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Makes an HTTP GET request with retry logic and error handling.
  """
  @spec http_get(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate http_get(url, headers \\ []), to: HTTP, as: :get

  @doc """
  Makes an HTTP POST request with retry logic and error handling.
  """
  @spec http_post(String.t(), any(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate http_post(url, body, headers \\ []), to: HTTP, as: :post

  # ──────────────────────────────────────────────────────────────────────────────
  # EVE ESI API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets character information from ESI.
  """
  @spec get_character(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_character(character_id), to: Client, as: :get_character_info

  @doc """
  Gets corporation information from ESI.
  """
  @spec get_corporation(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_corporation(corporation_id), to: Client, as: :get_corporation_info

  @doc """
  Gets alliance information from ESI.
  """
  @spec get_alliance(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_alliance(alliance_id), to: Client, as: :get_alliance_info

  @doc """
  Gets killmail from ESI.
  """
  @spec get_killmail(integer() | String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_killmail(killmail_id, hash), to: Client

  @doc """
  Gets ship type information from ESI.
  """
  @spec get_ship_type(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_ship_type(type_id), to: Client, as: :get_universe_type

  # ──────────────────────────────────────────────────────────────────────────────
  # Map API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets tracked systems from the map API.
  """
  @spec get_tracked_systems() :: {:ok, list()} | {:error, term()}
  def get_tracked_systems do
    WandererNotifier.Domains.SystemTracking.Client.get_all()
  end

  @doc """
  Gets tracked characters from the map API.
  """
  @spec get_tracked_characters() :: {:ok, list()} | {:error, term()}
  def get_tracked_characters do
    WandererNotifier.Domains.CharacterTracking.Client.get_all()
  end

  @doc """
  Gets system static information.
  """
  @spec get_system_info(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_system_info(system_id) do
    WandererNotifier.Domains.SystemTracking.StaticInfo.get_system_info(system_id)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Discord Integration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Sends a Discord notification.
  """
  @spec send_discord_notification(map()) :: {:ok, any()} | {:error, term()}
  def send_discord_notification(notification) do
    case WandererNotifier.Application.Services.NotificationService.notify_kill(notification) do
      :ok -> {:ok, :sent}
      {:error, :notifications_disabled} -> {:ok, :sent}
      error -> error
    end
  end

  @doc """
  Sends a status message to Discord.
  """
  @spec send_status_message(String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def send_status_message(message, opts \\ []) do
    # Status formatter doesn't have send_status_message, using Discord notifier directly
    _type = Keyword.get(opts, :type, :info)
    WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier.send_message(message)
  end

  @doc """
  Gets the configured Discord channel ID.
  """
  @spec discord_channel_id() :: String.t() | nil
  defdelegate discord_channel_id(),
    to: WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient,
    as: :channel_id

  # ──────────────────────────────────────────────────────────────────────────────
  # License Management
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Validates the application license.
  """
  @spec validate_license(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate validate_license(api_token, license_key),
    to: WandererNotifier.Domains.License.Client,
    as: :validate_bot

  @doc """
  Checks if premium features are enabled.
  """
  @spec premium_features_enabled?() :: boolean()
  def premium_features_enabled? do
    case WandererNotifier.Domains.License.Service.status() do
      %{status: :active} -> true
      _ -> false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Notification Service
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Sends a notification through the notification service.
  """
  @spec send_notification(map(), keyword()) :: {:ok, any()} | {:error, term()}
  def send_notification(notification, opts \\ []) do
    channel_id =
      Keyword.get(opts, :channel_id, WandererNotifier.Shared.Config.discord_channel_id())

    WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient.send_embed(
      notification,
      channel_id
    )
  end
end
