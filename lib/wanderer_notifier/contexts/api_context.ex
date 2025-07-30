defmodule WandererNotifier.Contexts.ApiContext do
  @moduledoc """
  Context module for external API integrations.

  Provides a clean API boundary for all external service integrations including:
  - EVE Swagger Interface (ESI) for character, corporation, alliance data
  - Map API for tracked systems and characters
  - License service for premium feature validation
  - HTTP utilities for general-purpose requests

  This context consolidates scattered external integration logic into a single,
  cohesive interface that abstracts the complexity of different external services.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Adapters.ESI.Client, as: ESIClient
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Infrastructure.Cache

  # ──────────────────────────────────────────────────────────────────────────────
  # EVE ESI API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets character information from ESI with caching.
  """
  @spec get_character(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_character(character_id) do
    ESIClient.get_character_info(character_id)
  end

  @doc """
  Gets corporation information from ESI with caching.
  """
  @spec get_corporation(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_corporation(corporation_id) do
    ESIClient.get_corporation_info(corporation_id)
  end

  @doc """
  Gets alliance information from ESI with caching.
  """
  @spec get_alliance(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_alliance(alliance_id) do
    ESIClient.get_alliance_info(alliance_id)
  end

  @doc """
  Gets killmail data from ESI.
  """
  @spec get_killmail(integer() | String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_killmail(killmail_id, hash) do
    ESIClient.get_killmail(killmail_id, hash)
  end

  @doc """
  Gets ship type information from ESI.
  """
  @spec get_ship_type(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_ship_type(type_id) do
    ESIClient.get_universe_type(type_id)
  end

  @doc """
  Gets system information from ESI.
  """
  @spec get_system_info(integer() | String.t()) :: {:ok, map()} | {:error, term()}
  def get_system_info(system_id) do
    WandererNotifier.Domains.Tracking.StaticInfo.get_system_info(system_id)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Map API Integration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets tracked systems from the map API with caching.

  This function first checks the cache for existing system data before
  making an external API call, improving performance and reducing API load.
  """
  @spec get_tracked_systems() :: {:ok, list()} | {:error, term()}
  def get_tracked_systems do
    case Cache.get("map:systems") do
      {:ok, systems} when is_list(systems) ->
        Logger.debug("Retrieved tracked systems from cache",
          count: length(systems),
          category: :api
        )

        {:ok, systems}

      {:ok, _invalid_data} ->
        Logger.warning("Invalid cached systems data, falling back to API", category: :api)
        fetch_systems_from_api()

      {:error, :not_found} ->
        Logger.debug("No cached systems found, fetching from API", category: :api)
        fetch_systems_from_api()
    end
  end

  @doc """
  Gets tracked characters from the map API with caching.

  Similar to get_tracked_systems/0, this function prioritizes cached data
  to improve performance while maintaining data freshness.
  """
  @spec get_tracked_characters() :: {:ok, list()} | {:error, term()}
  def get_tracked_characters do
    Logger.debug("ApiContext.get_tracked_characters called", category: :api)

    case Cache.get("map:character_list") do
      {:ok, characters} when is_list(characters) ->
        Logger.info("Retrieved tracked characters from cache",
          character_count: length(characters),
          category: :api
        )

        {:ok, characters}

      {:ok, _invalid_data} ->
        Logger.warning("Invalid cached character data, falling back to API", category: :api)
        fetch_characters_from_api()

      {:error, :not_found} ->
        Logger.debug("No cached characters found, fetching from API", category: :api)
        fetch_characters_from_api()
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # License Management
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Validates the application license with the license service.
  """
  @spec validate_license(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def validate_license(api_token, license_key) do
    WandererNotifier.Domains.License.LicenseService.validate_bot(api_token, license_key)
  end

  @doc """
  Checks if premium features are enabled based on current license status.
  """
  @spec premium_features_enabled?() :: boolean()
  def premium_features_enabled? do
    case WandererNotifier.Domains.License.LicenseService.status() do
      %{status: :active} -> true
      _ -> false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # General HTTP Utilities
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Makes an HTTP GET request with automatic retry logic and error handling.

  Uses the unified HTTP client with appropriate service configuration,
  rate limiting, and circuit breaker patterns.
  """
  @spec http_get(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def http_get(url, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    service = Keyword.get(opts, :service, :default)

    Http.request(:get, url, nil, headers, service: service)
  end

  @doc """
  Makes an HTTP POST request with automatic retry logic and error handling.
  """
  @spec http_post(String.t(), any(), keyword()) :: {:ok, map()} | {:error, term()}
  def http_post(url, body, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    service = Keyword.get(opts, :service, :default)

    Http.request(:post, url, body, headers, service: service)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp fetch_systems_from_api do
    Logger.debug("Fetching systems from map API", category: :api)

    case WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_systems() do
      {:ok, systems} ->
        Logger.info("Successfully fetched systems from API",
          count: length(systems),
          category: :api
        )

        {:ok, systems}

      {:error, reason} = error ->
        Logger.error("Failed to fetch systems from API",
          error: inspect(reason),
          category: :api
        )

        error
    end
  end

  defp fetch_characters_from_api do
    Logger.debug("Fetching characters from map API", category: :api)

    case WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_characters() do
      {:ok, characters} ->
        Logger.info("Successfully fetched characters from API",
          count: length(characters),
          category: :api
        )

        {:ok, characters}

      {:error, reason} = error ->
        Logger.error("Failed to fetch characters from API",
          error: inspect(reason),
          category: :api
        )

        error
    end
  end
end
