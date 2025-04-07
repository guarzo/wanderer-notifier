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
  alias WandererNotifier.Data.Repository, as: DataRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  require Ash.Query, as: Query

  # EVE Online constants and IDs
  @structure_category_id 65
  @deployable_category_id 22
  @pod_type_id 670

  # Known structure/deployable group IDs
  @structure_group_ids [
    1657,
    1404,
    1406,
    365,
    297,
    1025,
    1876,
    1677,
    1927,
    1980
  ]

  @deployable_group_ids [
    361,
    363,
    715,
    1022,
    1247,
    1249,
    1246,
    1248,
    1201,
    1297,
    1275
  ]

  # Keep a small in-process cache to avoid repeated structure checks
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

  @doc """
  Sends a manual test for weekly kill highlights, using a 7-day date range.
  """
  def send_test_highlights do
    AppLogger.scheduler_info("Sending test weekly kill highlights")

    channel_id = config_module().discord_channel_id_for(:kill_charts)

    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for test kill charts")
      {:error, "No channel ID configured"}
    else
      now = DateTime.utc_now()
      # 7 days
      days_ago = DateTime.add(now, -7 * 86_400, :second)

      AppLogger.scheduler_info(
        "Test kill highlights using date range: #{DateTime.to_string(days_ago)} to #{DateTime.to_string(now)}"
      )

      # Optional: Log basic DB diagnostics
      log_weekly_diagnostics(days_ago, now)

      # Now run highlights in that date range
      try do
        case process_weekly_highlights_with_date_range(channel_id, days_ago, now) do
          {:ok, _} = result ->
            AppLogger.scheduler_info("Successfully sent test kill highlights")
            result

          {:error, reason} = error ->
            AppLogger.scheduler_error("Failed to send test kill highlights: #{inspect(reason)}")
            error
        end
      rescue
        e ->
          AppLogger.scheduler_error("Exception sending test kill charts: #{Exception.message(e)}")
          {:error, "Exception: #{Exception.message(e)}"}
      end
    end
  end

  defp process_weekly_highlights(channel_id) do
    now = DateTime.utc_now()
    week_ago = DateTime.add(now, -7 * 86_400, :second)
    process_weekly_highlights_with_date_range(channel_id, week_ago, now)
  end

  defp process_weekly_highlights_with_date_range(channel_id, start_date, end_date) do
    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for kill charts")
      {:error, "No channel ID configured"}
    else
      date_range_str = format_date_range(start_date, end_date)
      AppLogger.scheduler_info("Processing kill highlights for period: #{date_range_str}")

      # Best kill
      best_kill_result = find_best_kill(start_date, end_date)
      kills_sent = maybe_send_highlight(best_kill_result, channel_id, true, date_range_str)

      # Worst loss
      worst_loss_result = find_worst_loss(start_date, end_date)
      losses_sent = maybe_send_highlight(worst_loss_result, channel_id, false, date_range_str)

      total_sent = kills_sent + losses_sent

      if total_sent > 0 do
        AppLogger.scheduler_info("Successfully sent #{total_sent} kill highlight notifications")
        {:ok, :sent}
      else
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

  # ----------------------------------------------------------------
  # Kill finding logic (best kill, worst loss)
  # ----------------------------------------------------------------

  defp find_best_kill(start_date, end_date) do
    find_significant_killmail(start_date, end_date, :attacker, "best kill")
  end

  defp find_worst_loss(start_date, end_date) do
    find_significant_killmail(start_date, end_date, :victim, "worst loss")
  end

  defp find_significant_killmail(start_date, end_date, character_role, description) do
    AppLogger.scheduler_info(
      "Searching for #{description} between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    # Get tracked IDs
    all_tracked_ids = get_tracked_character_ids()
    AppLogger.scheduler_info("Retrieved #{length(all_tracked_ids)} tracked character IDs")

    if all_tracked_ids == [] do
      AppLogger.scheduler_warn("No tracked characters found, cannot search for #{description}")
      {:error, :no_tracked_characters}
    else
      # Query
      case query_killmails_for_period(start_date, end_date, character_role) do
        {:ok, []} ->
          AppLogger.scheduler_warn("No #{character_role}s found in the date range")
          {:error, :no_results_in_range}

        {:ok, killmails} ->
          # Filter to tracked & exclude structures
          filtered = filter_tracked_killmails(killmails, all_tracked_ids, character_role)
          deduped = deduplicate_killmails(filtered, character_role)

          # Log post-filter/dedup
          AppLogger.scheduler_info(
            "Found #{length(deduped)} unique killmails for #{description} after filtering"
          )

          # Keep only killmails with a total value
          valued_killmails =
            Enum.filter(deduped, fn km -> not is_nil(km.total_value) end)

          if valued_killmails == [] do
            AppLogger.scheduler_warn("No killmails with valid total_value found")
            {:error, :no_kills_with_value}
          else
            best_km = pick_highest_value_killmail(valued_killmails)

            AppLogger.scheduler_debug("""
            FULL #{String.upcase(description)} KILLMAIL:
            #{inspect(best_km, pretty: true, limit: :infinity)}
            """)

            # Enrich missing data
            enriched = enrich_killmail_data(best_km)
            log_selected_killmail(enriched, description)

            {:ok, enriched}
          end

        error ->
          AppLogger.scheduler_error(
            "Error querying #{character_role}s in date range: #{inspect(error)}"
          )

          {:error, "Failed to find #{character_role}s in date range"}
      end
    end
  end

  defp query_killmails_for_period(start_date, end_date, character_role) do
    query =
      Killmail
      |> Query.filter(character_role == ^character_role)
      |> Query.filter(kill_time >= ^start_date)
      |> Query.filter(kill_time <= ^end_date)
      # Exclude pods
      |> Query.filter(ship_type_id != ^@pod_type_id)
      |> Query.sort(total_value: :desc)
      |> Query.limit(100)

    Api.read(query)
  end

  # Filter killmails to only include those from tracked characters
  # and exclude structures/deployables.
  defp filter_tracked_killmails(killmails, tracked_ids, character_role) do
    Enum.filter(killmails, fn km ->
      char_id = parse_to_int(km.related_character_id)
      is_tracked = char_id in tracked_ids
      is_structure = structure_or_deployable?(ship_type_for_role(km, character_role))

      unless is_tracked do
        AppLogger.scheduler_debug(
          "Character #{char_id} is not tracked — ignoring killmail #{km.killmail_id}"
        )
      end

      if is_structure do
        role_msg = if character_role == :victim, do: "Lost structure", else: "Structure kill"
        AppLogger.scheduler_debug("#{role_msg} — ignoring killmail #{km.killmail_id}")
      end

      is_tracked and not is_structure
    end)
  end

  # Determine the relevant ship type ID for the killmail based on role (victim or attacker).
  defp ship_type_for_role(killmail, :victim), do: killmail.ship_type_id

  defp ship_type_for_role(killmail, :attacker) do
    # For an attacker killmail, the "ship" is the victim's ship
    case killmail.victim_data do
      %{"ship_type_id" => victim_ship} -> victim_ship
      _ -> nil
    end
  end

  # Deduplicate killmails by killmail_id, picking a single record if multiple tracked chars are involved.
  defp deduplicate_killmails(killmails, character_role) do
    killmails
    |> Enum.group_by(& &1.killmail_id)
    |> Enum.map(fn {_, same_id_kms} ->
      if length(same_id_kms) > 1 do
        AppLogger.scheduler_info(
          "Multiple tracked characters for killmail #{List.first(same_id_kms).killmail_id}"
        )

        if character_role == :attacker do
          # For kills, pick the attacker with highest damage
          Enum.max_by(same_id_kms, &attacker_damage_done/1)
        else
          # For losses, just pick the first (rare scenario)
          List.first(same_id_kms)
        end
      else
        List.first(same_id_kms)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Extract damage from attacker_data
  defp attacker_damage_done(km) do
    with data when is_map(data) <- km.attacker_data do
      parse_to_int(Map.get(data, "damage_done")) || 0
    else
      _ -> 0
    end
  end

  defp pick_highest_value_killmail(killmails) do
    # First convert all values to Decimal for consistent comparison
    killmails_with_decimal_value =
      Enum.map(killmails, fn km ->
        decimal_value =
          case km.total_value do
            %Decimal{} = dec ->
              dec

            int when is_integer(int) ->
              Decimal.new(int)

            float when is_float(float) ->
              # Convert float to string first to preserve precision
              float |> Float.to_string() |> Decimal.new()

            str when is_binary(str) ->
              Decimal.new(str)

            _ ->
              Decimal.new(0)
          end

        {km, decimal_value}
      end)

    # Sort using Decimal.compare to avoid any float conversion
    {max_km, _} =
      Enum.reduce(killmails_with_decimal_value, {nil, nil}, fn {km, value}, {max_km, max_value} ->
        cond do
          is_nil(max_value) -> {km, value}
          Decimal.compare(value, max_value) == :gt -> {km, value}
          true -> {max_km, max_value}
        end
      end)

    max_km
  end

  defp log_selected_killmail(killmail, description) do
    AppLogger.scheduler_info(
      "Selected #{description}: " <>
        "ID=#{killmail.killmail_id}, " <>
        "Character=#{killmail.related_character_name || "Unknown"}, " <>
        "Ship=#{killmail.ship_type_name || "Unknown"}, " <>
        "System=#{killmail.solar_system_name || "Unknown"}, " <>
        "Region=#{killmail.region_name || "Unknown"}, " <>
        "Value=#{inspect(killmail.total_value)}, " <>
        "Time=#{DateTime.to_string(killmail.kill_time)}"
    )
  end

  # ----------------------------------------------------------------
  # Notification sending logic
  # ----------------------------------------------------------------

  defp maybe_send_highlight({:ok, killmail}, channel_id, is_kill, date_range_str) do
    AppLogger.scheduler_info(
      "Sending #{if is_kill, do: "best kill", else: "worst loss"} notification"
    )

    embed = format_kill_embed(killmail, is_kill, date_range_str)
    NotifierFactory.notify(:send_discord_embed_to_channel, [channel_id, embed])
    1
  end

  defp maybe_send_highlight({:error, reason}, _channel_id, is_kill, _date_range_str) do
    msg =
      if is_kill,
        do: "Unable to send best kill notification: #{inspect(reason)}",
        else: "Unable to send worst loss notification: #{inspect(reason)}"

    AppLogger.scheduler_warn(msg)
    0
  end

  # ----------------------------------------------------------------
  # Data enrichment helpers
  # ----------------------------------------------------------------

  defp enrich_killmail_data(km) do
    # Resolve missing character name
    km = maybe_resolve_character_name(km)

    # Resolve ship name if missing
    km = maybe_fix_ship_name(km)

    # Resolve system name if missing
    km = maybe_fix_system_name(km)

    km
  end

  # Resolve character name if it's "Unknown"
  defp maybe_resolve_character_name(km) do
    cond do
      is_nil(km.related_character_name) or
          String.starts_with?(to_string(km.related_character_name), "Unknown") ->
        # Attempt to resolve from ESI or from killmail data
        try_alternative_name_sources(km)

      true ->
        km
    end
  end

  # Attempt to look up name from ESI or killmail data (victim/attacker)
  defp try_alternative_name_sources(km) do
    # If we have an ID, see if we can get a better name
    cond do
      not is_nil(km.related_character_id) ->
        case lookup_character_name(km.related_character_id) do
          {:ok, name} ->
            %{km | related_character_name: name}

          {:error, _} ->
            fallback_name_from_killmail_data(km)
        end

      true ->
        fallback_name_from_killmail_data(km)
    end
  end

  # Fallback to victim/attacker data
  defp fallback_name_from_killmail_data(km) do
    case {km.character_role, km.victim_data, km.attacker_data} do
      {:attacker, %{"character_name" => victim_name}, _} when is_binary(victim_name) ->
        %{km | related_character_name: victim_name}

      {:victim, %{"character_name" => victim_name}, _} when is_binary(victim_name) ->
        %{km | related_character_name: victim_name}

      {_, _, %{"character_name" => attacker_name}} when is_binary(attacker_name) ->
        %{km | related_character_name: attacker_name}

      _ ->
        %{km | related_character_name: "Unknown Pilot"}
    end
  end

  # Fix missing or unknown ship names for losses
  defp maybe_fix_ship_name(km) do
    cond do
      km.character_role == :victim and is_nil(km.ship_type_name) and is_map(km.victim_data) ->
        victim_ship = Map.get(km.victim_data, "ship_type_name")
        %{km | ship_type_name: victim_ship || "Unknown Ship"}

      km.ship_type_name == "Unknown Ship" and is_map(km.victim_data) ->
        victim_ship = Map.get(km.victim_data, "ship_type_name")
        %{km | ship_type_name: victim_ship || "Unknown Ship"}

      true ->
        km
    end
  end

  # Fix system name if it is "Unknown System" or nil, using system ID
  defp maybe_fix_system_name(km) do
    if (is_nil(km.solar_system_name) or km.solar_system_name == "Unknown System") and
         is_integer(km.solar_system_id) do
      # Could be a wormhole J#### system
      system_name = "J#{km.solar_system_id}"
      %{km | solar_system_name: system_name}
    else
      km
    end
  end

  # ----------------------------------------------------------------
  # Character name lookup
  # ----------------------------------------------------------------

  defp lookup_character_name(character_id) when not is_nil(character_id) do
    # Check repository cache first
    case DataRepo.get_character_name(character_id) do
      {:ok, name} when is_binary(name) and name not in ["", "Unknown"] ->
        AppLogger.scheduler_info("[NAME_LOOKUP] Found character name in repo cache", %{
          character_id: character_id,
          character_name: name
        })

        {:ok, name}

      _ ->
        # Fallback to ESI
        AppLogger.scheduler_info("[NAME_LOOKUP] Looking up character name in ESI", %{
          character_id: character_id
        })

        case EsiService.get_character(character_id) do
          {:ok, %{"name" => resolved}} when is_binary(resolved) and resolved != "" ->
            CacheHelpers.cache_character_info(%{
              "character_id" => character_id,
              "name" => resolved
            })

            AppLogger.scheduler_info("[NAME_LOOKUP] Successfully resolved via ESI", %{
              character_id: character_id,
              character_name: resolved
            })

            {:ok, resolved}

          other ->
            AppLogger.scheduler_warn("[NAME_LOOKUP] Failed to get name from ESI", %{
              character_id: character_id,
              error: inspect(other)
            })

            {:error, :esi_failed}
        end
    end
  end

  defp lookup_character_name(_), do: {:error, :nil_character_id}

  # ----------------------------------------------------------------
  # Discord embed formatting
  # ----------------------------------------------------------------

  defp format_kill_embed(killmail, is_kill, date_range) do
    system_name = format_system_name(killmail)
    region_name = format_region_name(system_name, killmail.region_name)
    character_name = resolve_embed_character_name(killmail, is_kill)
    ship_name = resolve_embed_ship_name(killmail, is_kill)
    formatted_isk = format_isk_compact(killmail.total_value)
    zkill_url = "https://zkillboard.com/kill/#{killmail.killmail_id}/"
    color = if is_kill, do: 0x00FF00, else: 0xFF0000
    {title, desc} = embed_title_desc(character_name, is_kill)

    # Build initial fields
    fields = [
      %{"name" => "Value", "value" => formatted_isk, "inline" => true},
      %{"name" => "Ship", "value" => ship_name, "inline" => true},
      %{"name" => "Location", "value" => system_name, "inline" => true}
    ]

    embed = %{
      "title" => title,
      "description" => desc,
      "color" => color,
      "fields" => fields,
      "footer" => %{"text" => "Week of #{date_range}"},
      "timestamp" => DateTime.to_iso8601(killmail.kill_time),
      "url" => zkill_url
    }

    # Add details if any
    details_info = gather_details_info(killmail, is_kill)
    embed = maybe_add_details(embed, details_info)

    # Add ship thumbnail
    embed = maybe_add_thumbnail(embed, killmail, is_kill)

    # Logging
    AppLogger.scheduler_info(
      "Generated #{if is_kill, do: "kill", else: "loss"} embed: " <>
        "Title=\"#{title}\", Character=#{character_name}, " <>
        "Ship=#{ship_name}, System=#{system_name}, Region=#{region_name}, " <>
        "Fields=#{length(embed["fields"])}, " <>
        "Has thumbnail=#{Map.has_key?(embed, "thumbnail")}"
    )

    embed
  end

  defp embed_title_desc(character_display, true),
    do:
      {"🏆 Best Kill of the Week", "#{character_display} scored our most valuable kill this week!"}

  defp embed_title_desc(character_display, false),
    do:
      {"💀 Worst Loss of the Week",
       "#{character_display} suffered our most expensive loss this week."}

  defp resolve_embed_character_name(km, is_kill) do
    cond do
      # If we have a real name, just use it
      is_binary(km.related_character_name) -> km.related_character_name
      # Otherwise fallback
      true -> if is_kill, do: "Unknown Killer", else: "Unknown Pilot"
    end
  end

  defp resolve_embed_ship_name(km, is_kill) do
    case {is_kill, km.ship_type_name, km.victim_data} do
      # If this is a "kill" embed, the "ship" is the victim's
      {true, _, %{"ship_type_name" => victim_ship}} when is_binary(victim_ship) ->
        victim_ship

      {true, ship, nil} when is_binary(ship) ->
        ship || "Unknown Ship"

      # For "loss" embed, we usually have the killmail's own ship_type_name
      {false, ship_type_name, _} when is_binary(ship_type_name) ->
        ship_type_name

      _ ->
        "Unknown Ship"
    end
  end

  # Optional additional details block
  defp gather_details_info(km, true) do
    # For kills, we can mention victim ship and corp, plus attacker stats
    if is_map(km.victim_data) do
      victim_ship = Map.get(km.victim_data, "ship_type_name", "Unknown Ship")
      victim_corp = Map.get(km.victim_data, "corporation_name", "Unknown Corp")
      attackers_count = attacker_count(km.attacker_data)

      "Destroyed a #{victim_ship} from #{victim_corp}\nTotal attackers: #{attackers_count}"
    else
      nil
    end
  end

  defp gather_details_info(km, false) do
    # For losses, mention main attacker's ship/corp if known
    if is_map(km.attacker_data) do
      main_ship = Map.get(km.attacker_data, "ship_type_name", "Unknown Ship")
      main_corp = Map.get(km.attacker_data, "corporation_name", "Unknown Corp")
      attackers_count = attacker_count(km.attacker_data)

      "Killed by #{main_ship} from #{main_corp}\nTotal attackers: #{attackers_count}"
    else
      nil
    end
  end

  defp attacker_count(attacker_data) do
    cond do
      is_map(attacker_data) ->
        Map.get(attacker_data, "attackers_count", "Unknown")

      true ->
        "Unknown"
    end
  end

  # Insert the optional "details" field into the embed
  defp maybe_add_details(embed, nil), do: embed

  defp maybe_add_details(embed, info) do
    new_fields = embed["fields"] ++ [%{"name" => "Details", "value" => info, "inline" => false}]
    %{embed | "fields" => new_fields}
  end

  # Insert thumbnail if possible
  defp maybe_add_thumbnail(embed, km, true) do
    # For kills, try victim ship image
    ship_id = Map.get(km.victim_data || %{}, "ship_type_id")

    if ship_id do
      thumb_url = "https://images.evetech.net/types/#{ship_id}/render?size=128"
      Map.put(embed, "thumbnail", %{"url" => thumb_url})
    else
      embed
    end
  end

  defp maybe_add_thumbnail(embed, km, false) do
    # For losses, use killmail's own ship_type_id
    ship_id = km.ship_type_id

    if ship_id do
      thumb_url = "https://images.evetech.net/types/#{ship_id}/render?size=128"
      Map.put(embed, "thumbnail", %{"url" => thumb_url})
    else
      embed
    end
  end

  # ----------------------------------------------------------------
  # Utility & data formatting
  # ----------------------------------------------------------------

  defp format_system_name(km) do
    case km.solar_system_name do
      nil ->
        if is_integer(km.solar_system_id), do: "J#{km.solar_system_id}", else: "Unknown System"

      "Unknown System" ->
        if is_integer(km.solar_system_id), do: "J#{km.solar_system_id}", else: "Unknown System"

      name ->
        name
    end
  end

  defp format_region_name(system_name, region_name) do
    cond do
      # If it's a wormhole system name (starting with "J") and region is unknown
      String.starts_with?(system_name, "J") and
          (is_nil(region_name) or region_name == "Unknown Region") ->
        "J-Space"

      is_binary(region_name) and region_name != "" ->
        region_name

      true ->
        "Unknown Region"
    end
  end

  defp format_date_range(start_date, end_date) do
    start_str = Calendar.strftime(start_date, "%Y-%m-%d")
    end_str = Calendar.strftime(end_date, "%Y-%m-%d")
    "#{start_str} to #{end_str}"
  end

  defp format_isk_compact(nil), do: "Unknown"

  defp format_isk_compact(value) do
    # Handle Decimal values directly without converting to float
    cond do
      is_decimal(value) ->
        # For Decimal values, use Decimal arithmetic and then format as string
        billion = Decimal.new(1_000_000_000)
        million = Decimal.new(1_000_000)
        thousand = Decimal.new(1_000)

        cond do
          Decimal.compare(value, billion) in [:gt, :eq] ->
            # Value >= 1B
            value
            |> Decimal.div(billion)
            |> Decimal.round(2)
            |> Decimal.to_string()
            |> Kernel.<>("B ISK")

          Decimal.compare(value, million) in [:gt, :eq] ->
            # Value >= 1M
            value
            |> Decimal.div(million)
            |> Decimal.round(2)
            |> Decimal.to_string()
            |> Kernel.<>("M ISK")

          Decimal.compare(value, thousand) in [:gt, :eq] ->
            # Value >= 1K
            value
            |> Decimal.div(thousand)
            |> Decimal.round(2)
            |> Decimal.to_string()
            |> Kernel.<>("K ISK")

          true ->
            # Small value
            value
            |> Decimal.round(2)
            |> Decimal.to_string()
            |> Kernel.<>(" ISK")
        end

      # Handle non-Decimal values using the original flow
      true ->
        float_value = value_to_float(value)

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

  defp format_float(float), do: :erlang.float_to_binary(float, decimals: 2)

  defp value_to_float(value) do
    cond do
      is_float(value) -> value
      is_integer(value) -> value / 1.0
      is_binary(value) -> parse_binary_float(value)
      is_decimal(value) -> decimal_to_float(value)
      true -> 0.0
    end
  rescue
    _ -> 0.0
  end

  # Quick check if it's a Decimal
  defp is_decimal(v), do: is_map(v) and Map.get(v, :__struct__) == Decimal

  defp parse_binary_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp decimal_to_float(%Decimal{} = dec) do
    # First round the decimal to safely convert to float
    # then use Decimal.to_float which won't lose precision on rounded values
    dec
    # Use 2 decimal places instead of 0
    |> Decimal.round(2)
    |> Decimal.to_float()
  rescue
    e ->
      AppLogger.scheduler_warn("Error converting decimal to float: #{Exception.message(e)}")
      # Fall back to string conversion as a more robust approach
      dec
      |> Decimal.to_string()
      |> parse_binary_float()
  end

  defp parse_to_int(val) when is_integer(val), do: val

  defp parse_to_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_to_int(_), do: nil

  # ----------------------------------------------------------------
  # Tracked characters
  # ----------------------------------------------------------------

  defp get_tracked_character_ids do
    tracked_chars = DataRepo.get_tracked_characters()
    count = length(tracked_chars)

    AppLogger.scheduler_info("Retrieved #{count} tracked characters from repository cache")

    if count > 0 do
      # Log a sample
      AppLogger.scheduler_info("Sample tracked char: #{inspect(List.first(tracked_chars))}")

      ids = extract_character_ids_from_maps(tracked_chars)
      AppLogger.scheduler_info("Extracted #{length(ids)} valid IDs from cache")
      ids
    else
      AppLogger.scheduler_info("Cache returned no tracked chars, falling back to DB query")

      case query_tracked_characters_from_database() do
        {:ok, ids} when ids != [] ->
          AppLogger.scheduler_info("Found #{length(ids)} tracked chars in database")
          ids

        _ ->
          AppLogger.scheduler_warn("No tracked chars found in database either")
          []
      end
    end
  end

  defp extract_character_ids_from_maps(chars) do
    chars
    |> Enum.map(fn ch ->
      cond do
        is_map(ch) and Map.has_key?(ch, "character_id") ->
          parse_to_int(Map.get(ch, "character_id"))

        is_map(ch) and Map.has_key?(ch, :character_id) ->
          parse_to_int(Map.get(ch, :character_id))

        is_integer(ch) or is_binary(ch) ->
          parse_to_int(ch)

        true ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp query_tracked_characters_from_database do
    AppLogger.scheduler_info("Querying tracked_characters table directly")

    character_query =
      WandererNotifier.Resources.TrackedCharacter
      |> Query.select([:character_id])

    case WandererNotifier.Resources.Api.read(character_query) do
      {:ok, results} ->
        ids =
          results
          |> Enum.map(fn item ->
            parse_to_int(Map.get(item, :character_id))
          end)
          |> Enum.reject(&is_nil/1)

        AppLogger.scheduler_info("Successfully found #{length(ids)} tracked IDs in database")
        {:ok, ids}

      error ->
        AppLogger.scheduler_error("Error querying tracked_characters table: #{inspect(error)}")
        {:error, "Failed to query tracked characters from database"}
    end
  end

  # ----------------------------------------------------------------
  # Structure check & caching
  # ----------------------------------------------------------------

  defp structure_or_deployable?(nil), do: false

  defp structure_or_deployable?(ship_type_id) when is_integer(ship_type_id) do
    ensure_structure_cache_exists()

    cache = Process.get(@structure_types_cache_key)

    case Map.get(cache, ship_type_id) do
      nil -> check_and_cache_structure_type(ship_type_id)
      cached -> cached
    end
  end

  defp structure_or_deployable?(type_id) when is_binary(type_id) do
    case Integer.parse(type_id) do
      {int_id, _} -> structure_or_deployable?(int_id)
      :error -> false
    end
  end

  defp structure_or_deployable?(_), do: false

  defp ensure_structure_cache_exists do
    case Process.get(@structure_types_cache_key) do
      nil -> Process.put(@structure_types_cache_key, %{})
      _ -> :ok
    end
  end

  defp check_and_cache_structure_type(type_id) do
    case EsiService.get_type_info(type_id) do
      {:ok, %{"name" => _name, "group_id" => grp_id} = info} ->
        AppLogger.scheduler_debug(
          "Partial type info for #{type_id} with group_id #{grp_id}: #{inspect(info, limit: 200)}"
        )

        is_structure = grp_id in @structure_group_ids or grp_id in @deployable_group_ids
        update_structure_cache(type_id, is_structure)
        is_structure

      {:ok, %{"name" => _name} = partial_info} ->
        # We got partial data (no category_id/group_id).
        AppLogger.scheduler_debug(
          "Truly partial type info for #{type_id} => #{inspect(partial_info)}. Assuming not a structure."
        )

        update_structure_cache(type_id, false)
        false

      error ->
        AppLogger.scheduler_warn("Failed to get type info for #{type_id}: #{inspect(error)}")
        update_structure_cache(type_id, false)
        false
    end
  end

  defp update_structure_cache(type_id, value) do
    old_cache = Process.get(@structure_types_cache_key)
    new_cache = Map.put(old_cache, type_id, value)
    Process.put(@structure_types_cache_key, new_cache)
  end

  # ----------------------------------------------------------------
  # Misc helpers
  # ----------------------------------------------------------------

  # Log DB diagnostics for test
  defp log_weekly_diagnostics(start_dt, end_dt) do
    kills_query =
      Killmail
      |> Query.filter(character_role == :attacker)
      |> Query.filter(kill_time >= ^start_dt)
      |> Query.filter(kill_time <= ^end_dt)

    losses_query =
      Killmail
      |> Query.filter(character_role == :victim)
      |> Query.filter(kill_time >= ^start_dt)
      |> Query.filter(kill_time <= ^end_dt)

    with {:ok, kills} <- Api.read(kills_query),
         {:ok, losses} <- Api.read(losses_query) do
      AppLogger.scheduler_info(
        "Weekly DB diagnostics: " <>
          "Kills in last 7 days=#{length(kills)}, " <>
          "Losses in last 7 days=#{length(losses)}"
      )
    else
      _ -> AppLogger.scheduler_error("Unable to count kills/losses in DB for test highlights")
    end
  end

  defp config_module do
    Application.get_env(:wanderer_notifier, :config_module, NotificationConfig)
  end
end
