defmodule WandererNotifier.Contexts.ExternalAdapters do
  @moduledoc """
  Backward compatibility adapter for external service integrations.
  
  This module maintains the existing ExternalAdapters API while delegating
  to the new consolidated context modules:
  - ApiContext for external API integrations
  - NotificationContext for Discord and notification operations
  
  This allows existing code to continue working without changes while
  providing a migration path to the new, more focused contexts.
  """
  
  # Delegate to the appropriate new contexts
  alias WandererNotifier.Contexts.{ApiContext, NotificationContext}

  # ──────────────────────────────────────────────────────────────────────────────
  # HTTP Client - delegated to ApiContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Makes an HTTP GET request with retry logic and error handling."
  @spec http_get(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate http_get(url, headers \\ []), to: ApiContext

  @doc "Makes an HTTP POST request with retry logic and error handling."
  @spec http_post(String.t(), any(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate http_post(url, body, headers \\ []), to: ApiContext

  # ──────────────────────────────────────────────────────────────────────────────
  # EVE ESI API - delegated to ApiContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Gets character information from ESI."
  @spec get_character(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_character(character_id), to: ApiContext

  @doc "Gets corporation information from ESI."
  @spec get_corporation(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_corporation(corporation_id), to: ApiContext

  @doc "Gets alliance information from ESI."
  @spec get_alliance(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_alliance(alliance_id), to: ApiContext

  @doc "Gets killmail from ESI."
  @spec get_killmail(integer() | String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_killmail(killmail_id, hash), to: ApiContext

  @doc "Gets ship type information from ESI."
  @spec get_ship_type(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_ship_type(type_id), to: ApiContext

  @doc "Gets system static information."
  @spec get_system_info(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_system_info(system_id), to: ApiContext

  # ──────────────────────────────────────────────────────────────────────────────
  # Map API - delegated to ApiContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Gets tracked systems from the map API."
  @spec get_tracked_systems() :: {:ok, list()} | {:error, term()}
  defdelegate get_tracked_systems(), to: ApiContext

  @doc "Gets tracked characters from the map API."
  @spec get_tracked_characters() :: {:ok, list()} | {:error, term()}
  defdelegate get_tracked_characters(), to: ApiContext

  # ──────────────────────────────────────────────────────────────────────────────
  # License Management - delegated to ApiContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Validates the application license."
  @spec validate_license(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate validate_license(api_token, license_key), to: ApiContext

  @doc "Checks if premium features are enabled."
  @spec premium_features_enabled?() :: boolean()
  defdelegate premium_features_enabled?(), to: ApiContext

  # ──────────────────────────────────────────────────────────────────────────────
  # Discord Integration - delegated to NotificationContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Sends a Discord notification."
  @spec send_discord_notification(map()) :: {:ok, any()} | {:error, term()}
  def send_discord_notification(notification) do
    # Convert the old API to the new notification context API
    case NotificationContext.send_kill_notification(notification) do
      {:ok, :sent} -> {:ok, :sent}
      {:ok, :skipped} -> {:ok, :sent}  # Maintain backward compatibility
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Sends a status message to Discord."
  @spec send_status_message(String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  defdelegate send_status_message(message, opts \\ []), to: NotificationContext

  @doc "Gets the configured Discord channel ID."
  @spec discord_channel_id() :: String.t() | nil
  defdelegate discord_channel_id(), to: NotificationContext, as: :get_discord_channel

  @doc "Sends a notification through the notification service."
  @spec send_notification(map(), keyword()) :: {:ok, any()} | {:error, term()}
  def send_notification(notification, opts \\ []) do
    # Convert to new notification context format
    case NotificationContext.send_discord_embed(notification, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
end
