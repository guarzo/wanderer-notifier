defmodule WandererNotifier.Contexts.ExternalAdapters do
  @moduledoc """
  Context module for external service adapters.
  Provides a clean API boundary for all external integrations like HTTP clients,
  Discord notifications, and third-party APIs.
  """
  require Logger

  alias WandererNotifier.Infrastructure.Adapters.ESI.Client
  alias WandererNotifier.Infrastructure.Http, as: HTTP

  # ──────────────────────────────────────────────────────────────────────────────
  # HTTP Client
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Makes an HTTP GET request with retry logic and error handling.
  """
  @spec http_get(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def http_get(url, headers \\ []) do
    HTTP.request(:get, url, nil, headers, [])
  end

  @doc """
  Makes an HTTP POST request with retry logic and error handling.
  """
  @spec http_post(String.t(), any(), keyword()) :: {:ok, map()} | {:error, term()}
  def http_post(url, body, headers \\ []) do
    HTTP.request(:post, url, body, headers, [])
  end

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
    # Get from cache instead of fetching from API
    case WandererNotifier.Infrastructure.Cache.get("map:systems") do
      {:ok, systems} when is_list(systems) ->
        {:ok, systems}

      {:ok, _} ->
        {:ok, []}

      {:error, :not_found} ->
        # Only fetch from API if not in cache
        WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_systems()
    end
  end

  @doc """
  Gets tracked characters from the map API.
  """
  @spec get_tracked_characters() :: {:ok, list()} | {:error, term()}
  def get_tracked_characters do
    Logger.info("ExternalAdapters.get_tracked_characters called", [])

    # Get from cache instead of fetching from API
    case WandererNotifier.Infrastructure.Cache.get("map:character_list") do
      {:ok, characters} when is_list(characters) ->
        first_char = Enum.at(characters, 0)

        Logger.info("Retrieved characters from cache",
          character_count: length(characters),
          first_char_keys: (first_char && Map.keys(first_char)) |> inspect(),
          first_char_sample: inspect(first_char) |> String.slice(0, 500)
        )

        {:ok, characters}

      {:ok, _} ->
        Logger.warning("Cache returned non-list data for characters")
        {:ok, []}

      {:error, :not_found} ->
        Logger.warning("No characters found in cache, fetching from API")
        WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_characters()
    end
  end

  @doc """
  Gets system static information.
  """
  @spec get_system_info(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_system_info(system_id) do
    WandererNotifier.Domains.Tracking.StaticInfo.get_system_info(system_id)
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
      {:error, _reason} = error -> error
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
    to: WandererNotifier.Domains.License.Service,
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
