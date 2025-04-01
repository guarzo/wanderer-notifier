defmodule WandererNotifier.Data.Cache.Monitor do
  @moduledoc """
  GenServer implementation for monitoring cache health and status.
  Provides functionality for tracking cache operations and health metrics.
  """
  use GenServer
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.TrackedCharacter

  # Check interval - 15 minutes by default
  @check_interval 15 * 60 * 1000

  # Start the GenServer
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    # Schedule initial check after 5 minutes to allow system to start up
    schedule_check(5 * 60 * 1000)

    # Return initial state
    {:ok,
     %{
       last_check: nil,
       check_count: 0,
       last_results: nil
     }}
  end

  @impl true
  def handle_info(:check_cache_health, state) do
    # Run cache health check
    results = run_cache_health_check()

    # Update state with new check time and results
    new_state = %{
      last_check: DateTime.utc_now(),
      check_count: state.check_count + 1,
      last_results: results
    }

    # Schedule next check
    schedule_check()

    # Return updated state
    {:noreply, new_state}
  end

  # Run the health check
  defp run_cache_health_check do
    AppLogger.cache_info("[CacheMonitor] Running cache health check")

    # Initialize results map
    results = %{
      character_count_inconsistency: false,
      missing_characters: [],
      different_characters: [],
      fixed_issues: 0
    }

    # Check tracked characters
    results = check_tracked_characters(results)

    # Log results
    log_health_check_results(results)

    # Return the results
    results
  rescue
    e ->
      AppLogger.cache_error(
        "[CacheMonitor] Error during cache health check: #{Exception.message(e)}"
      )

      AppLogger.cache_debug("[CacheMonitor] #{Exception.format_stacktrace()}")
      %{error: e}
  end

  # Log the results of the health check
  defp log_health_check_results(results) do
    if results.character_count_inconsistency || length(results.missing_characters) > 0 ||
         length(results.different_characters) > 0 do
      AppLogger.cache_warn("""
      [CacheMonitor] Cache inconsistencies detected:
        - Character count inconsistency: #{results.character_count_inconsistency}
        - Missing characters: #{length(results.missing_characters)}
        - Different characters: #{length(results.different_characters)}
        - Fixed issues: #{results.fixed_issues}
      """)
    else
      AppLogger.cache_info(
        "[CacheMonitor] Cache health check completed - no inconsistencies found"
      )
    end
  end

  # Check for inconsistencies in tracked characters between cache and database
  defp check_tracked_characters(results) do
    # Get the cached characters
    cached_characters = CacheRepo.get("map:characters") || []

    # Check if database operations are enabled
    if TrackedCharacter.database_enabled?() do
      # Get the characters from database
      case TrackedCharacter.read_safely() do
        {:ok, db_characters} ->
          process_character_comparison(results, cached_characters, db_characters)

        {:error, reason} ->
          AppLogger.cache_error(
            "[CacheMonitor] Error retrieving characters from database: #{inspect(reason)}"
          )

          results
      end
    else
      # Database operations are disabled, log and return unchanged results
      AppLogger.cache_info(
        "[CacheMonitor] Skipping database character check - database operations disabled"
      )

      results
    end
  end

  # Process comparison between cached characters and database characters
  defp process_character_comparison(results, cached_characters, db_characters) do
    # Check if counts match
    count_inconsistent = length(cached_characters) != length(db_characters)

    if count_inconsistent do
      AppLogger.cache_warn("""
        [CacheMonitor] Character count mismatch:
        - Cache: #{length(cached_characters)}
        - Database: #{length(db_characters)}
      """)
    end

    # Compare characters between cache and database
    {missing, different} = compare_characters(cached_characters, db_characters)

    # If inconsistencies found, fix them
    fixed_count =
      fix_character_inconsistencies(count_inconsistent, missing, different, db_characters)

    # Update results
    %{
      results
      | character_count_inconsistency: count_inconsistent,
        missing_characters: missing,
        different_characters: different,
        fixed_issues: results.fixed_issues + fixed_count
    }
  end

  # Fix character inconsistencies if needed
  defp fix_character_inconsistencies(count_inconsistent, missing, different, db_characters) do
    if count_inconsistent || length(missing) > 0 || length(different) > 0 do
      # Resync the cache from database
      resync_characters_cache(db_characters)

      # Count fixed issues
      if(count_inconsistent, do: 1, else: 0) + length(missing) + length(different)
    else
      0
    end
  end

  # Compare characters between cache and database
  defp compare_characters(cached_characters, db_characters) do
    # Create maps for faster lookup
    cached_map =
      Map.new(cached_characters, fn char ->
        {to_string(char["character_id"] || char.character_id), char}
      end)

    db_map =
      Map.new(db_characters, fn char ->
        {to_string(char.character_id), char}
      end)

    # Find characters in database but not in cache
    missing_in_cache =
      db_map
      |> Map.keys()
      |> Enum.filter(fn char_id -> not Map.has_key?(cached_map, char_id) end)

    # Find characters with different data
    different_data =
      db_map
      |> Map.keys()
      |> Enum.filter(fn char_id ->
        # Only check characters that exist in both maps
        if Map.has_key?(cached_map, char_id) do
          cached_char = cached_map[char_id]
          db_char = db_map[char_id]

          # Check for mismatches in important fields
          cached_name = cached_char["name"] || cached_char.name
          db_char.character_name != cached_name
        else
          false
        end
      end)

    # Log any inconsistencies
    if length(missing_in_cache) > 0 do
      AppLogger.cache_warn(
        "[CacheMonitor] Found #{length(missing_in_cache)} characters in database but missing from cache"
      )
    end

    if length(different_data) > 0 do
      AppLogger.cache_warn(
        "[CacheMonitor] Found #{length(different_data)} characters with data mismatches between cache and database"
      )
    end

    {missing_in_cache, different_data}
  end

  # Resync characters cache from database
  defp resync_characters_cache(db_characters) do
    AppLogger.cache_info(
      "[CacheMonitor] Resyncing characters cache from database (#{length(db_characters)} characters)"
    )

    # Convert database characters to cache format
    cache_characters =
      Enum.map(db_characters, fn char ->
        %{
          "character_id" => to_string(char.character_id),
          "name" => char.character_name,
          "corporation_id" => char.corporation_id,
          "corporation_ticker" => char.corporation_name,
          "alliance_id" => char.alliance_id,
          "alliance_ticker" => char.alliance_name,
          "tracked" => true
        }
      end)

    # Update the cache
    CacheRepo.update_after_db_write(
      "map:characters",
      cache_characters,
      Timings.characters_cache_ttl()
    )

    # Also update individual character entries
    Enum.each(cache_characters, fn char ->
      character_id = char["character_id"]

      CacheRepo.update_after_db_write(
        "map:character:#{character_id}",
        char,
        Timings.characters_cache_ttl()
      )

      # Ensure it's marked as tracked
      CacheRepo.update_after_db_write(
        "tracked:character:#{character_id}",
        true,
        Timings.characters_cache_ttl()
      )
    end)

    AppLogger.cache_info("[CacheMonitor] Characters cache successfully resynced from database")
  end

  # Schedule next check with default interval
  defp schedule_check do
    schedule_check(@check_interval)
  end

  # Schedule check with specific interval
  defp schedule_check(interval) do
    Process.send_after(self(), :check_cache_health, interval)
  end
end
