defmodule WandererNotifier.Workers.CharacterSyncWorker do
  @moduledoc """
  GenServer that periodically validates character data consistency between cache and database.

  This worker has been refactored to focus on validation rather than being the primary sync mechanism.
  The primary sync now happens immediately when characters are received from the Map API.
  This worker serves as a fallback and validation mechanism to ensure consistency.
  """
  use GenServer
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Repository
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.TrackedCharacter

  # Change from 15 minutes to 1 hour for validation checks
  @sync_interval 60 * 60 * 1000

  # Start the GenServer
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    # Schedule first validation check after 10 minutes
    # This gives the system time to perform direct syncs first
    schedule_sync(10 * 60 * 1000)

    # Return initial state
    {:ok, %{last_sync: nil, sync_count: 0}}
  end

  @impl true
  def handle_info(:sync, state) do
    # Perform the validation
    result = run_validation()

    # Update state with new sync time and result
    new_state = %{
      last_sync: DateTime.utc_now(),
      sync_count: state.sync_count + 1,
      last_result: result
    }

    # Schedule next validation
    schedule_sync()

    # Return updated state
    {:noreply, new_state}
  end

  # Run the character validation
  defp run_validation do
    AppLogger.scheduler_info("Running periodic character consistency validation")

    # Check if kill charts feature is enabled first
    if should_generate_charts?() do
      validate_characters_if_available()
    else
      AppLogger.scheduler_info("Kill charts feature is disabled", action: "skipping_validation")
      {:ok, :disabled_feature}
    end
  rescue
    e ->
      AppLogger.scheduler_error("Error during validation",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace()
      )

      {:error, e}
  end

  # Validate characters if they are available in cache
  defp validate_characters_if_available do
    # Get character counts
    cached_characters = Repository.get("map:characters") || []

    # Only run if we have characters in the cache
    if length(cached_characters) > 0 do
      AppLogger.scheduler_info(
        "Validating consistency of characters between cache and database",
        character_count: length(cached_characters)
      )

      perform_character_validation(cached_characters)
    else
      AppLogger.scheduler_info("No characters in cache", action: "skipping_validation")
      {:ok, :no_characters}
    end
  end

  # Perform actual validation on characters
  defp perform_character_validation(cached_characters) do
    case validate_character_consistency(cached_characters) do
      {:ok, %{missing: 0, different: 0}} ->
        AppLogger.scheduler_info("Cache and database are consistent")
        {:ok, :consistent}

      {:ok, %{missing: missing, different: different}} ->
        handle_inconsistencies(cached_characters, missing, different)

      {:error, reason} ->
        AppLogger.scheduler_error("Validation failed", error: inspect(reason))
        {:error, reason}
    end
  end

  # Handle inconsistencies between cache and database
  defp handle_inconsistencies(cached_characters, missing, different) do
    if missing > 0 || different > 0 do
      AppLogger.scheduler_warn("Inconsistencies found", missing: missing, different: different)

      # Only attempt to sync if database operations are enabled
      if TrackedCharacter.database_enabled?() do
        # Run sync to fix inconsistencies
        sync_result = TrackedCharacter.sync_from_characters(cached_characters)

        AppLogger.scheduler_info("Auto-fixed inconsistencies", result: inspect(sync_result))
        {:ok, %{inconsistent: true, sync_result: sync_result}}
      else
        AppLogger.scheduler_info("Inconsistencies found but database operations are disabled")
        {:ok, %{inconsistent: true, sync_skipped: true}}
      end
    else
      AppLogger.scheduler_info("Cache and database are consistent")
      {:ok, :consistent}
    end
  end

  # Perform consistency validation between cache and database
  defp validate_character_consistency(cached_characters) do
    # Get all tracked characters from database
    case TrackedCharacter.list_all() do
      {:ok, db_characters} ->
        # Compare cache and database
        comparison_result = compare_characters(cached_characters, db_characters)
        {:ok, comparison_result}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      AppLogger.scheduler_error("Error fetching database characters",
        error: Exception.message(e)
      )

      {:error, e}
  end

  # Compare characters in cache and database
  defp compare_characters(cached_characters, db_characters) do
    # Create maps for faster lookup
    cached_map = Map.new(cached_characters, fn char -> {to_string(char.character_id), char} end)
    db_map = Map.new(db_characters, fn char -> {to_string(char.character_id), char} end)

    # Find characters in cache but not in database
    missing_in_db =
      cached_map
      |> Map.keys()
      |> Enum.filter(fn char_id -> not Map.has_key?(db_map, char_id) end)
      |> length()

    # Find characters with different data
    different_data =
      cached_map
      |> Map.keys()
      |> Enum.filter(fn char_id ->
        # Only check characters that exist in both maps
        if Map.has_key?(db_map, char_id) do
          cached_char = cached_map[char_id]
          db_char = db_map[char_id]

          # Compare important fields
          cached_char.name != db_char.character_name ||
            (extract_corp_id(cached_char) != db_char.corporation_id &&
               not is_nil(extract_corp_id(cached_char)))
        else
          false
        end
      end)
      |> length()

    # Return comparison stats
    %{
      cached_count: map_size(cached_map),
      db_count: map_size(db_map),
      missing: missing_in_db,
      different: different_data
    }
  end

  # Helper to extract corporation ID from character struct
  defp extract_corp_id(character) do
    cond do
      is_map_key(character, :corporation_id) -> character.corporation_id
      is_map_key(character, "corporation_id") -> character["corporation_id"]
      true -> nil
    end
  end

  # Check if kill charts feature is enabled
  defp should_generate_charts? do
    Features.kill_charts_enabled?()
  end

  # Schedule next sync with default interval
  defp schedule_sync do
    schedule_sync(@sync_interval)
  end

  # Schedule sync with specific interval
  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end
end
