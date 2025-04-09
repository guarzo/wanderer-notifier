defmodule WandererNotifier.Schedulers.WeeklyKillHighlightsScheduler do
  @moduledoc """
  Scheduler for sending weekly kill highlights to Discord.
  Sends the best kill and worst loss from the past week for tracked characters.
  """

  use WandererNotifier.Schedulers.IntervalScheduler, name: __MODULE__

  alias WandererNotifier.Api.ESI.Service, as: EsiService
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Repository, as: DataRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  require Ash.Query, as: Query

  # EVE Online constants and IDs
  @pod_type_id 670

  @structure_group_ids [1657, 1404, 1406, 365, 297, 1025, 1876, 1677, 1927, 1980]
  @deployable_group_ids [361, 363, 715, 1022, 1247, 1249, 1246, 1248, 1201, 1297, 1275]

  # In-process cache for structure type checks
  @structure_types_cache_key :structure_types_cache

  # Public API
  @impl true
  def enabled?, do: Features.kill_charts_enabled?()

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
  Sends a manual test for weekly kill highlights using a 7-day date range.
  """
  def send_test_highlights do
    AppLogger.scheduler_info("Sending test weekly kill highlights")
    channel_id = config_module().discord_channel_id_for(:kill_charts)

    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for test kill charts")
      {:error, "No channel ID configured"}
    else
      now = DateTime.utc_now()
      days_ago = DateTime.add(now, -7 * 86_400, :second)

      AppLogger.scheduler_info(
        "Test kill highlights using date range: #{DateTime.to_string(days_ago)} to #{DateTime.to_string(now)}"
      )

      log_weekly_diagnostics(days_ago, now)

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

  # Process Highlights (Common Functionality)
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

      best_kill_result =
        try do
          AppLogger.scheduler_info("Searching for best kill")
          find_best_kill(start_date, end_date)
        rescue
          e ->
            stack = Exception.format_stacktrace(__STACKTRACE__)
            AppLogger.scheduler_error("Error finding best kill: #{Exception.message(e)}")
            AppLogger.scheduler_error("Stack trace for best kill error: #{stack}")
            {:error, "Error finding best kill: #{Exception.message(e)}"}
        end

      kills_sent = safe_send_highlight(best_kill_result, channel_id, true, date_range_str)

      worst_loss_result =
        try do
          AppLogger.scheduler_info("Searching for worst loss")
          find_worst_loss(start_date, end_date)
        rescue
          e ->
            stack = Exception.format_stacktrace(__STACKTRACE__)
            AppLogger.scheduler_error("Error finding worst loss: #{Exception.message(e)}")
            AppLogger.scheduler_error("Stack trace for worst loss error: #{stack}")
            {:error, "Error finding worst loss: #{Exception.message(e)}"}
        end

      losses_sent = safe_send_highlight(worst_loss_result, channel_id, false, date_range_str)
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
      stack = Exception.format_stacktrace(__STACKTRACE__)

      AppLogger.scheduler_error("Error processing kill highlights",
        error: Exception.message(e),
        stacktrace: stack
      )

      {:error, "Exception: #{Exception.message(e)}"}
  end

  defp safe_send_highlight({:error, _} = _err, _channel_id, _is_kill, _date_range), do: 0

  defp safe_send_highlight({:ok, killmail}, channel_id, is_kill, date_range_str) do
    maybe_send_highlight({:ok, killmail}, channel_id, is_kill, date_range_str)
  rescue
    e ->
      AppLogger.scheduler_error("Error sending kill highlight: #{Exception.message(e)}")
      0
  end

  # ----------------------------------------------------------------
  # Kill Finding Logic
  # ----------------------------------------------------------------

  defp find_best_kill(start_date, end_date),
    do: find_significant_killmail(start_date, end_date, :attacker, "best kill")

  defp find_worst_loss(start_date, end_date),
    do: find_significant_killmail(start_date, end_date, :victim, "worst loss")

  defp find_significant_killmail(start_date, end_date, character_role, description) do
    AppLogger.scheduler_info(
      "Searching for #{description} between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    tracked_ids = get_tracked_character_ids()
    AppLogger.scheduler_info("Retrieved #{length(tracked_ids)} tracked character IDs")

    if tracked_ids == [] do
      AppLogger.scheduler_warn("No tracked characters found, cannot search for #{description}")
      {:error, :no_tracked_characters}
    else
      case query_killmails_for_period(start_date, end_date, character_role) do
        {:ok, []} ->
          AppLogger.scheduler_warn("No #{character_role}s found in the date range")
          {:error, :no_results_in_range}

        {:ok, killmails} ->
          killmails
          |> filter_tracked_killmails(tracked_ids, character_role)
          |> deduplicate_killmails(character_role)
          |> Enum.filter(fn km -> not is_nil(km.total_value) end)
          |> pick_and_enrich(description)

        error ->
          AppLogger.scheduler_error(
            "Error querying #{character_role}s in date range: #{inspect(error)}"
          )

          {:error, "Failed to find #{character_role}s in date range"}
      end
    end
  end

  defp pick_and_enrich(killmails, description) do
    if killmails == [] do
      AppLogger.scheduler_warn("No killmails with valid total_value found")
      {:error, :no_kills_with_value}
    else
      best_km = pick_highest_value_killmail(killmails)

      AppLogger.scheduler_debug("""
      FULL #{String.upcase(description)} KILLMAIL:
      #{inspect(best_km, pretty: true, limit: :infinity)}
      """)

      best_km
      |> enrich_killmail_data()
      |> tap(&log_selected_killmail(&1, description))
      |> then(&{:ok, &1})
    end
  end

  defp query_killmails_for_period(start_date, end_date, character_role) do
    # Use the new normalized data model
    # First query for character involvements that match our criteria
    involvement_query =
      WandererNotifier.Resources.KillmailCharacterInvolvement
      |> Query.filter(character_role == ^character_role)
      |> Query.load(:killmail)
      |> Query.filter(killmail.kill_time >= ^start_date)
      |> Query.filter(killmail.kill_time <= ^end_date)
      |> Query.filter(killmail.victim_ship_id != ^@pod_type_id)
      |> Query.sort({:expr, [:killmail, :total_value]}, :desc)
      |> Query.limit(100)

    case Api.read(involvement_query) do
      {:ok, involvements} ->
        # Extract the killmails from the involvements
        killmails = Enum.map(involvements, & &1.killmail)
        {:ok, killmails}

      error ->
        error
    end
  end

  # Get the ship type ID for a specific character role
  defp ship_type_for_role(km, :victim) do
    # For victims, use the victim's ship type ID
    km.victim_ship_id
  end

  defp ship_type_for_role(km, :attacker) do
    # For attackers, use the victim's ship type ID
    km.victim_ship_id
  end

  defp filter_tracked_killmails(killmails, tracked_ids, character_role) do
    Enum.filter(killmails, &tracked_and_not_structure?(&1, tracked_ids, character_role))
  end

  defp tracked_and_not_structure?(km, tracked_ids, character_role) do
    case find_character_involvement(km.id, character_role) do
      {:ok, involvement} ->
        char_id = parse_to_int(involvement.character_id)
        tracked? = char_id in tracked_ids
        structure? = structure_or_deployable?(ship_type_for_role(km, character_role))

        log_tracking_status(char_id, tracked?, structure?, km.killmail_id, character_role)
        tracked? and not structure?

      _ ->
        false
    end
  end

  defp log_tracking_status(char_id, tracked?, structure?, killmail_id, character_role) do
    if !tracked? do
      AppLogger.scheduler_debug(
        "Character #{char_id} is not tracked — ignoring killmail #{killmail_id}"
      )
    end

    if structure? do
      structure_type = if character_role == :victim, do: "Lost structure", else: "Structure kill"
      AppLogger.scheduler_debug("#{structure_type} — ignoring killmail #{killmail_id}")
    end
  end

  # Helper function to find character involvement
  defp find_character_involvement(killmail_id, character_role) do
    query =
      WandererNotifier.Resources.KillmailCharacterInvolvement
      |> Query.filter(killmail_id == ^killmail_id)
      |> Query.filter(character_role == ^character_role)
      |> Query.limit(1)

    case Api.read(query) do
      {:ok, [involvement]} -> {:ok, involvement}
      _ -> {:error, :not_found}
    end
  end

  defp deduplicate_killmails(killmails, character_role) do
    killmails
    |> Enum.group_by(& &1.killmail_id)
    |> Enum.map(&select_best_killmail(&1, character_role))
    |> Enum.reject(&is_nil/1)
  end

  defp select_best_killmail({_, [km]}, _character_role), do: km
  defp select_best_killmail({_, []}, _character_role), do: nil

  defp select_best_killmail({_, kms}, character_role) do
    AppLogger.scheduler_info(
      "Multiple tracked characters for killmail #{List.first(kms).killmail_id}"
    )

    if character_role == :attacker do
      select_highest_damage_killmail(kms)
    else
      List.first(kms)
    end
  end

  defp select_highest_damage_killmail(killmails) do
    first_km = List.first(killmails)

    case get_all_attacker_involvements(first_km.id) do
      {:ok, []} -> first_km
      {:ok, involvements} -> select_killmail_with_highest_damage(killmails, involvements)
      _ -> first_km
    end
  end

  defp select_killmail_with_highest_damage(killmails, involvements) do
    highest_damage =
      Enum.max_by(involvements, fn inv -> inv.damage_done || 0 end, fn ->
        List.first(involvements)
      end)

    Enum.find(killmails, List.first(killmails), fn km -> km.id == highest_damage.killmail_id end)
  end

  # Helper to get all attacker involvements for a killmail
  defp get_all_attacker_involvements(killmail_id) do
    query =
      WandererNotifier.Resources.KillmailCharacterInvolvement
      |> Query.filter(killmail_id == ^killmail_id)
      |> Query.filter(character_role == :attacker)

    Api.read(query)
  end

  # Enrich killmail data from the normalized model
  defp enrich_killmail_data(km) do
    # Try to find character information for this killmail
    case find_character_in_killmail(km) do
      {:ok, character_id, character_name, character_role} ->
        km = %{
          km
          | related_character_id: character_id,
            related_character_name: character_name,
            character_role: character_role
        }

        # Continue with enrichment
        km
        |> maybe_resolve_character_name()
        |> maybe_fix_ship_name()
        |> maybe_fix_system_name()

      _ ->
        # Continue with basic enrichment
        km
        |> maybe_fix_ship_name()
        |> maybe_fix_system_name()
    end
  end

  # Find character information for a killmail
  defp find_character_in_killmail(km) do
    query =
      WandererNotifier.Resources.KillmailCharacterInvolvement
      |> Query.filter(killmail_id == ^km.id)
      |> Query.limit(1)

    case Api.read(query) do
      {:ok, [involvement]} ->
        {:ok, involvement.character_id, involvement.character_name, involvement.character_role}

      _ ->
        {:error, :not_found}
    end
  end

  # ----------------------------------------------------------------
  # Notification Sending Logic
  # ----------------------------------------------------------------

  defp maybe_send_highlight({:ok, killmail}, channel_id, is_kill, date_range_str) do
    AppLogger.scheduler_info(
      "Sending #{if is_kill, do: "best kill", else: "worst loss"} notification"
    )

    embed = StructuredFormatter.format_weekly_kill_highlight(killmail, is_kill, date_range_str)
    NotifierFactory.notify(:send_discord_embed_to_channel, [channel_id, embed])
    1
  end

  # ----------------------------------------------------------------
  # Data Enrichment Helpers
  # ----------------------------------------------------------------

  defp maybe_resolve_character_name(km) do
    if is_nil(km.related_character_name) or
         String.starts_with?(to_string(km.related_character_name), "Unknown") do
      try_alternative_name_sources(km)
    else
      km
    end
  end

  defp try_alternative_name_sources(km) do
    case {is_nil(km.related_character_id), lookup_character_name(km.related_character_id)} do
      {false, {:ok, name}} -> %{km | related_character_name: name}
      _ -> fallback_name_from_killmail_data(km)
    end
  end

  defp fallback_name_from_killmail_data(km) do
    case {km.character_role, km.victim_data, km.attacker_data} do
      {:attacker, %{"character_name" => name}, _} when is_binary(name) ->
        %{km | related_character_name: name}

      {:victim, %{"character_name" => name}, _} when is_binary(name) ->
        %{km | related_character_name: name}

      {_, _, %{"character_name" => name}} when is_binary(name) ->
        %{km | related_character_name: name}

      _ ->
        %{km | related_character_name: "Unknown Pilot"}
    end
  end

  defp maybe_fix_ship_name(km) do
    cond do
      km.character_role == :victim and is_nil(km.ship_type_name) and is_map(km.victim_data) ->
        Map.update!(km, :ship_type_name, fn _ ->
          Map.get(km.victim_data, "ship_type_name", "Unknown Ship")
        end)

      km.ship_type_name == "Unknown Ship" and is_map(km.victim_data) ->
        Map.update!(km, :ship_type_name, fn _ ->
          Map.get(km.victim_data, "ship_type_name", "Unknown Ship")
        end)

      true ->
        km
    end
  end

  defp maybe_fix_system_name(km) do
    if (is_nil(km.solar_system_name) or km.solar_system_name == "Unknown System") and
         is_integer(km.solar_system_id) do
      %{km | solar_system_name: "J#{km.solar_system_id}"}
    else
      km
    end
  end

  defp lookup_character_name(character_id) when not is_nil(character_id) do
    case DataRepo.get_character_name(character_id) do
      {:ok, name} when is_binary(name) and name not in ["", "Unknown"] ->
        AppLogger.scheduler_info("[NAME_LOOKUP] Found character name in repo cache", %{
          character_id: character_id,
          character_name: name
        })

        {:ok, name}

      _ ->
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
  # Discord Embed Formatting
  # ----------------------------------------------------------------

  defp format_date_range(start_date, end_date) do
    "#{Calendar.strftime(start_date, "%Y-%m-%d")} to #{Calendar.strftime(end_date, "%Y-%m-%d")}"
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
  # Tracked Characters & Database Queries
  # ----------------------------------------------------------------

  defp get_tracked_character_ids do
    tracked_chars = DataRepo.get_tracked_characters()
    count = length(tracked_chars)
    AppLogger.scheduler_info("Retrieved #{count} tracked characters from repository cache")

    if count > 0 do
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
    character_query = WandererNotifier.Resources.TrackedCharacter |> Query.select([:character_id])

    case WandererNotifier.Resources.Api.read(character_query) do
      {:ok, results} ->
        ids =
          results
          |> Enum.map(fn item -> parse_to_int(Map.get(item, :character_id)) end)
          |> Enum.reject(&is_nil/1)

        AppLogger.scheduler_info("Successfully found #{length(ids)} tracked IDs in database")
        {:ok, ids}

      error ->
        AppLogger.scheduler_error("Error querying tracked_characters table: #{inspect(error)}")
        {:error, "Failed to query tracked characters from database"}
    end
  end

  # ----------------------------------------------------------------
  # Structure Check & Caching
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
    if is_nil(Process.get(@structure_types_cache_key)),
      do: Process.put(@structure_types_cache_key, %{}),
      else: :ok
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
    Process.put(@structure_types_cache_key, Map.put(old_cache, type_id, value))
  end

  # ----------------------------------------------------------------
  # Miscellaneous Helpers
  # ----------------------------------------------------------------

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
        "Weekly DB diagnostics: Kills in last 7 days=#{length(kills)}, Losses in last 7 days=#{length(losses)}"
      )
    else
      _ -> AppLogger.scheduler_error("Unable to count kills/losses in DB for test highlights")
    end
  end

  defp config_module,
    do: Application.get_env(:wanderer_notifier, :config_module, NotificationConfig)

  # Convert total_value to a Decimal (with rounding)
  defp to_decimal(%Decimal{} = dec), do: dec
  defp to_decimal(int) when is_integer(int), do: Decimal.new(int)

  defp to_decimal(float) when is_float(float),
    do: float |> Float.to_string() |> Decimal.new() |> Decimal.round(2)

  defp to_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {dec, ""} -> Decimal.round(dec, 2)
      _ -> Decimal.new(0)
    end
  end

  defp to_decimal(_), do: Decimal.new(0)

  defp pick_highest_value_killmail(killmails) do
    killmails
    |> Enum.map(fn km -> {km, to_decimal(km.total_value)} end)
    |> Enum.reduce({nil, nil}, fn {km, value}, {max_km, max_value} ->
      cond do
        is_nil(max_value) -> {km, value}
        Decimal.compare(value, max_value) == :gt -> {km, value}
        true -> {max_km, max_value}
      end
    end)
    |> elem(0)
  end

  defp log_selected_killmail(km, description) do
    AppLogger.scheduler_info(
      "Selected #{description}: " <>
        "ID=#{km.killmail_id}, " <>
        "Character=#{km.related_character_name || "Unknown"}, " <>
        "Ship=#{km.ship_type_name || "Unknown"}, " <>
        "System=#{km.solar_system_name || "Unknown"}, " <>
        "Region=#{km.region_name || "Unknown"}, " <>
        "Value=#{inspect(km.total_value)}, " <>
        "Time=#{DateTime.to_string(km.kill_time)}"
    )
  end
end
