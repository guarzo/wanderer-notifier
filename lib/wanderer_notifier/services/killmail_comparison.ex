defmodule WandererNotifier.Services.KillmailComparison do
  @moduledoc """
  Service for comparing killmail data between our database and zKillboard.
  Helps identify discrepancies in kill tracking.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Resources.{Killmail, Api}
  alias WandererNotifier.Services.ZKillboardApi
  import Ash.Query

  # Note: ZKillboard API no longer supports direct date filtering via startTime/endTime parameters.
  # Instead, we fetch all recent kills for a character and filter them in memory.
  # This approach was implemented after discovering that the API's date filtering was removed.

  @doc """
  Compares killmails between our database and zKillboard for a given character and timespan.

  ## Parameters
    - character_id: The character ID to compare
    - start_date: Start date for comparison (DateTime)
    - end_date: End date for comparison (DateTime)

  ## Returns
    {:ok, %{
      our_kills: integer,
      zkill_kills: integer,
      missing_kills: [integer],
      extra_kills: [integer],
      comparison: %{
        total_difference: integer,
        percentage_match: float,
        analysis: String.t()
      }
    }}
  """
  def compare_killmails(character_id, start_date, end_date) do
    AppLogger.processor_info("Starting killmail comparison", %{
      character_id: character_id,
      start_date: DateTime.to_iso8601(start_date),
      end_date: DateTime.to_iso8601(end_date)
    })

    with {:ok, our_kills} <- fetch_our_kills(character_id, start_date, end_date),
         {:ok, zkill_kills} <- fetch_zkill_kills(character_id, start_date, end_date) do
      our_kill_ids = MapSet.new(our_kills, & &1.killmail_id)
      zkill_kill_ids = MapSet.new(zkill_kills, & &1["killmail_id"])

      # Find kills we're missing (in zKill but not in our DB)
      missing_kills = MapSet.difference(zkill_kill_ids, our_kill_ids)

      # Find extra kills (in our DB but not in zKill)
      extra_kills = MapSet.difference(our_kill_ids, zkill_kill_ids)

      # Calculate statistics
      stats =
        calculate_comparison_stats(
          our_kill_ids,
          zkill_kill_ids,
          missing_kills,
          extra_kills
        )

      {:ok,
       %{
         our_kills: MapSet.size(our_kill_ids),
         zkill_kills: MapSet.size(zkill_kill_ids),
         missing_kills: MapSet.to_list(missing_kills),
         extra_kills: MapSet.to_list(extra_kills),
         comparison: stats
       }}
    end
  end

  @doc """
  Analyzes specific killmails that are missing from our database.
  Helps identify patterns in what we're missing.

  ## Parameters
    - character_id: The character ID to analyze
    - kill_ids: List of killmail IDs to analyze

  ## Returns
    {:ok, analysis_results}
  """
  def analyze_missing_kills(character_id, kill_ids) when is_list(kill_ids) do
    # Fetch detailed information about missing kills from zKillboard
    kills_info =
      Enum.map(kill_ids, fn kill_id ->
        case ZKillboardApi.get_killmail(kill_id) do
          {:ok, kill_data} ->
            Logger.info("ZKB Data for #{kill_id}: #{inspect(kill_data)}")

            # Get the hash from ZKB data
            hash = get_in(kill_data, ["zkb", "hash"])

            # Fetch ESI data
            case WandererNotifier.Api.ESI.Service.get_killmail(kill_id, hash) do
              {:ok, esi_data} ->
                Logger.info("ESI Data for #{kill_id}: #{inspect(esi_data)}")
                # Merge ZKB and ESI data
                merged_data = Map.merge(kill_data, esi_data)
                Logger.info("Merged Data for #{kill_id}: #{inspect(merged_data)}")

                # Add basic analysis of why we might have missed it
                analysis = analyze_kill_miss_reason(merged_data, character_id)
                %{kill_id: kill_id, reason: analysis}

              {:error, esi_error} ->
                Logger.error("Failed to get ESI data for #{kill_id}: #{inspect(esi_error)}")
                %{kill_id: kill_id, reason: :fetch_failed}
            end

          _ ->
            %{kill_id: kill_id, reason: :fetch_failed}
        end
      end)

    # Group by reason and format for JSON
    grouped_analysis =
      Enum.group_by(kills_info, fn %{reason: reason} -> reason end)
      |> Enum.map(fn {reason, kills} ->
        %{
          reason: reason,
          count: length(kills),
          examples: Enum.map(kills, fn %{kill_id: id} -> id end)
        }
      end)

    {:ok, grouped_analysis}
  end

  @doc """
  Compare killmails for a character from the last 24 hours against our database.
  Returns a map containing:
  - our_kills: number of kills in our database
  - zkill_kills: number of kills on zKillboard
  - missing_kills: list of kill IDs found on zKillboard but not in our database
  - extra_kills: list of kill IDs found in our database but not on zKillboard
  - comparison: statistics about the comparison
  """
  def compare_recent_killmails(character_id) when is_integer(character_id) do
    # Get kills from zKillboard - it already returns recent kills
    case ZKillboardApi.get_character_kills(character_id) do
      {:ok, zkill_kills} ->
        # Log the raw zkill response for debugging
        AppLogger.processor_info("Raw ZKillboard response", %{
          character_id: character_id,
          total_kills: length(zkill_kills),
          first_kill: List.first(zkill_kills),
          last_kill: List.last(zkill_kills)
        })

        # Get our database kills for comparison
        our_kills = get_our_kills(character_id)

        # Log raw database kills
        AppLogger.processor_info("Raw database kills", %{
          character_id: character_id,
          total_kills: length(our_kills),
          first_kill: if(length(our_kills) > 0, do: List.first(our_kills), else: nil),
          last_kill: if(length(our_kills) > 0, do: List.last(our_kills), else: nil)
        })

        # Filter zkill kills to last 24 hours
        now = DateTime.utc_now()
        yesterday = DateTime.add(now, -24 * 60 * 60, :second)

        AppLogger.processor_info("Time window", %{
          now: now,
          yesterday: yesterday,
          now_iso: DateTime.to_iso8601(now),
          yesterday_iso: DateTime.to_iso8601(yesterday)
        })

        filtered_zkill_kills =
          zkill_kills
          |> Enum.filter(fn kill ->
            # Log each kill's time before parsing
            AppLogger.processor_debug("Processing kill", %{
              kill_id: kill["killmail_id"],
              raw_time: kill["killmail_time"]
            })

            case DateTime.from_iso8601(kill["killmail_time"]) do
              {:ok, kill_time, _} ->
                comparison = DateTime.compare(kill_time, yesterday)
                comparison in [:gt, :eq]

              error ->
                AppLogger.processor_error("Failed to parse kill time", %{
                  kill_id: kill["killmail_id"],
                  kill_time: kill["killmail_time"],
                  error: inspect(error)
                })

                false
            end
          end)

        # Convert our kills to a map for easier lookup
        our_kill_map = Map.new(our_kills, fn kill -> {kill.killmail_id, kill} end)

        # Find missing and extra kills
        {missing_kills, extra_kills} =
          analyze_kill_differences(filtered_zkill_kills, our_kill_map)

        # Calculate statistics
        our_kill_count = map_size(our_kill_map)
        zkill_kill_count = length(filtered_zkill_kills)
        missing_count = length(missing_kills)
        extra_count = length(extra_kills)

        # Calculate percentage match and analysis
        {percentage_match, analysis} =
          calculate_match_stats(our_kill_count, zkill_kill_count, missing_count, extra_count)

        {:ok,
         %{
           our_kills: our_kill_count,
           zkill_kills: zkill_kill_count,
           missing_kills: missing_kills,
           extra_kills: extra_kills,
           comparison: %{
             total_difference: missing_count + extra_count,
             percentage_match: percentage_match,
             analysis: analysis
           }
         }}

      {:error, reason} ->
        AppLogger.processor_error("Failed to fetch ZKillboard kills", %{
          character_id: character_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private functions

  defp get_our_kills(character_id) do
    query =
      Killmail
      |> filter(related_character_id == ^character_id)

    case Api.read(query) do
      {:ok, kills} -> kills
      _ -> []
    end
  end

  defp fetch_our_kills(character_id, start_date, end_date) do
    query =
      Killmail
      |> filter(related_character_id == ^character_id)
      |> filter(kill_time >= ^start_date)
      |> filter(kill_time <= ^end_date)

    case Api.read(query) do
      {:ok, kills} ->
        {:ok, kills}

      error ->
        AppLogger.processor_error("Error fetching our kills",
          error: inspect(error),
          character_id: character_id
        )

        error
    end
  end

  defp fetch_zkill_kills(character_id, start_date, end_date) do
    # Get all recent kills for the character - no date parameters as ZKill API doesn't use them anymore
    case WandererNotifier.Services.ZKillboardApi.get_character_kills(character_id) do
      {:ok, kills} ->
        Logger.info("Got #{length(kills)} kills from ZKillboard")

        # For each kill, check date first, then fetch ESI data only if needed
        filtered_kills =
          kills
          |> Task.async_stream(
            fn kill ->
              # First check if we have this kill cached
              cache_key = "esi:killmail:#{kill["killmail_id"]}"

              case WandererNotifier.Data.Cache.Repository.get(cache_key) do
                nil ->
                  # Not in cache, fetch from ESI
                  case WandererNotifier.Api.ESI.Service.get_killmail(
                         kill["killmail_id"],
                         get_in(kill, ["zkb", "hash"])
                       ) do
                    {:ok, esi_data} ->
                      # Cache the ESI data for 24 hours
                      WandererNotifier.Data.Cache.Repository.set(cache_key, esi_data, 86_400)

                      # Check if this kill is in our date range
                      case DateTime.from_iso8601(esi_data["killmail_time"]) do
                        {:ok, kill_date, _} ->
                          if DateTime.compare(kill_date, start_date) in [:gt, :eq] and
                               DateTime.compare(kill_date, end_date) in [:lt, :eq] do
                            {:ok, Map.merge(kill, esi_data)}
                          else
                            :skip
                          end

                        error ->
                          Logger.error(
                            "Failed to parse kill time for #{kill["killmail_id"]}: #{inspect(error)}"
                          )

                          :skip
                      end

                    {:error, reason} ->
                      Logger.error(
                        "Failed to get ESI data for kill #{kill["killmail_id"]}: #{inspect(reason)}"
                      )

                      :skip
                  end

                esi_data ->
                  # Found in cache, check date range
                  case DateTime.from_iso8601(esi_data["killmail_time"]) do
                    {:ok, kill_date, _} ->
                      if DateTime.compare(kill_date, start_date) in [:gt, :eq] and
                           DateTime.compare(kill_date, end_date) in [:lt, :eq] do
                        {:ok, Map.merge(kill, esi_data)}
                      else
                        :skip
                      end

                    error ->
                      Logger.error(
                        "Failed to parse cached kill time for #{kill["killmail_id"]}: #{inspect(error)}"
                      )

                      :skip
                  end
              end
            end,
            max_concurrency: 5,
            timeout: 30_000
          )
          |> Stream.filter(fn
            {:ok, {:ok, _kill}} -> true
            _ -> false
          end)
          |> Stream.map(fn {:ok, {:ok, kill}} -> kill end)
          |> Enum.to_list()

        {:ok, filtered_kills}

      error ->
        AppLogger.processor_error("Error fetching kills from ZKill", %{
          error: inspect(error),
          character_id: character_id
        })

        error
    end
  end

  defp calculate_comparison_stats(our_kills, zkill_kills, missing_kills, extra_kills) do
    our_count = MapSet.size(our_kills)
    zkill_count = MapSet.size(zkill_kills)
    missing_count = MapSet.size(missing_kills)
    extra_count = MapSet.size(extra_kills)

    # Calculate percentage match
    max_kills = max(our_count, zkill_count)

    percentage_match =
      if max_kills > 0 do
        matching_kills = zkill_count - missing_count
        Float.round(matching_kills / max_kills * 100, 2)
      else
        100.0
      end

    # Generate analysis
    analysis = generate_analysis(our_count, zkill_count, missing_count, extra_count)

    %{
      total_difference: abs(our_count - zkill_count),
      percentage_match: percentage_match,
      analysis: analysis
    }
  end

  defp generate_analysis(our_count, zkill_count, missing_count, extra_count) do
    cond do
      our_count == zkill_count and missing_count == 0 and extra_count == 0 ->
        "Perfect match - all kills are accounted for"

      missing_count > 0 and extra_count == 0 ->
        "Missing kills only - we're not capturing all kills"

      missing_count == 0 and extra_count > 0 ->
        "Extra kills only - we have kills that zKill doesn't"

      missing_count > 0 and extra_count > 0 ->
        "Both missing and extra kills - potential processing issues"

      true ->
        "Unexpected state - needs investigation"
    end
  end

  defp analyze_kill_miss_reason(kill_data, character_id) do
    Logger.info(
      "TEST LOG - Analyzing kill #{kill_data["killmail_id"]} for character #{character_id}"
    )

    # Log the full kill data structure for debugging
    AppLogger.processor_info("Full kill data for analysis", %{
      character_id: character_id,
      kill_id: kill_data["killmail_id"],
      kill_time: kill_data["killmail_time"],
      victim_data: %{
        character_id: get_in(kill_data, ["victim", "character_id"]),
        ship_type_id: get_in(kill_data, ["victim", "ship_type_id"]),
        category_id: get_in(kill_data, ["victim", "category_id"])
      },
      attackers:
        Enum.map(kill_data["attackers"] || [], fn attacker ->
          %{
            character_id: attacker["character_id"],
            ship_type_id: attacker["ship_type_id"]
          }
        end),
      zkb_data: get_in(kill_data, ["zkb"])
    })

    # Check each condition in sequence and return the first matching reason
    cond do
      # First check if the character is found in the kill - if found, it's valid
      !not_in_attackers_or_victim?(kill_data, character_id) ->
        AppLogger.processor_info("Kill classified as valid - character found", %{
          kill_id: kill_data["killmail_id"],
          character_id: character_id
        })

        :valid_kill

      # Check if the kill is too old (might have been before tracking started)
      is_old_kill?(kill_data) ->
        AppLogger.processor_info("Kill classified as too old", %{
          kill_id: kill_data["killmail_id"],
          kill_time: kill_data["killmail_time"]
        })

        :kill_too_old

      # Check if it's an NPC kill
      get_in(kill_data, ["zkb", "npc"]) == true ->
        AppLogger.processor_info("Kill classified as NPC kill", %{
          kill_id: kill_data["killmail_id"],
          zkb_data: get_in(kill_data, ["zkb"])
        })

        :npc_kill

      # Check if it's a structure kill
      is_structure_kill?(kill_data) ->
        AppLogger.processor_info("Kill classified as structure kill", %{
          kill_id: kill_data["killmail_id"],
          victim_category: get_in(kill_data, ["victim", "category_id"])
        })

        :structure_kill

      # Check if it's a pod kill
      is_pod_kill?(kill_data) ->
        AppLogger.processor_info("Kill classified as pod kill", %{
          kill_id: kill_data["killmail_id"],
          victim_ship_type: get_in(kill_data, ["victim", "ship_type_id"])
        })

        :pod_kill

      # Default case
      true ->
        AppLogger.processor_info("Kill classified as unknown reason", %{
          kill_id: kill_data["killmail_id"]
        })

        :unknown_reason
    end
  end

  defp is_old_kill?(kill_data) do
    case kill_data["killmail_time"] do
      nil ->
        false

      time ->
        kill_time = DateTime.from_iso8601(time)
        cutoff_date = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

        case kill_time do
          {:ok, datetime, _} -> DateTime.compare(datetime, cutoff_date) == :lt
          _ -> false
        end
    end
  end

  defp is_structure_kill?(kill_data) do
    victim = kill_data["victim"] || %{}
    # Structure categories in EVE
    # 65 is the structure category
    structure_categories = [65]
    victim["category_id"] in structure_categories
  end

  defp is_pod_kill?(kill_data) do
    victim = kill_data["victim"] || %{}
    # 670 is the Capsule (pod) type ID
    victim["ship_type_id"] == 670
  end

  defp not_in_attackers_or_victim?(kill_data, character_id) do
    str_char_id = to_string(character_id)

    # Check victim
    victim = kill_data["victim"] || %{}
    victim_id = victim["character_id"]
    victim_match = to_string(victim_id) == str_char_id

    # Log victim details
    Logger.info(
      "VICTIM CHECK - Kill #{kill_data["killmail_id"]} - Victim ID: #{victim_id}, Character ID: #{character_id}, Match: #{victim_match}"
    )

    # Check attackers
    attackers = kill_data["attackers"] || []

    # Log each attacker check
    attacker_match =
      Enum.any?(attackers, fn attacker ->
        attacker_char_id = attacker["character_id"]
        str_attacker_id = if(attacker_char_id, do: to_string(attacker_char_id), else: nil)
        is_match = str_attacker_id == str_char_id

        Logger.info(
          "ATTACKER CHECK - Kill #{kill_data["killmail_id"]} - Attacker ID: #{attacker_char_id}, Character ID: #{character_id}, Match: #{is_match}"
        )

        is_match
      end)

    Logger.info(
      "FINAL CHECK - Kill #{kill_data["killmail_id"]} - Character #{character_id} - Victim Match: #{victim_match}, Attacker Match: #{attacker_match}, Total Attackers: #{length(attackers)}"
    )

    not (victim_match or attacker_match)
  end

  # Private helper to analyze differences between zkill and our kills
  defp analyze_kill_differences(zkill_kills, our_kill_map) do
    # Find missing kills (in zKill but not in our DB)
    missing_kills =
      zkill_kills
      |> Enum.filter(fn kill -> !Map.has_key?(our_kill_map, kill["killmail_id"]) end)
      |> Enum.map(fn kill -> kill["killmail_id"] end)

    # Find extra kills (in our DB but not in zKill)
    zkill_kill_ids = MapSet.new(zkill_kills, & &1["killmail_id"])

    extra_kills =
      our_kill_map
      |> Map.keys()
      |> Enum.filter(fn kill_id -> !MapSet.member?(zkill_kill_ids, kill_id) end)

    {missing_kills, extra_kills}
  end

  # Private helper to calculate match statistics
  defp calculate_match_stats(our_count, _zkill_count, missing_count, extra_count) do
    # Total unique kills across both sources
    total_unique = our_count + missing_count
    # Kills that match between sources
    matched = our_count - extra_count

    percentage_match =
      if total_unique > 0 do
        matched / total_unique * 100
      else
        100.0
      end

    analysis =
      cond do
        percentage_match == 100.0 ->
          "Perfect match between our database and zKillboard"

        percentage_match > 90.0 ->
          "Very good coverage, only a few kills missing"

        percentage_match > 75.0 ->
          "Good coverage but some kills are missing"

        percentage_match > 50.0 ->
          "Moderate coverage, significant number of kills missing"

        true ->
          "Poor coverage, most kills are missing"
      end

    {percentage_match, analysis}
  end
end
