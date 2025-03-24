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
      start_date: inspect(start_date),
      end_date: inspect(end_date),
      start_type: start_date.__struct__,
      end_type: end_date.__struct__
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
            # Add basic analysis of why we might have missed it
            analysis = analyze_kill_miss_reason(kill_data, character_id)
            {kill_id, analysis}

          _ ->
            {kill_id, :fetch_failed}
        end
      end)

    # Group by reason
    grouped_analysis = Enum.group_by(kills_info, fn {_id, reason} -> reason end)

    {:ok, grouped_analysis}
  end

  # Private functions

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
    # Step by step error handling to identify the exact failure point
    try do
      # Step 1: Log initial date values with more detail
      AppLogger.processor_info("Processing dates for zKill fetch", %{
        start_date: inspect(start_date),
        end_date: inspect(end_date),
        start_date_type: if(start_date, do: start_date.__struct__, else: "nil"),
        end_date_type: if(end_date, do: end_date.__struct__, else: "nil"),
        start_date_fields: if(start_date, do: Map.from_struct(start_date), else: "nil"),
        end_date_fields: if(end_date, do: Map.from_struct(end_date), else: "nil")
      })

      # Step 2: Ensure we have valid DateTime structs
      unless start_date.__struct__ == DateTime and end_date.__struct__ == DateTime do
        raise ArgumentError, "Invalid DateTime struct received"
      end

      # Step 3: Format the dates for zKill API
      start_str = format_datetime_for_zkill(start_date)
      end_str = format_datetime_for_zkill(end_date)

      AppLogger.processor_debug("Formatted dates for zKill", %{
        start_str: start_str,
        end_str: end_str,
        start_str_length: String.length(start_str),
        end_str_length: String.length(end_str)
      })

      # Step 4: Make the API call
      case ZKillboardApi.get_character_kills(character_id, start_str, end_str) do
        {:ok, kills} ->
          AppLogger.processor_info("Successfully fetched kills from zKill", %{
            character_id: character_id,
            kill_count: length(kills)
          })

          {:ok, kills}

        {:error, :invalid_date_format} ->
          AppLogger.processor_error("Invalid date format for zKill API", %{
            character_id: character_id,
            start_str: start_str,
            end_str: end_str
          })

          {:error, "Invalid date format for zKill API"}

        {:error, reason} = error ->
          AppLogger.processor_error("Error fetching zKill kills", %{
            error: inspect(reason),
            character_id: character_id,
            start_str: start_str,
            end_str: end_str
          })

          error
      end
    rescue
      e ->
        # Get detailed error information
        error_info = %{
          message: Exception.message(e),
          module: e.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__),
          start_date: if(start_date, do: inspect(start_date), else: "nil"),
          end_date: if(end_date, do: inspect(end_date), else: "nil"),
          start_type: if(start_date, do: start_date.__struct__, else: "unknown"),
          end_type: if(end_date, do: end_date.__struct__, else: "unknown")
        }

        AppLogger.processor_error("Date processing failed", error_info)
        {:error, "Date processing failed: #{error_info.message}"}
    end
  end

  # Helper function to format DateTime for zKill API
  defp format_datetime_for_zkill(%DateTime{} = dt) do
    AppLogger.processor_debug("Formatting DateTime for zKill", %{
      datetime: inspect(dt),
      fields: %{
        year: dt.year,
        month: dt.month,
        day: dt.day,
        hour: dt.hour,
        minute: dt.minute
      }
    })

    formatted =
      "#{dt.year}#{pad_number(dt.month)}#{pad_number(dt.day)}#{pad_number(dt.hour)}#{pad_number(dt.minute)}"

    AppLogger.processor_debug("Formatted result", %{formatted: formatted})
    formatted
  end

  # Helper function to pad numbers with leading zeros
  defp pad_number(number) when number < 10, do: "0#{number}"
  defp pad_number(number), do: "#{number}"

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
    # Check each condition in sequence and return the first matching reason
    cond do
      # Check if the kill is too old (might have been before tracking started)
      is_old_kill?(kill_data) ->
        :kill_too_old

      # Check if it's an NPC kill
      get_in(kill_data, ["zkb", "npc"]) == true ->
        :npc_kill

      # Check if it's a structure kill
      is_structure_kill?(kill_data) ->
        :structure_kill

      # Check if the character is not found in the kill
      not_in_attackers_or_victim?(kill_data, character_id) ->
        :character_not_found

      # Check if it's a pod kill (some might be configured to ignore these)
      is_pod_kill?(kill_data) ->
        :pod_kill

      # Default case
      true ->
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
    victim_id = get_in(kill_data, ["victim", "character_id"])
    victim_match = to_string(victim_id) == str_char_id

    # Check attackers
    attackers = get_in(kill_data, ["attackers"]) || []

    attacker_match =
      Enum.any?(attackers, fn attacker ->
        to_string(attacker["character_id"]) == str_char_id
      end)

    not (victim_match or attacker_match)
  end
end
