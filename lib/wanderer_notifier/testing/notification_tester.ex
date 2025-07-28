defmodule WandererNotifier.Testing.NotificationTester do
  @moduledoc """
  Simple IEx helper module for testing notification formats.

  Usage in IEx:

      iex> alias WandererNotifier.Testing.NotificationTester, as: NT

      # Test character notification (with real character ID)
      iex> NT.test_character("123456789")

      # Test system notification (with real system ID)
      iex> NT.test_system("30000142")

      # Process killmail by ID as new notification
      iex> NT.test_killmail_id("123456789")

      # Test WandererKills service connectivity
      iex> NT.test_wanderer_kills_connection()

      # Override next kill classification
      iex> NT.set_kill_override(:character)
      iex> # Next real kill will be treated as character kill

      iex> NT.set_kill_override(:system)
      iex> # Next real kill will be treated as system kill
  """

  require Logger
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Killmail.{WandererKillsAPI, Pipeline}

  @kill_override_key "test:kill_override"

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notification Testing
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Test character notification by character ID.

  Looks up character data from cache and sends a test notification.
  """
  def test_character(character_id) when is_binary(character_id) do
    Logger.info("[TEST] Testing character notification for ID: #{character_id}")

    # Debug: check what cache keys exist
    debug_cache_keys()

    case Cache.get("map:character_list") do
      {:ok, character_list} when is_list(character_list) ->
        handle_character_list(character_list, character_id)

      {:ok, non_list_data} ->
        Logger.info(
          "[TEST] map:character_list exists but is not a list: #{inspect(non_list_data)}"
        )

        check_other_cache_locations(character_id)

      {:error, :not_found} ->
        Logger.info("[TEST] map:character_list not found in cache")
        check_other_cache_locations(character_id)
    end
  end

  def test_character(character_id) when is_integer(character_id) do
    test_character(Integer.to_string(character_id))
  end

  defp debug_cache_keys do
    # Try to get cache statistics or check common keys
    Logger.info("[TEST] Checking cache contents...")

    # Check a few common cache keys
    keys_to_check = [
      "map:character_list",
      "map:characters",
      "map:systems",
      "map:character_ids"
    ]

    Enum.each(keys_to_check, fn key ->
      case Cache.get(key) do
        {:ok, data} when is_list(data) ->
          Logger.info("[TEST] Cache key #{key}: list with #{length(data)} items")

        {:ok, data} ->
          Logger.info("[TEST] Cache key #{key}: #{inspect(data)}")

        {:error, :not_found} ->
          Logger.info("[TEST] Cache key #{key}: not found")
      end
    end)
  end

  defp handle_character_list(character_list, character_id) do
    Logger.info("[TEST] Found #{length(character_list)} characters in map:character_list")
    log_sample_character(character_list)

    character_id_int = String.to_integer(character_id)

    case find_character_in_list(character_list, character_id, character_id_int) do
      nil ->
        handle_character_not_found(character_list, character_id, character_id_int)

      character_data ->
        Logger.info("[TEST] Found character in map list: #{inspect(character_data)}")
        character = create_character_struct(character_data, character_id)
        send_character_notification(character)
    end
  end

  defp log_sample_character(character_list) do
    if length(character_list) > 0 do
      first_char = Enum.at(character_list, 0)
      Logger.info("[TEST] Sample character structure: #{inspect(first_char)}")
    end
  end

  defp find_character_in_list(character_list, character_id_str, character_id_int) do
    Enum.find(character_list, fn char ->
      character_matches?(char, character_id_str, character_id_int)
    end)
  end

  defp character_matches?(char, character_id_str, character_id_int) do
    # The eve_id is nested inside the "character" sub-map
    character_data = Map.get(char, "character", %{})
    eve_id = Map.get(character_data, "eve_id")

    # Also check the top-level character_id (which is a UUID)
    char_id = Map.get(char, "character_id") || Map.get(char, :character_id)

    eve_id == character_id_str ||
      eve_id == character_id_int ||
      char_id == character_id_str ||
      char_id == character_id_int ||
      to_string(eve_id) == character_id_str ||
      to_string(char_id) == character_id_str
  end

  defp handle_character_not_found(character_list, character_id, character_id_int) do
    Logger.info("[TEST] Character #{character_id} not found in map list")
    Logger.info("[TEST] Checking if character ID is in the list as integer...")

    all_eve_ids =
      Enum.map(character_list, fn char ->
        character_data = Map.get(char, "character", %{})
        Map.get(character_data, "eve_id")
      end)

    Logger.info("[TEST] All eve_ids in cache: #{inspect(Enum.take(all_eve_ids, 10))}...")

    if character_id_int in all_eve_ids do
      Logger.info("[TEST] Character ID #{character_id_int} IS in the list!")
    end

    if character_id in all_eve_ids do
      Logger.info("[TEST] Character ID #{character_id} IS in the list as string!")
    end

    check_other_cache_locations(character_id)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notification Testing
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Test system notification by system ID.

  Looks up system data from cache and sends a test notification.
  """
  def test_system(system_id) when is_binary(system_id) do
    Logger.info("[TEST] Testing system notification for ID: #{system_id}")

    case System.get_system(system_id) do
      {:ok, system} ->
        Logger.info("[TEST] Found system: #{system.name}")
        send_system_notification(system)

      {:error, :not_found} ->
        Logger.error("[TEST] System #{system_id} not found in cache")
        {:error, :not_found}
    end
  end

  def test_system(system_id) when is_integer(system_id) do
    test_system(Integer.to_string(system_id))
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Killmail ID Processing
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Process a killmail by ID through the full notification pipeline.

  Fetches the killmail data from WandererKills service and processes it
  as a new notification through the normal pipeline.
  """
  def test_killmail_id(killmail_id) when is_binary(killmail_id) do
    Logger.info("[TEST] Processing killmail ID: #{killmail_id}")

    with {:ok, killmail_data} <- fetch_killmail_data(killmail_id),
         {:ok, result} <- process_killmail(killmail_data) do
      Logger.info("[TEST] Killmail #{killmail_id} processed successfully: #{inspect(result)}")
      {:ok, result}
    else
      {:error, %{type: :not_found}} ->
        Logger.error("[TEST] Killmail #{killmail_id} not found in WandererKills service")
        {:error, :not_found}

      {:error, %{type: :http_error, message: message}} ->
        Logger.error("[TEST] HTTP error fetching killmail #{killmail_id}: #{message}")
        {:error, :http_error}

      {:error, %{type: :network_error, message: message}} ->
        Logger.error("[TEST] Network error fetching killmail #{killmail_id}: #{message}")
        {:error, :network_error}

      {:error, reason} ->
        Logger.error("[TEST] Failed to process killmail #{killmail_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def test_killmail_id(killmail_id) when is_integer(killmail_id) do
    test_killmail_id(Integer.to_string(killmail_id))
  end

  defp fetch_killmail_data(killmail_id) do
    Logger.info("[TEST] Fetching killmail data from WandererKills service")

    # Log the base URL being used
    base_url =
      WandererNotifier.Shared.Config.get(:wanderer_kills_url, "http://host.docker.internal:4004")

    full_url = "#{base_url}/api/v1/killmail/#{killmail_id}"
    Logger.info("[TEST] Request URL: #{full_url}")

    case WandererKillsAPI.get_killmail(killmail_id) do
      {:ok, killmail_data} ->
        Logger.info(
          "[TEST] Successfully fetched killmail data: #{inspect(Map.keys(killmail_data))}"
        )

        {:ok, killmail_data}

      {:error, %{type: :not_found} = error} ->
        Logger.info("[TEST] Killmail not found - this might be expected if the ID doesn't exist")
        Logger.info("[TEST] Try checking if the WandererKills service is running and accessible")
        {:error, error}

      {:error, %{type: :http_error, message: message} = error} ->
        Logger.error("[TEST] HTTP error: #{message}")
        Logger.info("[TEST] Check if WandererKills service is running at: #{base_url}")
        {:error, error}

      {:error, %{type: :network_error, message: message} = error} ->
        Logger.error("[TEST] Network error: #{message}")
        Logger.info("[TEST] Check network connectivity to: #{base_url}")
        {:error, error}

      {:error, other_error} ->
        Logger.error("[TEST] Unexpected error: #{inspect(other_error)}")
        {:error, other_error}
    end
  end

  defp process_killmail(killmail_data) do
    Logger.info("[TEST] Processing killmail through pipeline")
    Pipeline.process_killmail(killmail_data)
  end

  @doc """
  Test connectivity to the WandererKills service.

  Useful for debugging connection issues before testing killmail IDs.
  """
  def test_wanderer_kills_connection do
    Logger.info("[TEST] Testing WandererKills service connectivity")

    base_url =
      WandererNotifier.Shared.Config.get(:wanderer_kills_url, "http://host.docker.internal:4004")

    Logger.info("[TEST] WandererKills base URL: #{base_url}")

    case WandererKillsAPI.health_check() do
      {:ok, health_data} ->
        Logger.info("[TEST] WandererKills service is healthy: #{inspect(health_data)}")
        {:ok, :healthy}

      {:error, reason} ->
        Logger.error("[TEST] WandererKills service health check failed: #{inspect(reason)}")
        Logger.info("[TEST] Make sure the WandererKills service is running at: #{base_url}")
        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Kill Classification Override
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Set kill classification override for the next kill.

  Options:
  - :character - Next kill will be treated as character kill
  - :system - Next kill will be treated as system kill
  - :clear - Remove override
  """
  def set_kill_override(:character) do
    Cache.put(@kill_override_key, :character, :timer.minutes(10))
    Logger.info("[TEST] Kill override set to :character (expires in 10 minutes)")
    :ok
  end

  def set_kill_override(:system) do
    Cache.put(@kill_override_key, :system, :timer.minutes(10))
    Logger.info("[TEST] Kill override set to :system (expires in 10 minutes)")
    :ok
  end

  def set_kill_override(:clear) do
    Cache.delete(@kill_override_key)
    Logger.info("[TEST] Kill override cleared")
    :ok
  end

  @doc """
  Check current kill override setting.
  """
  def get_kill_override do
    case Cache.get(@kill_override_key) do
      {:ok, override} ->
        Logger.info("[TEST] Current kill override: #{override}")
        {:ok, override}

      {:error, :not_found} ->
        Logger.info("[TEST] No kill override set")
        {:ok, nil}
    end
  end

  @doc """
  Get the override for kill classification (called by the system).
  """
  def check_kill_override do
    case Cache.get(@kill_override_key) do
      {:ok, override} ->
        # Clear after use
        Cache.delete(@kill_override_key)
        Logger.info("[TEST] Using kill override: #{override}")
        {:ok, override}

      {:error, :not_found} ->
        {:ok, nil}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════════

  defp check_other_cache_locations(character_id) do
    # Try as integer with get_character
    character_id_int = String.to_integer(character_id)

    case Cache.get_character(character_id_int) do
      {:ok, character_data} ->
        Logger.info("[TEST] Found character in ESI cache: #{inspect(character_data)}")
        character = create_character_struct(character_data, character_id)
        send_character_notification(character)

      {:error, :not_found} ->
        # Try direct string key
        case Cache.get("esi:character:#{character_id}") do
          {:ok, character_data} ->
            Logger.info("[TEST] Found character with string key: #{inspect(character_data)}")
            character = create_character_struct(character_data, character_id)
            send_character_notification(character)

          {:error, :not_found} ->
            Logger.error("[TEST] Character #{character_id} not found in any cache location")

            Logger.info(
              "[TEST] Tried: map:character_list, esi:character:#{character_id_int}, esi:character:#{character_id}"
            )

            {:error, :not_found}
        end
    end
  end

  defp create_character_struct(character_data, character_id) do
    # Handle nested structure from map:character_list
    char_info = Map.get(character_data, "character", character_data)
    _character_id_int = String.to_integer(character_id)

    %Character{
      character_id: character_id,
      name: get_name(char_info),
      corporation_id: get_corp_id(char_info),
      alliance_id: get_alliance_id(char_info),
      eve_id: character_id,
      corporation_ticker: Map.get(char_info, "corporation_ticker"),
      alliance_ticker: Map.get(char_info, "alliance_ticker"),
      tracked: true
    }
  end

  defp get_name(data) do
    Map.get(data, "name") || Map.get(data, :name) || "Unknown"
  end

  defp get_corp_id(data) do
    Map.get(data, "corporation_id") || Map.get(data, :corporation_id)
  end

  defp get_alliance_id(data) do
    Map.get(data, "alliance_id") || Map.get(data, :alliance_id)
  end

  defp send_character_notification(character) do
    try do
      DiscordNotifier.send_new_tracked_character_notification(character)
    rescue
      e ->
        Logger.error("[TEST] Exception sending character notification: #{inspect(e)}")
        {:error, e}
    end
  end

  defp send_system_notification(system) do
    try do
      DiscordNotifier.send_new_system_notification(system)
    rescue
      e ->
        Logger.error("[TEST] Exception sending system notification: #{inspect(e)}")
        {:error, e}
    end
  end
end
