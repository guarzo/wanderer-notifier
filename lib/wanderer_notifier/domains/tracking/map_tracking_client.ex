defmodule WandererNotifier.Domains.Tracking.MapTrackingClient do
  @moduledoc """
  Simplified tracking client that removes Process dictionary usage and complex abstractions.

  This module provides direct function calls with explicit parameters instead of
  threading context through the Process dictionary. This makes the code easier
  to understand, debug, and test while maintaining all functionality.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Domains.Tracking.StaticInfo

  @type entity_type :: :characters | :systems
  @type entity_config :: %{
          endpoint: String.t(),
          cache_key: String.t(),
          batch_size: integer(),
          requires_slug: boolean()
        }

  # Entity configurations without function references (simpler)
  @entity_configs %{
    characters: %{
      endpoint: "tracked-characters",
      cache_key: "map:character_list",
      batch_size: 25,
      requires_slug: true
    },
    systems: %{
      endpoint: "systems",
      cache_key: "map:systems",
      batch_size: 50,
      requires_slug: false
    }
  }

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API - Direct function calls with explicit parameters
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Fetches and caches character data from the map API.
  """
  @spec fetch_and_cache_characters() :: {:ok, list()} | {:error, term()}
  def fetch_and_cache_characters do
    Logger.debug("MapTrackingClient.fetch_and_cache_characters called")
    fetch_and_cache_entities(:characters)
  end

  @doc """
  Fetches and caches character data from the map API.
  Optional skip_notifications parameter prevents notifications during initial load.
  """
  @spec fetch_and_cache_characters(boolean()) :: {:ok, list()} | {:error, term()}
  def fetch_and_cache_characters(skip_notifications) do
    Logger.debug("MapTrackingClient.fetch_and_cache_characters called",
      skip_notifications: skip_notifications
    )

    fetch_and_cache_entities(:characters, skip_notifications)
  end

  @doc """
  Fetches and caches system data from the map API.
  """
  @spec fetch_and_cache_systems() :: {:ok, list()} | {:error, term()}
  def fetch_and_cache_systems do
    fetch_and_cache_entities(:systems)
  end

  @doc """
  Fetches and caches system data from the map API.
  Optional skip_notifications parameter prevents notifications during initial load.
  """
  @spec fetch_and_cache_systems(boolean()) :: {:ok, list()} | {:error, term()}
  def fetch_and_cache_systems(skip_notifications) do
    Logger.debug("MapTrackingClient.fetch_and_cache_systems called",
      skip_notifications: skip_notifications
    )

    fetch_and_cache_entities(:systems, skip_notifications)
  end

  @doc """
  Generic method to fetch and cache entities with explicit entity type parameter.
  """
  @spec fetch_and_cache_entities(entity_type()) :: {:ok, list()} | {:error, term()}
  def fetch_and_cache_entities(entity_type) when entity_type in [:characters, :systems] do
    fetch_and_cache_entities(entity_type, false)
  end

  @spec fetch_and_cache_entities(entity_type(), boolean()) :: {:ok, list()} | {:error, term()}
  def fetch_and_cache_entities(entity_type, skip_notifications)
      when entity_type in [:characters, :systems] do
    config = get_entity_config(entity_type)

    case fetch_from_api(entity_type, config) do
      {:ok, entities} ->
        cache_entities(entity_type, entities, config)
        process_entities(entity_type, entities, skip_notifications)
        {:ok, entities}

      {:error, reason} ->
        Logger.error("Failed to fetch #{entity_type}", reason: inspect(reason), category: :api)
        {:error, reason}
    end
  end

  @doc """
  Checks if a character is tracked.
  """
  @spec is_character_tracked?(String.t()) :: {:ok, boolean()} | {:error, term()}
  def is_character_tracked?(character_id) when is_binary(character_id) do
    case Cache.get("map:character_list") do
      {:ok, characters} when is_list(characters) ->
        check_character_in_list(characters, character_id)

      {:ok, _} ->
        {:ok, false}

      {:error, :not_found} ->
        {:ok, false}
    end
  end

  def is_character_tracked?(character_id) when is_integer(character_id) do
    is_character_tracked?(Integer.to_string(character_id))
  end

  defp check_character_in_list(characters, character_id) do
    tracked = Enum.any?(characters, &character_matches?(character_id, &1))

    unless tracked do
      handle_untracked_character(characters, character_id)
    end

    {:ok, tracked}
  end

  defp handle_untracked_character(characters, character_id) do
    Logger.debug("[MapTrackingClient] Character #{character_id} not tracked")

    exact_match = find_exact_character_match(characters, character_id)

    if exact_match do
      Logger.error(
        "[MapTrackingClient] Character WAS found but matching failed! Data: #{inspect(exact_match)}"
      )
    end
  end

  defp find_exact_character_match(characters, character_id) do
    Enum.find(characters, fn char ->
      check_character_eve_id(char, character_id)
    end)
  end

  defp check_character_eve_id(%{"character" => %{"eve_id" => id}}, character_id) do
    result = to_string(id) == to_string(character_id)

    if result do
      Logger.debug("[MapTrackingClient] Found exact match! eve_id: #{id}")
    end

    result
  end

  defp check_character_eve_id(_, _), do: false

  defp character_matches?(character_id, %{"character" => %{"eve_id" => id}}),
    do: to_string(id) == character_id

  defp character_matches?(character_id, %{character: %{eve_id: id}}),
    do: to_string(id) == character_id

  defp character_matches?(character_id, %{"eve_id" => id}), do: to_string(id) == character_id
  defp character_matches?(character_id, %{eve_id: id}), do: to_string(id) == character_id
  defp character_matches?(_, _), do: false

  @doc """
  Checks if a system is tracked.
  """
  @spec is_system_tracked?(String.t()) :: {:ok, boolean()} | {:error, term()}
  def is_system_tracked?(system_id) when is_binary(system_id) do
    case Cache.get("map:systems") do
      {:ok, systems} when is_list(systems) -> check_system_in_list(systems, system_id)
      {:ok, _} -> {:ok, false}
      {:error, :not_found} -> {:ok, false}
    end
  end

  def is_system_tracked?(system_id) when is_integer(system_id) do
    is_system_tracked?(Integer.to_string(system_id))
  end

  defp check_system_in_list(systems, system_id) do
    tracked = Enum.any?(systems, &system_matches?(system_id, &1))

    if not tracked do
      Logger.debug(
        "[MapTrackingClient] System #{system_id} not found in tracked list of #{length(systems)} systems"
      )

      sample_ids = extract_sample_system_ids(systems)
      Logger.debug("[MapTrackingClient] Sample tracked system IDs: #{inspect(sample_ids)}")
    end

    {:ok, tracked}
  end

  defp system_matches?(system_id, %System{solar_system_id: id}), do: to_string(id) == system_id
  defp system_matches?(system_id, %{"solar_system_id" => id}), do: to_string(id) == system_id
  defp system_matches?(system_id, %{solar_system_id: id}), do: to_string(id) == system_id
  defp system_matches?(_, _), do: false

  defp extract_sample_system_ids(systems) do
    systems
    |> Enum.take(5)
    |> Enum.map(fn sys ->
      case sys do
        %System{solar_system_id: id} -> id
        %{"solar_system_id" => id} -> id
        %{solar_system_id: id} -> id
        _ -> "unknown"
      end
    end)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Implementation - No Process dictionary needed
  # ══════════════════════════════════════════════════════════════════════════════

  @spec get_entity_config(entity_type()) :: entity_config()
  defp get_entity_config(entity_type) do
    Map.fetch!(@entity_configs, entity_type)
  end

  @spec fetch_from_api(entity_type(), entity_config()) :: {:ok, list()} | {:error, term()}
  defp fetch_from_api(entity_type, config) do
    url = build_url(entity_type, config)
    headers = build_headers()

    Logger.debug("Fetching #{entity_type} from API",
      url: url,
      has_auth: Enum.any?(headers, fn {k, _} -> k == "Authorization" end),
      category: :api
    )

    case Http.request(:get, url, nil, headers, service: :map, timeout: 30_000) do
      {:ok, %{status_code: 200, body: body}} ->
        parse_response(entity_type, body)

      {:ok, %{status_code: status_code} = response} ->
        Logger.error("HTTP #{status_code} error when fetching #{entity_type}",
          status_code: status_code,
          body: Map.get(response, :body),
          url: url,
          category: :api
        )

        {:error, {:http_error, status_code}}

      {:error, reason} ->
        Logger.error("Request failed for #{entity_type}",
          error: inspect(reason),
          url: url,
          category: :api
        )

        {:error, reason}
    end
  end

  @spec build_url(entity_type(), entity_config()) :: String.t()
  defp build_url(_entity_type, config) do
    base_url = Config.map_url()
    map_name = Config.map_name()
    endpoint = config.endpoint

    # The correct pattern is /api/maps/{map_name}/{endpoint}
    "#{base_url}/api/maps/#{map_name}/#{endpoint}"
  end

  @spec build_headers() :: list({String.t(), String.t()})
  defp build_headers do
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    api_key = Config.map_api_key()

    case api_key do
      nil ->
        Logger.warning("No MAP_API_KEY configured - requests will be unauthenticated",
          category: :api
        )

        headers

      "" ->
        Logger.warning("MAP_API_KEY is empty - requests will be unauthenticated", category: :api)
        headers

      api_key ->
        [{"Authorization", "Bearer #{api_key}"} | headers]
    end
  end

  @spec parse_response(entity_type(), term()) :: {:ok, list()} | {:error, term()}
  defp parse_response(:characters, %{"data" => characters}) when is_list(characters) do
    Logger.debug("MapTrackingClient parsed #{length(characters)} characters from API response")

    {:ok, characters}
  end

  defp parse_response(:systems, %{"data" => %{"systems" => systems}}) when is_list(systems) do
    {:ok, systems}
  end

  defp parse_response(entity_type, body) do
    Logger.error("Invalid response format for #{entity_type}",
      body_type: inspect(body |> get_body_type()),
      body_sample: inspect(body) |> String.slice(0, 200),
      category: :api
    )

    {:error, :invalid_response}
  end

  defp get_body_type(body) when is_list(body), do: "list with #{length(body)} items"
  defp get_body_type(body) when is_map(body), do: "map with keys: #{inspect(Map.keys(body))}"
  defp get_body_type(body), do: "#{inspect(body.__struct__ || :unknown)}"

  @spec cache_entities(entity_type(), list(), entity_config()) :: :ok
  defp cache_entities(entity_type, entities, config) do
    Cache.put(config.cache_key, entities, :timer.hours(1))

    Logger.debug("Cached #{length(entities)} #{entity_type}",
      category: :cache,
      cache_key: config.cache_key,
      sample_entity: inspect(Enum.at(entities, 0))
    )

    :ok
  end

  @spec process_entities(entity_type(), list(), boolean()) :: :ok
  defp process_entities(entity_type, entities, skip_notifications) do
    Enum.each(entities, fn entity ->
      maybe_send_notification(entity_type, entity, skip_notifications)
    end)
  end

  @spec maybe_send_notification(entity_type(), map(), boolean()) :: :ok
  defp maybe_send_notification(:characters, character, skip_notifications) do
    if skip_notifications do
      Logger.debug("Skipping character notification during initial load",
        character_id: character["eve_id"],
        category: :notifications
      )

      :ok
    else
      character_id = character["eve_id"]

      if character_id && Determiner.should_notify?(:character, character_id, character) do
        WandererNotifier.DiscordNotifier.send_character_async(character)
      end

      :ok
    end
  end

  defp maybe_send_notification(:systems, system, skip_notifications) do
    if skip_notifications do
      Logger.debug("Skipping system notification during initial load",
        system_id: system["solar_system_id"],
        category: :notifications
      )

      :ok
    else
      system_id = system["solar_system_id"]

      if system_id && Determiner.should_notify?(:system, system_id, system) do
        # Create System struct and enrich it before sending notification
        system_struct = System.from_api_data(system)

        # enrich_system always returns {:ok, system}, even on failure
        {:ok, enriched_system} = StaticInfo.enrich_system(system_struct)
        WandererNotifier.DiscordNotifier.send_system_async(enriched_system)
      end

      :ok
    end
  end
end
