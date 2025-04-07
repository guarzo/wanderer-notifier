defmodule WandererNotifier.Schedulers.WeeklyKillHighlightsScheduler do
  @moduledoc """
  Scheduler for sending weekly kill highlights to Discord.
  Sends the best kill and worst loss from the past week for tracked characters.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  alias WandererNotifier.Api.ESI.Service, as: EsiService
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  require Ash.Query, as: Query

  # EVE Online type IDs
  # Structure category
  @structure_category_id 65
  # Deployable category
  @deployable_category_id 22
  # Capsule (pod) type ID
  @pod_type_id 670

  # Known structure group IDs (partial list of important ones)
  @structure_group_ids [
    # Citadels and other upwell structures
    # Citadels (Astrahus, Fortizar, Keepstar)
    1657,
    # Engineering Complexes (Raitaru, Azbel, Sotiyo)
    1404,
    # Refineries (Athanor, Tatara)
    1406,
    # Other structure types
    # Starbases (POS)
    365,
    # Starbase Control Towers
    297,
    # Infrastructure Hubs (iHubs)
    1025,
    # FLEX Structures
    1876,
    # Engineering Complexes (Legacy)
    1677,
    # Observatories
    1927,
    # Forward Operating Bases
    1980
  ]

  # Known deployable group IDs
  @deployable_group_ids [
    # Mobile Depots
    361,
    # Mobile Tractor Units
    363,
    # Mobile Siphon Units
    715,
    # Mobile Scan Inhibitors
    1022,
    # Ship Maintenance Arrays
    1247,
    # Corporate Hangar Arrays
    1249,
    # Mobile Cyno Inhibitors
    1246,
    # Mobile Missile Sentry
    1248,
    # Mobile Warp Disruptors
    1201,
    # Mobile Micro Jump Units
    1297,
    # Mobile Service Units
    1275
  ]

  # Cached structure type IDs to avoid redundant API calls
  @structure_types_cache_key :structure_types_cache

  @impl true
  def enabled? do
    Features.kill_charts_enabled?()
  end

  @impl true
  def execute(state) do
    if enabled?() do
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Sending weekly kill highlights to Discord"
      )

      # Get the Discord channel ID for kill highlights
      channel_id = NotificationConfig.discord_channel_id_for(:kill_charts)

      case process_weekly_highlights(channel_id) do
        {:ok, _} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Successfully sent kill highlights")
          {:ok, :completed, state}

        {:error, reason} ->
          AppLogger.scheduler_error("#{inspect(__MODULE__)}: Failed to send kill highlights",
            error: inspect(reason)
          )

          {:error, reason, state}
      end
    else
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Skipping weekly kill highlights (disabled)"
      )

      {:ok, :skipped, Map.put(state, :reason, :scheduler_disabled)}
    end
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.weekly_kill_data_fetch_interval(),
      description: "Weekly kill highlights Discord sending"
    }
  end

  def send_test_highlights do
    AppLogger.scheduler_info("Sending test weekly kill highlights")

    # Get channel ID from config
    channel_id = config().discord_channel_id_for(:kill_charts)

    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for test kill charts")
      {:error, "No channel ID configured"}
    else
      # Calculate date range for the past week
      now = DateTime.utc_now()
      # Use 7 days for testing
      days_ago = DateTime.add(now, -7 * 86_400, :second)

      # Log the query date range
      AppLogger.scheduler_info(
        "Test kill highlights using date range: #{DateTime.to_string(days_ago)} to #{DateTime.to_string(now)}"
      )

      # Log total kills and losses in database for test diagnostics
      # Use simple queries with time filter instead of fixed limit
      all_kills_query =
        Killmail
        |> Query.filter(character_role == :attacker)
        |> Query.filter(kill_time >= ^days_ago)
        |> Query.filter(kill_time <= ^now)

      all_losses_query =
        Killmail
        |> Query.filter(character_role == :victim)
        |> Query.filter(kill_time >= ^days_ago)
        |> Query.filter(kill_time <= ^now)

      # Check total database counts for diagnostics
      all_kills_result = Api.read(all_kills_query)
      all_losses_result = Api.read(all_losses_query)

      case {all_kills_result, all_losses_result} do
        {{:ok, kills}, {:ok, losses}} ->
          kills_count = length(kills)
          losses_count = length(losses)

          AppLogger.scheduler_info(
            "Database diagnostics: Kills in last 7 days: #{kills_count}, Losses in last 7 days: #{losses_count}"
          )

        _ ->
          AppLogger.scheduler_error("Unable to count kills and losses in database")
      end

      # Run the regular weekly highlights processing with standard date range
      try do
        case process_weekly_highlights_with_date_range(channel_id, days_ago, now) do
          {:ok, _} = result ->
            AppLogger.scheduler_info("Successfully sent test kill highlights")
            result

          {:error, reason} = error ->
            AppLogger.scheduler_error("Failed to send test kill charts: #{inspect(reason)}")
            error
        end
      rescue
        e ->
          AppLogger.scheduler_error("Exception sending test kill charts: #{Exception.message(e)}")

          {:error, "Exception: #{Exception.message(e)}"}
      end
    end
  end

  # Process the weekly kill highlights for a specific date range
  defp process_weekly_highlights_with_date_range(channel_id, start_date, end_date) do
    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for kill charts")
      {:error, "No channel ID configured"}
    else
      # Format date range for display
      start_str = Calendar.strftime(start_date, "%Y-%m-%d")
      end_str = Calendar.strftime(end_date, "%Y-%m-%d")
      date_range = "#{start_str} to #{end_str}"

      AppLogger.scheduler_info("Processing kill highlights for period: #{date_range}")
      # Get best kill - process independently
      best_kill_result = find_best_kill(start_date, end_date)

      kills_sent =
        case best_kill_result do
          {:ok, kill} ->
            AppLogger.scheduler_info("Sending best kill notification")
            # Format the Discord embed with the killmail data
            kill_embed = format_kill_embed(kill, true, date_range)
            NotifierFactory.notify(:send_discord_embed_to_channel, [channel_id, kill_embed])
            1

          {:error, reason} ->
            AppLogger.scheduler_warn("Unable to send best kill notification: #{inspect(reason)}")
            0
        end

      # Get worst loss - process independently
      worst_loss_result = find_worst_loss(start_date, end_date)

      losses_sent =
        case worst_loss_result do
          {:ok, loss} ->
            AppLogger.scheduler_info("Sending worst loss notification")
            # Format the Discord embed with the killmail data
            loss_embed = format_kill_embed(loss, false, date_range)
            NotifierFactory.notify(:send_discord_embed_to_channel, [channel_id, loss_embed])
            1

          {:error, reason} ->
            AppLogger.scheduler_warn("Unable to send worst loss notification: #{inspect(reason)}")

            0
        end

      total_sent = kills_sent + losses_sent

      # Return overall result
      if total_sent > 0 do
        # At least one notification was sent
        AppLogger.scheduler_info("Successfully sent #{total_sent} kill highlight notifications")
        {:ok, :sent}
      else
        # Nothing was sent
        AppLogger.scheduler_error("Failed to send any kill highlights")
        {:error, :no_kills}
      end
    end
  rescue
    e ->
      AppLogger.scheduler_error("Error processing kill highlights",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Exception: #{Exception.message(e)}"}
  end

  # Process the weekly kill highlights
  defp process_weekly_highlights(channel_id) do
    # Calculate date range for the past week
    now = DateTime.utc_now()
    week_ago = DateTime.add(now, -7 * 86_400, :second)

    # Use the generic function with the weekly date range
    process_weekly_highlights_with_date_range(channel_id, week_ago, now)
  end

  # Find the best kill (highest value) in the given period
  defp find_best_kill(start_date, end_date) do
    find_significant_killmail(start_date, end_date, :attacker, "best kill")
  end

  # Find the worst loss (highest value) in the given period
  defp find_worst_loss(start_date, end_date) do
    find_significant_killmail(start_date, end_date, :victim, "worst loss")
  end

  # Shared implementation for finding best kill or worst loss
  defp find_significant_killmail(start_date, end_date, character_role, description) do
    # Log query parameters
    AppLogger.scheduler_info(
      "Searching for #{description} between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    # Get tracked character IDs from our tracking system
    all_tracked_character_ids = get_tracked_character_ids()

    AppLogger.scheduler_info(
      "Retrieved #{length(all_tracked_character_ids)} tracked character IDs"
    )

    if all_tracked_character_ids == [] do
      AppLogger.scheduler_warn("No tracked characters found, cannot search for #{description}")
      {:error, character_role == :attacker && :no_tracked_characters || :no_tracked_characters}
    else
      # Query for all killmails in the date range
      query_result = query_killmails_for_period(start_date, end_date, character_role)

      case query_result do
        {:ok, []} ->
          AppLogger.scheduler_warn("No #{character_role}s found in the date range")
          error_reason = character_role == :attacker && :no_kills_in_range || :no_losses_in_range
          {:error, error_reason}

        {:ok, killmails} ->
          # Log all the found killmails for debugging
          killmails_count = length(killmails)
          AppLogger.scheduler_info("Found #{killmails_count} total #{character_role}s in date range")

          # Filter to tracked characters and exclude structures/deployables
          filtered_killmails =
            filter_tracked_killmails(killmails, all_tracked_character_ids, character_role)

          # Group by killmail_id to handle multiple tracked characters in same killmail
          deduplicated_killmails =
            deduplicate_killmails(filtered_killmails, character_role)

          # Log how many killmails remain after filtering and deduplication
          deduped_count = length(deduplicated_killmails)
          role_term = character_role == :attacker && "attackers" || "victims"

          AppLogger.scheduler_info(
            "Found #{deduped_count} unique #{character_role}s with tracked #{role_term} after filtering"
          )

          # Filter for killmails with value
          valued_killmails =
            Enum.filter(deduplicated_killmails, fn kill -> kill.total_value != nil end)

          if valued_killmails != [] do
            # Get the killmail with the highest value
            best_killmail = find_highest_value_killmail(valued_killmails)

            # Log the complete killmail struct for debugging
            AppLogger.scheduler_debug(
              "FULL #{String.upcase(description)} KILLMAIL STRUCT: #{inspect(best_killmail, pretty: true, limit: :infinity)}"
            )

            # Enrich missing data if necessary
            best_killmail = enrich_killmail_data(best_killmail)

            # Log selected killmail details for debugging
            log_selected_killmail(best_killmail, description)

            {:ok, best_killmail}
          else
            AppLogger.scheduler_warn("No #{character_role}s with valid values found")
            error_reason = character_role == :attacker && :no_kills_with_value || :no_losses_with_value
            {:error, error_reason}
          end

        error ->
          AppLogger.scheduler_error("Error querying #{character_role}s in date range: #{inspect(error)}")
          {:error, "Failed to find #{character_role}s in date range"}
      end
    end
  end

  # Create a query for killmails in a specific period
  defp query_killmails_for_period(start_date, end_date, character_role) do
    # Only search for killmails where the character is actually tracked
    date_query =
      Killmail
      |> Query.filter(character_role == ^character_role)
      |> Query.filter(kill_time >= ^start_date)
      |> Query.filter(kill_time <= ^end_date)
      |> Query.filter(ship_type_id != ^@pod_type_id)
      |> Query.sort(total_value: :desc)
      |> Query.limit(100)

    Api.read(date_query)
  end

  # Filter killmails to keep only those with tracked characters and non-structure ships
  defp filter_tracked_killmails(killmails, tracked_character_ids, character_role) do
    Enum.filter(killmails, fn killmail ->
      # Convert the related_character_id to integer to match our list
      character_id = killmail.related_character_id

      character_id_int =
        if is_binary(character_id),
          do: String.to_integer(character_id),
          else: character_id

      # Character is tracked if their ID is in our tracked IDs list
      is_tracked = Enum.member?(tracked_character_ids, character_id_int)

      # Log which characters aren't tracked for debugging
      unless is_tracked do
        AppLogger.scheduler_debug(
          "Character #{character_id} is not tracked - ignoring #{character_role} #{killmail.killmail_id}"
        )
      end

      # Get appropriate ship type ID based on character role
      ship_type_id =
        if character_role == :victim do
          killmail.ship_type_id
        else
          # For attacker, check victim's ship from victim_data
          case killmail.victim_data do
            data when is_map(data) -> Map.get(data, "ship_type_id")
            _ -> nil
          end
        end

      # Check if the ship is a structure or deployable
      is_structure_or_deployable =
        ship_type_id && structure_or_deployable?(ship_type_id)

      if is_structure_or_deployable do
        role_term = character_role == :victim && "Lost" || "Victim"
        AppLogger.scheduler_debug(
          "#{role_term} ship is a structure or deployable - ignoring #{character_role} #{killmail.killmail_id}"
        )
      end

      # Include killmail only if character is tracked and ship is not a structure or deployable
      is_tracked && !is_structure_or_deployable
    end)
  end

  # Deduplicate killmails by selecting best character for each killmail ID
  defp deduplicate_killmails(killmails, character_role) do
    # Group by killmail_id
    grouped_killmails = Enum.group_by(killmails, fn kill -> kill.killmail_id end)

    # Select best character for each killmail
    Enum.map(grouped_killmails, fn {_killmail_id, kills_for_id} ->
      if length(kills_for_id) > 1 do
        # Multiple tracked characters were involved
        AppLogger.scheduler_info(
          "Multiple tracked characters involved in killmail #{List.first(kills_for_id).killmail_id}"
        )

        if character_role == :attacker do
          # For kills, select the one with highest damage
          best_character_kill =
            Enum.max_by(kills_for_id, fn kill -> get_attacker_damage(kill) end)

          AppLogger.scheduler_info(
            "Selected character #{best_character_kill.related_character_id} with highest damage"
          )

          best_character_kill
        else
          # For losses, we just take the first one
          AppLogger.scheduler_info(
            "Multiple tracked victims in the same killmail (unusual). Taking first one."
          )
          List.first(kills_for_id)
        end
      else
        # Only one tracked character was involved
        List.first(kills_for_id)
      end
    end)
    |> Enum.filter(fn kill -> not is_nil(kill) end)
  end

  # Extract attacker damage from killmail
  defp get_attacker_damage(kill) do
    # Get damage done by this character
    attacker_damage =
      cond do
        is_nil(kill.attacker_data) ->
          0

        is_map(kill.attacker_data) && !is_struct(kill.attacker_data) ->
          Map.get(kill.attacker_data, "damage_done") || 0

        is_struct(kill.attacker_data) &&
            Map.has_key?(kill.attacker_data, :damage_done) ->
          Map.get(kill.attacker_data, :damage_done) || 0

        true ->
          0
      end

    # Convert to integer
    case attacker_damage do
      damage when is_integer(damage) ->
        damage

      damage when is_binary(damage) ->
        case Integer.parse(damage) do
          {int_damage, _} -> int_damage
          _ -> 0
        end

      _ ->
        0
    end
  end

  # Find the killmail with the highest value
  defp find_highest_value_killmail(killmails) do
    Enum.max_by(
      killmails,
      fn kill ->
        case kill.total_value do
          nil -> Decimal.new(0)
          val when is_struct(val, Decimal) -> val
          _ -> Decimal.new(0)
        end
      end
    )
  end

  # Log details of the selected killmail
  defp log_selected_killmail(killmail, description) do
    AppLogger.scheduler_info(
      "Selected #{description}: ID=#{killmail.killmail_id}, " <>
        "Character=#{killmail.related_character_name || "Unknown"}, " <>
        "Ship=#{killmail.ship_type_name || "Unknown"}, " <>
        "System=#{killmail.solar_system_name || "Unknown"}, " <>
        "Region=#{killmail.region_name || "Unknown"}, " <>
        "Value=#{inspect(killmail.total_value)}, " <>
        "Time=#{DateTime.to_string(killmail.kill_time)}"
    )
  end

  # Get list of tracked character IDs for filtering
  defp get_tracked_character_ids do
    # First try getting characters from repository cache
    tracked_characters = DataRepo.get_tracked_characters()

    # Log the raw data for debugging
    AppLogger.scheduler_info(
      "Retrieved #{length(tracked_characters)} tracked characters from repository cache"
    )

    if tracked_characters != [] do
      # Log a sample character for format inspection
      sample = List.first(tracked_characters)
      AppLogger.scheduler_info("Sample character format: #{inspect(sample)}")

      # Extract character IDs, handling different formats
      character_ids = extract_character_ids_from_maps(tracked_characters)

      # Log the extracted IDs
      AppLogger.scheduler_info(
        "Extracted #{length(character_ids)} valid character IDs from cache"
      )

      character_ids
    else
      # If cache returned empty list, fallback to database query
      AppLogger.scheduler_info(
        "Cache returned no tracked characters, falling back to database query"
      )

      # Query directly from the tracked_characters table
      case query_tracked_characters_from_database() do
        {:ok, ids} when ids != [] ->
          AppLogger.scheduler_info("Found #{length(ids)} tracked characters in database")
          ids

        _ ->
          AppLogger.scheduler_warn("No tracked characters found in database either")
          []
      end
    end
  end

  # Extract character IDs from list of character maps
  defp extract_character_ids_from_maps(characters) do
    Enum.map(characters, fn char ->
      # Try different ways to extract character_id
      character_id =
        cond do
          # String map access
          is_map(char) && Map.has_key?(char, "character_id") ->
            Map.get(char, "character_id")

          # Atom map access
          is_map(char) && Map.has_key?(char, :character_id) ->
            Map.get(char, :character_id)

          # Character is directly an ID
          is_binary(char) || is_integer(char) ->
            char

          true ->
            nil
        end

      # Convert to integer if possible
      case character_id do
        id when is_integer(id) ->
          id

        id when is_binary(id) ->
          case Integer.parse(id) do
            {int_id, _} -> int_id
            :error -> nil
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Query tracked characters directly from database
  defp query_tracked_characters_from_database do
    # Create query to get all character_ids from tracked_characters table
    require Ash.Query

    # Log that we're attempting direct database query
    AppLogger.scheduler_info("Querying tracked_characters table directly")

    # Use the TrackedCharacter resource to query the database
    character_query =
      WandererNotifier.Resources.TrackedCharacter
      |> Ash.Query.select([:character_id])

    # Execute the query and extract character IDs
    case WandererNotifier.Resources.Api.read(character_query) do
      {:ok, results} ->
        # Extract character_id from each result
        character_ids =
          Enum.map(results, fn char ->
            # Get the character_id value (could be integer or string)
            id = Map.get(char, :character_id)

            # Ensure it's an integer
            case id do
              id when is_integer(id) ->
                id

              id when is_binary(id) ->
                {parsed, _} = Integer.parse(id)
                parsed

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        AppLogger.scheduler_info(
          "Successfully found #{length(character_ids)} character IDs in database"
        )

        {:ok, character_ids}

      error ->
        AppLogger.scheduler_error("Error querying tracked_characters table: #{inspect(error)}")
        {:error, "Failed to query tracked characters from database"}
    end
  end

  # Enrich killmail with missing system and region data
  defp enrich_killmail_data(killmail) do
    # Log the current values
    AppLogger.scheduler_info(
      "Enriching killmail: ID=#{killmail.killmail_id}, " <>
        "Character=#{killmail.related_character_name || "Unknown"}, " <>
        "Ship=#{killmail.ship_type_name || "Unknown"}, " <>
        "System=#{killmail.solar_system_name || "Unknown"}, " <>
        "System ID=#{killmail.solar_system_id || "nil"}"
    )

    # Try to get character name if it's missing or is "Unknown Character"
    killmail =
      if is_nil(killmail.related_character_name) ||
           String.starts_with?(to_string(killmail.related_character_name), "Unknown Character") do
        # If we have a character ID, look it up in ESI
        if is_nil(killmail.related_character_id) do
          # No character ID, try alternative sources
          try_alternative_character_sources(killmail)
        else
          case lookup_character_name(killmail.related_character_id) do
            {:ok, name} when is_binary(name) and name != "" ->
              AppLogger.scheduler_info("Resolved character name from ESI: #{name}")
              %{killmail | related_character_name: name}

            _ ->
              # If ESI lookup fails, try alternative sources
              try_alternative_character_sources(killmail)
          end
        end
      else
        killmail
      end

    # Try to fix ship name if it's missing (for losses)
    killmail =
      case {killmail.character_role, killmail.ship_type_name, killmail.victim_data} do
        # For losses with unknown ship type but with victim data
        {false, nil, victim_data} when not is_nil(victim_data) ->
          Map.get(victim_data, "ship_type_name") || "Unknown Ship"

        {false, "Unknown Ship", victim_data} when not is_nil(victim_data) ->
          Map.get(victim_data, "ship_type_name") || "Unknown Ship"

        # If we have a valid ship name, use it
        {_, ship_type_name, _}
        when not is_nil(ship_type_name) and ship_type_name != "Unknown Ship" ->
          ship_type_name

        # Default fallback
        _ ->
          "Unknown Ship"
      end

    # Try to fix system name if missing
    if (is_nil(killmail.solar_system_name) || killmail.solar_system_name == "Unknown System") &&
         not is_nil(killmail.solar_system_id) do
      # For system ID, use J-format for wormhole systems
      if is_integer(killmail.solar_system_id) do
        system_id_str = "J#{killmail.solar_system_id}"
        AppLogger.scheduler_info("Using J-format system name: #{system_id_str}")
        %{killmail | solar_system_name: system_id_str}
      else
        killmail
      end
    else
      killmail
    end
  end

  # Try to get character name from alternative sources (victim_data or attacker_data)
  defp try_alternative_character_sources(killmail) do
    # Use pattern matching to handle different scenarios
    case {killmail.character_role, killmail.victim_data, killmail.attacker_data,
          killmail.related_character_id} do
      # Kill with victim data containing character name
      {:attacker, victim_data, _, _} when is_map(victim_data) ->
        case Map.get(victim_data, "character_name") do
          name when is_binary(name) and name != "" ->
            AppLogger.scheduler_info("Using character name from victim data: #{name}")
            %{killmail | related_character_name: name}

          _ ->
            try_attacker_data_fallback(killmail)
        end

      # Loss with victim data containing character name
      {:victim, victim_data, _, _} when is_map(victim_data) ->
        case Map.get(victim_data, "character_name") do
          name when is_binary(name) and name != "" ->
            AppLogger.scheduler_info("Using character name from victim data: #{name}")
            %{killmail | related_character_name: name}

          _ ->
            try_character_id_fallback(killmail)
        end

      # Default fallback to character ID if available
      {_, _, _, character_id} when not is_nil(character_id) ->
        try_character_id_fallback(killmail)

      # No data available
      _ ->
        %{killmail | related_character_name: "Unknown Pilot"}
    end
  end

  # Helper for getting name from attacker data
  defp try_attacker_data_fallback(killmail) do
    case killmail.attacker_data do
      attacker_data when is_map(attacker_data) ->
        case Map.get(attacker_data, "character_name") do
          name when is_binary(name) and name != "" ->
            AppLogger.scheduler_info("Using character name from attacker data: #{name}")
            %{killmail | related_character_name: name}

          _ ->
            AppLogger.scheduler_info("No character name found in kill data")
            try_character_id_fallback(killmail)
        end

      _ ->
        try_character_id_fallback(killmail)
    end
  end

  # Helper for resolving character name from character ID
  defp try_character_id_fallback(killmail) do
    case killmail.related_character_id do
      id when not is_nil(id) ->
        case lookup_character_name(id) do
          {:ok, name} when is_binary(name) and name != "" ->
            %{killmail | related_character_name: name}

          _ ->
            %{killmail | related_character_name: "Unknown Pilot"}
        end

      _ ->
        %{killmail | related_character_name: "Unknown Pilot"}
    end
  end

  # Look up a character name from the ESI API
  defp lookup_character_name(character_id) when not is_nil(character_id) do
    # First try repository cache
    case DataRepo.get_character_name(character_id) do
      {:ok, name} when is_binary(name) and name != "" and name != "Unknown" ->
        AppLogger.scheduler_info("Found character name in repository cache", %{
          character_id: character_id,
          character_name: name
        })

        {:ok, name}

      _ ->
        # Fall back to ESI API
        AppLogger.scheduler_info("Looking up character name via ESI API", %{
          character_id: character_id
        })

        case EsiService.get_character(character_id) do
          {:ok, character_data} when is_map(character_data) ->
            name = Map.get(character_data, "name")

            if is_binary(name) && name != "" do
              # Cache the name for future use
              CacheHelpers.cache_character_info(%{
                "character_id" => character_id,
                "name" => name
              })

              AppLogger.scheduler_info("Successfully resolved character name from ESI", %{
                character_id: character_id,
                character_name: name
              })

              {:ok, name}
            else
              AppLogger.scheduler_warn("ESI returned invalid character name", %{
                character_id: character_id,
                name: inspect(name)
              })

              {:error, :invalid_name}
            end

          error ->
            AppLogger.scheduler_warn("Failed to get character name from ESI", %{
              character_id: character_id,
              error: inspect(error)
            })

            {:error, :esi_failed}
        end
    end
  end

  defp lookup_character_name(_), do: {:error, :nil_character_id}

  # Format a kill/loss into a Discord embed
  defp format_kill_embed(killmail, is_kill, date_range) do
    # Extract and format basic information
    system_name = format_system_name(killmail)
    region_name = format_region_name(system_name, killmail.region_name)
    character_name = resolve_character_name(killmail, is_kill)
    ship_name = resolve_ship_name(is_kill, killmail.ship_type_name, killmail.victim_data)
    ship_type_id = killmail.ship_type_id
    is_loss = not is_kill

    # Log the formatted killmail
    log_killmail_formatting(
      killmail.killmail_id,
      is_kill,
      character_name,
      ship_name,
      ship_type_id,
      system_name,
      region_name,
      killmail.total_value
    )

    # Format field values
    formatted_isk = format_isk_compact(killmail.total_value)
    zkill_url = "https://zkillboard.com/kill/#{killmail.killmail_id}/"
    character_display = character_name

    # Create embed base structure
    {title, description, color} = get_embed_title_description(character_display, is_kill)
    detail_info = get_details_info(killmail, is_kill, is_loss)

    # Build the initial embed
    embed =
      create_base_embed(
        title,
        description,
        color,
        formatted_isk,
        ship_name,
        system_name,
        date_range,
        zkill_url,
        killmail.kill_time
      )

    # Add additional elements to the embed
    embed = add_details_to_embed(embed, detail_info)
    embed = add_thumbnail_to_embed(embed, is_kill, killmail.victim_data, ship_type_id)

    # Log the finalized embed
    log_embed_result(embed, is_kill, character_name, ship_name, system_name, region_name)

    embed
  end

  # Extract system name from killmail
  defp format_system_name(killmail) do
    case killmail.solar_system_name do
      nil ->
        # Try to construct from system ID if available (common for wormhole systems)
        if is_integer(killmail.solar_system_id),
          do: "J#{killmail.solar_system_id}",
          else: "Unknown System"

      "Unknown System" ->
        # Try to construct from system ID if available
        if is_integer(killmail.solar_system_id),
          do: "J#{killmail.solar_system_id}",
          else: "Unknown System"

      name ->
        name
    end
  end

  # Determine region name
  defp format_region_name(system_name, region_name) do
    case {system_name, region_name} do
      {name, nil} when is_binary(name) and binary_part(name, 0, 1) == "J" ->
        "J-Space"

      {name, "Unknown Region"} when is_binary(name) and binary_part(name, 0, 1) == "J" ->
        "J-Space"

      {_, region} when not is_nil(region) ->
        region

      _ ->
        "Unknown Region"
    end
  end

  # Resolve character name from killmail with appropriate fallbacks
  defp resolve_character_name(killmail, is_kill) do
    case {killmail.related_character_name, killmail.related_character_id, is_kill,
          killmail.victim_data} do
      # Unknown character name with ID available - try to resolve
      {<<"Unknown Character", _::binary>>, id, _, _} when not is_nil(id) ->
        resolve_name_from_id(id)

      # Nil character name with ID available - try to resolve
      {nil, id, _, _} when not is_nil(id) ->
        resolve_name_from_id(id)

      # Character ID format from previous enrichment with ID available
      {<<"Character #", _::binary>>, id, _, _} when not is_nil(id) ->
        resolve_name_from_id(id)

      # Loss with missing character name but victim data available
      {nil, _id, false, victim_data} when not is_nil(victim_data) ->
        Map.get(victim_data, "character_name") || "Unknown Pilot"

      {"Unknown Character", _id, false, victim_data} when not is_nil(victim_data) ->
        Map.get(victim_data, "character_name") || "Unknown Pilot"

      # Use existing character name
      {name, _, _, _} when not is_nil(name) ->
        name

      # Default fallback
      _ ->
        "Unknown Pilot"
    end
  end

  # Helper to resolve name from ID
  defp resolve_name_from_id(id) do
    case lookup_character_name(id) do
      {:ok, resolved_name} when is_binary(resolved_name) and resolved_name != "" ->
        resolved_name

      _ ->
        "Unknown Pilot"
    end
  end

  # Determine ship name with appropriate fallbacks
  defp resolve_ship_name(is_kill, ship_type_name, victim_data) do
    case {is_kill, ship_type_name, victim_data} do
      # For losses with unknown ship type but with victim data
      {false, nil, victim_data} when not is_nil(victim_data) ->
        Map.get(victim_data, "ship_type_name") || "Unknown Ship"

      {false, "Unknown Ship", victim_data} when not is_nil(victim_data) ->
        Map.get(victim_data, "ship_type_name") || "Unknown Ship"

      # If we have a valid ship name, use it
      {_, ship_type_name, _}
      when not is_nil(ship_type_name) and ship_type_name != "Unknown Ship" ->
        ship_type_name

      # Default fallback
      _ ->
        "Unknown Ship"
    end
  end

  # Log killmail formatting details
  defp log_killmail_formatting(
         killmail_id,
         is_kill,
         character_name,
         ship_name,
         ship_type_id,
         system_name,
         region_name,
         total_value
       ) do
    AppLogger.scheduler_info(
      "Formatting #{if is_kill, do: "kill", else: "loss"} embed: " <>
        "ID=#{killmail_id}, " <>
        "Character=#{character_name}, " <>
        "Ship=#{ship_name} (ID=#{ship_type_id}), " <>
        "System=#{system_name}, " <>
        "Region=#{region_name}, " <>
        "Value=#{inspect(total_value)}"
    )
  end

  # Get embed title, description, and color based on kill/loss type
  defp get_embed_title_description(character_display, is_kill) do
    if is_kill do
      {
        "🏆 Best Kill of the Week",
        "#{character_display} scored our most valuable kill this week!",
        # Green
        0x00FF00
      }
    else
      {
        "💀 Worst Loss of the Week",
        "#{character_display} suffered our most expensive loss this week.",
        # Red
        0xFF0000
      }
    end
  end

  # Build the base embed structure
  defp create_base_embed(
         title,
         description,
         color,
         formatted_isk,
         ship_name,
         system_name,
         date_range,
         zkill_url,
         kill_time
       ) do
    base_embed = %{
      "title" => title,
      "description" => description,
      "color" => color,
      "fields" => [
        %{
          "name" => "Value",
          "value" => formatted_isk,
          "inline" => true
        },
        %{
          "name" => "Ship",
          "value" => ship_name,
          "inline" => true
        },
        %{
          "name" => "Location",
          "value" => system_name,
          "inline" => true
        }
      ],
      "footer" => %{
        "text" => "Week of #{date_range}"
      },
      "timestamp" => DateTime.to_iso8601(kill_time),
      "url" => zkill_url
    }

    base_embed
  end

  # Get detailed information about the kill/loss
  defp get_details_info(killmail, is_kill, is_loss) do
    cond do
      # For kills, show destroyed ship, corporation and attackers count
      is_kill && killmail.victim_data ->
        get_kill_details(killmail)

      # For losses, show main attacker's ship and total attackers
      is_loss && killmail.attacker_data ->
        get_loss_details(killmail)

      # Default case - no details available
      true ->
        nil
    end
  end

  # Get detailed info for a kill
  defp get_kill_details(killmail) do
    victim_ship = Map.get(killmail.victim_data, "ship_type_name") || "Unknown Ship"
    victim_corp = Map.get(killmail.victim_data, "corporation_name") || "Unknown Corporation"

    # Access attacker_data properly, handling the case where it's a struct
    attackers_count = get_attackers_count(killmail.attacker_data)

    "Destroyed a #{victim_ship} belonging to #{victim_corp}\nTotal attackers: #{attackers_count}"
  end

  # Get detailed info for a loss
  defp get_loss_details(killmail) do
    # Access attacker_data properly, handling the case where it's a struct
    main_attacker_ship = get_attacker_ship(killmail.attacker_data)
    attackers_count = get_attackers_count(killmail.attacker_data)
    main_attacker_corp = get_attacker_corporation(killmail.attacker_data)

    "Killed by #{main_attacker_ship} from #{main_attacker_corp}\nTotal attackers: #{attackers_count}"
  end

  # Extract attacker ship info
  defp get_attacker_ship(attacker_data) do
    case attacker_data do
      data when is_map(data) and not is_struct(data) ->
        Map.get(data, "ship_type_name") || "Unknown Ship"

      %{ship_type_name: name} ->
        name || "Unknown Ship"

      _ ->
        "Unknown Ship"
    end
  end

  # Extract attackers count
  defp get_attackers_count(attacker_data) do
    case attacker_data do
      data when is_map(data) and not is_struct(data) ->
        Map.get(data, "attackers_count") || "Unknown"

      %{attackers_count: count} ->
        count || "Unknown"

      _ ->
        "Unknown"
    end
  end

  # Extract attacker corporation
  defp get_attacker_corporation(attacker_data) do
    case attacker_data do
      data when is_map(data) and not is_struct(data) ->
        Map.get(data, "corporation_name") || "Unknown Corporation"

      %{corporation_name: name} ->
        name || "Unknown Corporation"

      _ ->
        "Unknown Corporation"
    end
  end

  # Add details field to embed if available
  defp add_details_to_embed(embed, nil), do: embed

  defp add_details_to_embed(embed, info) do
    updated_fields =
      embed["fields"] ++
        [
          %{
            "name" => "Details",
            "value" => info,
            "inline" => false
          }
        ]

    %{embed | "fields" => updated_fields}
  end

  # Add thumbnail to embed if possible
  defp add_thumbnail_to_embed(embed, is_kill, victim_data, ship_type_id) do
    case {is_kill, victim_data, ship_type_id} do
      # For kills, try to use victim ship image from victim data
      {true, victim_data, _} when not is_nil(victim_data) ->
        victim_type_id = Map.get(victim_data, "ship_type_id")

        if victim_type_id do
          ship_image_url = "https://images.evetech.net/types/#{victim_type_id}/render?size=128"
          Map.put(embed, "thumbnail", %{"url" => ship_image_url})
        else
          embed
        end

      # For losses, use our ship image if available
      {false, _, ship_id} when not is_nil(ship_id) ->
        ship_image_url = "https://images.evetech.net/types/#{ship_id}/render?size=128"
        Map.put(embed, "thumbnail", %{"url" => ship_image_url})

      # No thumbnail data available
      _ ->
        embed
    end
  end

  # Log the final embed
  defp log_embed_result(embed, is_kill, character_name, ship_name, system_name, region_name) do
    AppLogger.scheduler_info(
      "Generated embed for #{if is_kill, do: "kill", else: "loss"}: " <>
        "Title=\"#{embed["title"]}\", " <>
        "Character=#{character_name}, " <>
        "Ship=#{ship_name}, " <>
        "System=#{system_name}, " <>
        "Region=#{region_name}, " <>
        "Fields=#{length(embed["fields"])}, " <>
        "Has thumbnail=#{Map.has_key?(embed, "thumbnail")}"
    )
  end

  # Format ISK value for display in a more compact way
  defp format_isk_compact(value) do
    # Handle nil value
    if is_nil(value) do
      "Unknown"
    else
      # Try to convert to float
      float_value = try_convert_to_float(value)

      # Format based on magnitude
      cond do
        float_value >= 1_000_000_000 ->
          "#{format_float(float_value / 1_000_000_000)}B ISK"

        float_value >= 1_000_000 ->
          "#{format_float(float_value / 1_000_000)}M ISK"

        float_value >= 1_000 ->
          "#{format_float(float_value / 1_000)}K ISK"

        true ->
          "#{format_float(float_value)} ISK"
      end
    end
  end

  # Helper function to try converting a value to float
  defp try_convert_to_float(value) do
    # Handle each data type with appropriate conversion
    cond do
      # Already a float
      is_float(value) ->
        value

      # Integer -> float
      is_integer(value) ->
        value / 1.0

      # String -> float
      is_binary(value) ->
        case Float.parse(value) do
          {float, _} -> float
          :error -> 0.0
        end

      # Decimal -> float
      is_map(value) && Map.has_key?(value, :__struct__) && value.__struct__ == Decimal ->
        convert_decimal_to_float(value)

      # Any other struct with a :value field (some composite types)
      is_map(value) && Map.has_key?(value, :__struct__) && Map.has_key?(value, :value) ->
        try_convert_to_float(Map.get(value, :value))

      # Any other map with a "value" key (JSON data)
      is_map(value) && Map.has_key?(value, "value") ->
        try_convert_to_float(Map.get(value, "value"))

      # Default case
      true ->
        0.0
    end
  rescue
    # Catch any unexpected errors
    error ->
      AppLogger.scheduler_error("Error converting value to float: #{inspect(error)}")
      0.0
  end

  # Helper function to handle Decimal conversion
  defp convert_decimal_to_float(decimal) do
    with {:ok, float} <- safe_decimal_to_float(decimal) do
      float
    else
      :error ->
        with {:ok, str} <- safe_decimal_to_string(decimal),
             {float, _} <- Float.parse(str) do
          float
        else
          _ -> 0.0
        end
    end
  end

  # Safe wrapper for Decimal.to_float
  defp safe_decimal_to_float(decimal) do
    {:ok, Decimal.to_float(decimal)}
  rescue
    _ -> :error
  end

  # Safe wrapper for Decimal.to_string
  defp safe_decimal_to_string(decimal) do
    {:ok, Decimal.to_string(decimal)}
  rescue
    _ -> :error
  end

  # Helper to format a float to 2 decimal places
  defp format_float(float) do
    :erlang.float_to_binary(float, [{:decimals, 2}])
  end

  # For dependency injection in tests
  defp config do
    Application.get_env(:wanderer_notifier, :config_module, NotificationConfig)
  end

  # Check if a ship type ID belongs to a structure or deployable category/group
  defp structure_or_deployable?(ship_type_id) when is_nil(ship_type_id), do: false

  defp structure_or_deployable?(ship_type_id) when is_integer(ship_type_id),
    do: check_structure_cache(ship_type_id)

  defp structure_or_deployable?(ship_type_id) when is_binary(ship_type_id) do
    case Integer.parse(ship_type_id) do
      {int_id, _} -> check_structure_cache(int_id)
      :error -> false
    end
  end

  defp structure_or_deployable?(_), do: false

  # Helper to check the cache for a ship type
  defp check_structure_cache(type_id) do
    # Initialize cache if needed
    ensure_structure_cache_exists()

    # Get from cache or fetch from API
    cache = Process.get(@structure_types_cache_key)

    case Map.get(cache, type_id) do
      nil -> check_and_cache_structure_type(type_id)
      is_structure -> is_structure
    end
  end

  # Ensure the structure type cache exists
  defp ensure_structure_cache_exists do
    case Process.get(@structure_types_cache_key) do
      nil -> Process.put(@structure_types_cache_key, %{})
      _ -> :ok
    end
  end

  # Check ESI API for type information and cache result
  defp check_and_cache_structure_type(type_id) do
    # Try to get type information from ESI
    case ESIService.get_type_info(type_id) do
      {:ok, type_info} when is_map(type_info) ->
        # Extract category ID and group ID from type info
        category_id = Map.get(type_info, "category_id")
        group_id = Map.get(type_info, "group_id")

        AppLogger.scheduler_debug(
          "ESI type info for type_id #{type_id}: category_id=#{category_id}, group_id=#{group_id}"
        )

        # Determine if it's a structure
        is_structure = is_structure_type?(category_id, group_id)

        # Update cache
        update_structure_cache(type_id, is_structure)
        is_structure

      error ->
        # Log error and default to false
        AppLogger.scheduler_warn(
          "Failed to get type info for type_id #{type_id}: #{inspect(error)}"
        )

        # Cache as false to avoid repeated failures
        update_structure_cache(type_id, false)
        false
    end
  end

  # Helper to determine if a type is a structure based on category and group
  defp is_structure_type?(category_id, group_id) do
    category_id == @structure_category_id ||
      category_id == @deployable_category_id ||
      (group_id && (group_id in @structure_group_ids || group_id in @deployable_group_ids))
  end

  # Update the structure cache with a new value
  defp update_structure_cache(type_id, is_structure) do
    cache = Process.get(@structure_types_cache_key)
    updated_cache = Map.put(cache, type_id, is_structure)
    Process.put(@structure_types_cache_key, updated_cache)
  end
end
