defmodule WandererNotifier.Schedulers.WeeklyKillHighlightsScheduler do
  @moduledoc """
  Scheduler for sending weekly kill highlights to Discord.
  Sends the best kill and worst loss from the past week for tracked characters.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  require Ash.Query, as: Query

  # EVE Online type IDs
  # Structure category
  @structure_category_id 65
  # Capsule (pod) type ID
  @pod_type_id 670

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
    # Log query parameters
    AppLogger.scheduler_info(
      "Searching for best kill between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    # Get tracked character IDs from our tracking system
    all_tracked_character_ids = get_tracked_character_ids()

    AppLogger.scheduler_info(
      "Retrieved #{length(all_tracked_character_ids)} tracked character IDs"
    )

    if all_tracked_character_ids == [] do
      AppLogger.scheduler_warn("No tracked characters found, cannot search for best kill")
      {:error, :no_tracked_characters}
    else
      # Only search for killmails where the character is actually tracked
      # Query for all killmails in the date range
      date_query =
        Killmail
        |> Query.filter(character_role == :attacker)
        |> Query.filter(kill_time >= ^start_date)
        |> Query.filter(kill_time <= ^end_date)
        |> Query.filter(ship_type_id != ^@pod_type_id)
        |> Query.filter(ship_type_id != ^@structure_category_id)
        |> Query.sort(total_value: :desc)
        |> Query.limit(100)

      case Api.read(date_query) do
        {:ok, []} ->
          AppLogger.scheduler_warn("No kills found in the date range")
          {:error, :no_kills_in_range}

        {:ok, kills} ->
          # Log all the found kills for debugging
          kills_count = length(kills)
          AppLogger.scheduler_info("Found #{kills_count} total kills in date range")

          # Filter to keep only kills where the character is actually tracked
          tracked_kills =
            Enum.filter(kills, fn kill ->
              # Convert the related_character_id to integer to match our list
              character_id = kill.related_character_id

              character_id_int =
                if is_binary(character_id),
                  do: String.to_integer(character_id),
                  else: character_id

              # Character is tracked if their ID is in our tracked IDs list
              is_tracked = Enum.member?(all_tracked_character_ids, character_id_int)

              # Log which characters aren't tracked for debugging
              unless is_tracked do
                AppLogger.scheduler_debug(
                  "Character #{character_id} is not tracked - ignoring kill #{kill.killmail_id}"
                )
              end

              is_tracked
            end)

          # Group by killmail_id to handle multiple tracked characters in same killmail
          grouped_kills = Enum.group_by(tracked_kills, fn kill -> kill.killmail_id end)

          # Select best character for each killmail (highest damage dealer)
          deduplicated_kills =
            Enum.map(grouped_kills, fn {_killmail_id, kills_for_id} ->
              if length(kills_for_id) > 1 do
                # Multiple tracked characters were involved, select the one with highest damage
                AppLogger.scheduler_info(
                  "Multiple tracked characters involved in killmail #{List.first(kills_for_id).killmail_id}"
                )

                # Find the character with highest damage
                best_character_kill =
                  Enum.max_by(kills_for_id, fn kill ->
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
                  end)

                AppLogger.scheduler_info(
                  "Selected character #{best_character_kill.related_character_id} with highest damage"
                )

                best_character_kill
              else
                # Only one tracked character was involved
                List.first(kills_for_id)
              end
            end)
            |> Enum.filter(fn kill -> not is_nil(kill) end)

          # Log how many kills remain after filtering and deduplication
          deduped_count = length(deduplicated_kills)

          AppLogger.scheduler_info(
            "Found #{deduped_count} unique kills with tracked attackers after filtering"
          )

          # Filter for kills with value
          kills_with_value =
            Enum.filter(deduplicated_kills, fn kill -> kill.total_value != nil end)

          if kills_with_value != [] do
            # Get the kill with the highest value
            best_kill =
              Enum.max_by(
                kills_with_value,
                fn kill ->
                  case kill.total_value do
                    nil -> Decimal.new(0)
                    val when is_struct(val, Decimal) -> val
                    _ -> Decimal.new(0)
                  end
                end
              )

            # Log the complete killmail struct for debugging
            AppLogger.scheduler_debug(
              "FULL BEST KILLMAIL STRUCT: #{inspect(best_kill, pretty: true, limit: :infinity)}"
            )

            # Enrich missing data if necessary
            best_kill = enrich_killmail_data(best_kill)

            # Log selected kill details for debugging
            AppLogger.scheduler_info(
              "Selected best kill: ID=#{best_kill.killmail_id}, " <>
                "Character=#{best_kill.related_character_name || "Unknown"}, " <>
                "Ship=#{best_kill.ship_type_name || "Unknown"}, " <>
                "System=#{best_kill.solar_system_name || "Unknown"}, " <>
                "Region=#{best_kill.region_name || "Unknown"}, " <>
                "Value=#{inspect(best_kill.total_value)}, " <>
                "Time=#{DateTime.to_string(best_kill.kill_time)}"
            )

            {:ok, best_kill}
          else
            AppLogger.scheduler_warn("No kills with valid values found")
            {:error, :no_kills_with_value}
          end

        error ->
          AppLogger.scheduler_error("Error querying kills in date range: #{inspect(error)}")
          {:error, "Failed to find kills in date range"}
      end
    end
  end

  # Find the worst loss (highest value) in the given period
  defp find_worst_loss(start_date, end_date) do
    # Log query parameters
    AppLogger.scheduler_info(
      "Searching for worst loss between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    # Get tracked character IDs from our tracking system
    all_tracked_character_ids = get_tracked_character_ids()

    AppLogger.scheduler_info(
      "Retrieved #{length(all_tracked_character_ids)} tracked character IDs"
    )

    if all_tracked_character_ids == [] do
      AppLogger.scheduler_warn("No tracked characters found, cannot search for worst loss")
      {:error, :no_tracked_characters}
    else
      # Query for all losses in the date range
      date_query =
        Killmail
        |> Query.filter(character_role == :victim)
        |> Query.filter(kill_time >= ^start_date)
        |> Query.filter(kill_time <= ^end_date)
        |> Query.filter(ship_type_id != ^@pod_type_id)
        |> Query.filter(ship_type_id != ^@structure_category_id)
        |> Query.sort(total_value: :desc)
        |> Query.limit(100)

      case Api.read(date_query) do
        {:ok, []} ->
          AppLogger.scheduler_warn("No losses found in the date range")
          {:error, :no_losses_in_range}

        {:ok, losses} ->
          # Log all the found losses for debugging
          losses_count = length(losses)
          AppLogger.scheduler_info("Found #{losses_count} total losses in date range")

          # Filter to keep only losses where the character is actually tracked
          tracked_losses =
            Enum.filter(losses, fn loss ->
              # Convert the related_character_id to integer to match our list
              character_id = loss.related_character_id

              character_id_int =
                if is_binary(character_id),
                  do: String.to_integer(character_id),
                  else: character_id

              # Character is tracked if their ID is in our tracked IDs list
              is_tracked = Enum.member?(all_tracked_character_ids, character_id_int)

              # Log which characters aren't tracked for debugging
              unless is_tracked do
                AppLogger.scheduler_debug(
                  "Character #{character_id} is not tracked - ignoring loss #{loss.killmail_id}"
                )
              end

              is_tracked
            end)

          # Group by killmail_id to handle multiple tracked characters in same killmail
          grouped_losses = Enum.group_by(tracked_losses, fn loss -> loss.killmail_id end)

          # Select one character for each killmail
          deduplicated_losses =
            Enum.map(grouped_losses, fn {_killmail_id, losses_for_id} ->
              if length(losses_for_id) > 1 do
                # Multiple tracked characters were lost in the same killmail (rare but possible)
                AppLogger.scheduler_info(
                  "Multiple tracked characters lost in killmail #{List.first(losses_for_id).killmail_id}"
                )

                # For losses, we just take the first one, as it's unlikely to matter much
                # Most situations with multiple victims are in the same group and equally important
                List.first(losses_for_id)
              else
                # Only one tracked character was lost
                List.first(losses_for_id)
              end
            end)
            |> Enum.filter(fn loss -> not is_nil(loss) end)

          # Log how many losses remain after filtering and deduplication
          deduped_count = length(deduplicated_losses)

          AppLogger.scheduler_info(
            "Found #{deduped_count} unique losses with tracked victims after filtering"
          )

          # Filter for losses with value
          losses_with_value =
            Enum.filter(deduplicated_losses, fn loss -> loss.total_value != nil end)

          if losses_with_value != [] do
            # Get the loss with the highest value
            worst_loss =
              Enum.max_by(
                losses_with_value,
                fn loss ->
                  case loss.total_value do
                    nil -> Decimal.new(0)
                    val when is_struct(val, Decimal) -> val
                    _ -> Decimal.new(0)
                  end
                end
              )

            # Log the complete killmail struct for debugging
            AppLogger.scheduler_debug(
              "FULL WORST KILLMAIL STRUCT: #{inspect(worst_loss, pretty: true, limit: :infinity)}"
            )

            # Enrich missing data if necessary
            worst_loss = enrich_killmail_data(worst_loss)

            # Log selected loss details for debugging
            AppLogger.scheduler_info(
              "Selected worst loss: ID=#{worst_loss.killmail_id}, " <>
                "Character=#{worst_loss.related_character_name || "Unknown"}, " <>
                "Ship=#{worst_loss.ship_type_name || "Unknown"}, " <>
                "System=#{worst_loss.solar_system_name || "Unknown"}, " <>
                "Region=#{worst_loss.region_name || "Unknown"}, " <>
                "Value=#{inspect(worst_loss.total_value)}, " <>
                "Time=#{DateTime.to_string(worst_loss.kill_time)}"
            )

            {:ok, worst_loss}
          else
            AppLogger.scheduler_warn("No losses with valid values found")
            {:error, :no_losses_with_value}
          end

        error ->
          AppLogger.scheduler_error("Error querying losses in date range: #{inspect(error)}")
          {:error, "Failed to find losses in date range"}
      end
    end
  end

  # Get list of tracked character IDs for filtering
  defp get_tracked_character_ids do
    # First try getting characters from repository cache
    tracked_characters = WandererNotifier.Data.Repository.get_tracked_characters()

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
        if not is_nil(killmail.related_character_id) do
          case lookup_character_name(killmail.related_character_id) do
            {:ok, name} when is_binary(name) and name != "" ->
              AppLogger.scheduler_info("Resolved character name from ESI: #{name}")
              %{killmail | related_character_name: name}

            _ ->
              # If ESI lookup fails, try alternative sources
              try_alternative_character_sources(killmail)
          end
        else
          # No character ID, try alternative sources
          try_alternative_character_sources(killmail)
        end
      else
        killmail
      end

    # Try to fix ship name if it's missing (for losses)
    killmail =
      if (is_nil(killmail.ship_type_name) || killmail.ship_type_name == "Unknown Ship") &&
           killmail.character_role == :victim &&
           not is_nil(killmail.victim_data) do
        ship_name = Map.get(killmail.victim_data, "ship_type_name")

        if not is_nil(ship_name) && ship_name != "" do
          AppLogger.scheduler_info("Using ship name from victim data: #{ship_name}")
          %{killmail | ship_type_name: ship_name}
        else
          killmail
        end
      else
        killmail
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
    # If this is a kill, try to get from victim_data
    if killmail.character_role == :attacker && not is_nil(killmail.victim_data) do
      char_name = Map.get(killmail.victim_data, "character_name")

      if not is_nil(char_name) && char_name != "" do
        AppLogger.scheduler_info("Using character name from victim data: #{char_name}")
        %{killmail | related_character_name: char_name}
      else
        # Try attacker data
        if not is_nil(killmail.attacker_data) do
          char_name =
            if is_map(killmail.attacker_data) do
              Map.get(killmail.attacker_data, "character_name")
            else
              nil
            end

          if not is_nil(char_name) && char_name != "" do
            AppLogger.scheduler_info("Using character name from attacker data: #{char_name}")
            %{killmail | related_character_name: char_name}
          else
            AppLogger.scheduler_info("No character name found in kill data")
            # Fall back to character ID if available
            if not is_nil(killmail.related_character_id) do
              # Try to resolve it again
              case lookup_character_name(killmail.related_character_id) do
                {:ok, name} when is_binary(name) and name != "" ->
                  %{killmail | related_character_name: name}

                _ ->
                  %{killmail | related_character_name: "Unknown Pilot"}
              end
            else
              %{killmail | related_character_name: "Unknown Pilot"}
            end
          end
        else
          # Fall back to character ID if available
          if not is_nil(killmail.related_character_id) do
            # Try to resolve it again
            case lookup_character_name(killmail.related_character_id) do
              {:ok, name} when is_binary(name) and name != "" ->
                %{killmail | related_character_name: name}

              _ ->
                %{killmail | related_character_name: "Unknown Pilot"}
            end
          else
            %{killmail | related_character_name: "Unknown Pilot"}
          end
        end
      end
    else
      # For losses
      if killmail.character_role == :victim && not is_nil(killmail.victim_data) do
        char_name = Map.get(killmail.victim_data, "character_name")

        if not is_nil(char_name) && char_name != "" do
          AppLogger.scheduler_info("Using character name from victim data: #{char_name}")
          %{killmail | related_character_name: char_name}
        else
          AppLogger.scheduler_info("No character name found in loss data")
          # Fall back to character ID if available
          if not is_nil(killmail.related_character_id) do
            # Try to resolve it again
            case lookup_character_name(killmail.related_character_id) do
              {:ok, name} when is_binary(name) and name != "" ->
                %{killmail | related_character_name: name}

              _ ->
                %{killmail | related_character_name: "Unknown Pilot"}
            end
          else
            %{killmail | related_character_name: "Unknown Pilot"}
          end
        end
      else
        # Fall back to character ID if available
        if not is_nil(killmail.related_character_id) do
          # Try to resolve it again
          case lookup_character_name(killmail.related_character_id) do
            {:ok, name} when is_binary(name) and name != "" ->
              %{killmail | related_character_name: name}

            _ ->
              %{killmail | related_character_name: "Unknown Pilot"}
          end
        else
          %{killmail | related_character_name: "Unknown Pilot"}
        end
      end
    end
  end

  # Look up a character name from the ESI API
  defp lookup_character_name(character_id) when not is_nil(character_id) do
    # First try repository cache
    case WandererNotifier.Data.Repository.get_character_name(character_id) do
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

        case WandererNotifier.Api.ESI.Service.get_character(character_id) do
          {:ok, character_data} when is_map(character_data) ->
            name = Map.get(character_data, "name")

            if is_binary(name) && name != "" do
              # Cache the name for future use
              WandererNotifier.Data.Cache.Helpers.cache_character_info(%{
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
    # See if solar_system_name is already in J-format
    system_name =
      if is_nil(killmail.solar_system_name) || killmail.solar_system_name == "Unknown System" do
        # Try to construct from system ID if available (common for wormhole systems)
        if is_integer(killmail.solar_system_id) do
          "J#{killmail.solar_system_id}"
        else
          "Unknown System"
        end
      else
        killmail.solar_system_name
      end

    # For system names starting with J and no region, it's a wormhole system
    region_name =
      if system_name != nil &&
           String.starts_with?(system_name, "J") &&
           (killmail.region_name == nil || killmail.region_name == "Unknown Region") do
        "J-Space"
      else
        killmail.region_name || "Unknown Region"
      end

    # Ensure we get the proper character name - try to resolve it if we have the ID
    character_name =
      cond do
        # Try to resolve character ID if name is unknown or has "Unknown Character" prefix
        (is_binary(killmail.related_character_name) &&
           String.starts_with?(killmail.related_character_name, "Unknown Character")) ||
            is_nil(killmail.related_character_name) ->
          if not is_nil(killmail.related_character_id) do
            case lookup_character_name(killmail.related_character_id) do
              {:ok, name} when is_binary(name) and name != "" -> name
              _ -> "Unknown Pilot"
            end
          else
            # Fallback when no ID is available
            "Unknown Pilot"
          end

        # Handle string "Character #ID" format (from previous enrichment)
        is_binary(killmail.related_character_name) &&
            String.starts_with?(killmail.related_character_name, "Character #") ->
          if not is_nil(killmail.related_character_id) do
            case lookup_character_name(killmail.related_character_id) do
              {:ok, name} when is_binary(name) and name != "" -> name
              _ -> "Unknown Pilot"
            end
          else
            "Unknown Pilot"
          end

        # Special handling for loss notifications without proper name but with victim data
        not is_kill &&
            (killmail.related_character_name == nil ||
               killmail.related_character_name == "Unknown Character") ->
          if not is_nil(killmail.victim_data) do
            character_name_from_victim = Map.get(killmail.victim_data, "character_name")

            character_name_from_victim ||
              if not is_nil(killmail.related_character_id),
                do: "Unknown Pilot",
                else: "Unknown Pilot"
          else
            if not is_nil(killmail.related_character_id),
              do: "Unknown Pilot",
              else: "Unknown Pilot"
          end

        # Use existing character name
        true ->
          killmail.related_character_name
      end

    # Try to get ship name from victim_data for losses
    ship_name =
      if not is_kill &&
           (killmail.ship_type_name == nil || killmail.ship_type_name == "Unknown Ship") do
        if not is_nil(killmail.victim_data) do
          Map.get(killmail.victim_data, "ship_type_name") || "Unknown Ship"
        else
          "Unknown Ship"
        end
      else
        killmail.ship_type_name || "Unknown Ship"
      end

    ship_type_id = killmail.ship_type_id

    # Log the full killmail for debugging
    AppLogger.scheduler_info(
      "Formatting #{if is_kill, do: "kill", else: "loss"} embed: " <>
        "ID=#{killmail.killmail_id}, " <>
        "Character=#{character_name}, " <>
        "Ship=#{ship_name} (ID=#{ship_type_id}), " <>
        "System=#{system_name}, " <>
        "Region=#{region_name}, " <>
        "Value=#{inspect(killmail.total_value)}"
    )

    # Format ISK value
    formatted_isk = format_isk_compact(killmail.total_value)

    # ZKillboard URL for the kill
    zkill_url = "https://zkillboard.com/kill/#{killmail.killmail_id}/"

    # Create character link for Discord
    character_display = character_name

    # Determine title, description and color based on whether this is a kill or loss
    {title, description, color} =
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

    # More detailed victim/attacker info
    detail_info =
      cond do
        # For kills, show destroyed ship, corporation and attackers count
        is_kill && killmail.victim_data ->
          victim_ship = Map.get(killmail.victim_data, "ship_type_name") || "Unknown Ship"
          victim_corp = Map.get(killmail.victim_data, "corporation_name") || "Unknown Corporation"

          # Access attacker_data properly, handling the case where it's a struct
          attackers_count =
            cond do
              is_map(killmail.attacker_data) && !is_struct(killmail.attacker_data) ->
                Map.get(killmail.attacker_data, "attackers_count") || "Unknown"

              is_struct(killmail.attacker_data) &&
                  Map.has_key?(killmail.attacker_data, :attackers_count) ->
                Map.get(killmail.attacker_data, :attackers_count) || "Unknown"

              true ->
                "Unknown"
            end

          "Destroyed a #{victim_ship} belonging to #{victim_corp}\nTotal attackers: #{attackers_count}"

        # For losses, show main attacker's ship and total attackers
        not is_kill && killmail.attacker_data ->
          # Access attacker_data properly, handling the case where it's a struct
          main_attacker_ship =
            cond do
              is_map(killmail.attacker_data) && !is_struct(killmail.attacker_data) ->
                Map.get(killmail.attacker_data, "ship_type_name") || "Unknown Ship"

              is_struct(killmail.attacker_data) &&
                  Map.has_key?(killmail.attacker_data, :ship_type_name) ->
                Map.get(killmail.attacker_data, :ship_type_name) || "Unknown Ship"

              true ->
                "Unknown Ship"
            end

          attackers_count =
            cond do
              is_map(killmail.attacker_data) && !is_struct(killmail.attacker_data) ->
                Map.get(killmail.attacker_data, "attackers_count") || "Unknown"

              is_struct(killmail.attacker_data) &&
                  Map.has_key?(killmail.attacker_data, :attackers_count) ->
                Map.get(killmail.attacker_data, :attackers_count) || "Unknown"

              true ->
                "Unknown"
            end

          main_attacker_corp =
            cond do
              is_map(killmail.attacker_data) && !is_struct(killmail.attacker_data) ->
                Map.get(killmail.attacker_data, "corporation_name") || "Unknown Corporation"

              is_struct(killmail.attacker_data) &&
                  Map.has_key?(killmail.attacker_data, :corporation_name) ->
                Map.get(killmail.attacker_data, :corporation_name) || "Unknown Corporation"

              true ->
                "Unknown Corporation"
            end

          "Killed by #{main_attacker_ship} from #{main_attacker_corp}\nTotal attackers: #{attackers_count}"

        # Default case - no details available
        true ->
          nil
      end

    # Build the embed
    embed = %{
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
        "text" => "Week of #{date_range} • [View on zKillboard](#{zkill_url})"
      },
      "timestamp" => DateTime.to_iso8601(killmail.kill_time)
    }

    # Add zkillboard URL (Discord doesn't support markdown in footers)
    embed = Map.put(embed, "url", zkill_url)

    # Update footer to not include the markdown link
    embed = put_in(embed, ["footer", "text"], "Week of #{date_range}")

    # Add details field if available
    embed =
      if detail_info do
        updated_fields =
          embed["fields"] ++
            [
              %{
                "name" => "Details",
                "value" => detail_info,
                "inline" => false
              }
            ]

        %{embed | "fields" => updated_fields}
      else
        embed
      end

    # Add view link field
    updated_fields =
      embed["fields"] ++
        [
          %{
            "name" => "Links",
            "value" => "[View on zKillboard](#{zkill_url})",
            "inline" => false
          }
        ]

    embed = %{embed | "fields" => updated_fields}

    # Add thumbnail if possible
    embed =
      if is_kill do
        # For kills, try to use victim ship image
        victim_type_id =
          if is_nil(killmail.victim_data) do
            nil
          else
            Map.get(killmail.victim_data, "ship_type_id")
          end

        if victim_type_id do
          ship_image_url = "https://images.evetech.net/types/#{victim_type_id}/render?size=128"
          Map.put(embed, "thumbnail", %{"url" => ship_image_url})
        else
          embed
        end
      else
        # For losses, use our ship image
        if ship_type_id do
          ship_image_url =
            "https://images.evetech.net/types/#{ship_type_id}/render?size=128"

          Map.put(embed, "thumbnail", %{"url" => ship_image_url})
        else
          embed
        end
      end

    # Log the generated embed
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

    embed
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

  # Format ISK value for display (original version, kept for backward compatibility)
  defp format_isk(value) do
    # Log the raw value
    AppLogger.scheduler_info("Formatting ISK value: Raw value = #{inspect(value)}")

    # Handle nil value
    if is_nil(value) do
      "Unknown"
    else
      # Try to convert to float
      float_value = try_convert_to_float(value)

      # Log the converted float value
      AppLogger.scheduler_info("Converted value to float: #{float_value}")

      # Format based on magnitude
      cond do
        float_value >= 1_000_000_000 ->
          "#{format_float(float_value / 1_000_000_000)} billion ISK"

        float_value >= 1_000_000 ->
          "#{format_float(float_value / 1_000_000)} million ISK"

        float_value >= 1_000 ->
          "#{format_float(float_value / 1_000)} thousand ISK"

        true ->
          "#{format_float(float_value)} ISK"
      end
    end
  end

  # Helper function to try converting a value to float
  defp try_convert_to_float(value) do
    try do
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
          try do
            # Try Decimal.to_float
            Decimal.to_float(value)
          rescue
            # If that fails, try string conversion
            _ ->
              try do
                str = Decimal.to_string(value)

                case Float.parse(str) do
                  {float, _} -> float
                  :error -> 0.0
                end
              rescue
                # Last resort
                _ -> 0.0
              end
          end

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
  end

  # Helper to format a float to 2 decimal places
  defp format_float(float) do
    :erlang.float_to_binary(float, [{:decimals, 2}])
  end

  # For dependency injection in tests
  defp config do
    Application.get_env(:wanderer_notifier, :config_module, NotificationConfig)
  end
end
