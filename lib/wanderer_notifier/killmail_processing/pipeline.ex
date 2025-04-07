defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  Handles both realtime and historical processing modes.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.KillmailProcessing.{Context, Metrics}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.{Enrichment, Notification}
  alias WandererNotifier.Resources.KillmailPersistence

  @type killmail :: Killmail.t()
  @type result :: {:ok, killmail()} | {:error, term()}

  @doc """
  Process a killmail through the pipeline.
  """
  @spec process_killmail(map(), Context.t()) :: result()
  def process_killmail(zkb_data, ctx) do
    Metrics.track_processing_start(ctx)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- create_killmail(zkb_data),
         {:ok, enriched} <- enrich_killmail(killmail),
         {:ok, tracked} <- check_tracking(enriched),
         {:ok, persisted} <- maybe_persist_killmail(tracked, ctx),
         {:ok, should_notify, reason} <- check_notification(persisted, ctx),
         {:ok, result} <- maybe_send_notification(persisted, should_notify, ctx) do
      Metrics.track_processing_complete(ctx, {:ok, result})
      log_killmail_outcome(result, ctx, persisted: true, notified: should_notify, reason: reason)
      {:ok, result}
    else
      {:error, {:skipped, reason}} ->
        Metrics.track_processing_skipped(ctx)
        log_killmail_outcome(zkb_data, ctx, persisted: false, notified: false, reason: reason)
        {:ok, :skipped}

      error ->
        Metrics.track_processing_error(ctx)
        log_killmail_error(zkb_data, ctx, error)
        error
    end
  end

  @spec create_killmail(map()) :: result()
  defp create_killmail(zkb_data) do
    kill_id = Map.get(zkb_data, "killmail_id")
    hash = get_in(zkb_data, ["zkb", "hash"])

    with {:ok, esi_data} <- ESIService.get_killmail(kill_id, hash),
         zkb_map <- Map.get(zkb_data, "zkb", %{}),
         killmail <- Killmail.new(kill_id, zkb_map, esi_data) do
      {:ok, killmail}
    else
      error ->
        log_killmail_error(zkb_data, nil, error)
        error
    end
  end

  @spec enrich_killmail(killmail()) :: result()
  defp enrich_killmail(killmail) do
    enriched = Enrichment.enrich_killmail_data(killmail)

    # Log detailed information about the enriched killmail for debugging if enabled
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      # Get the killmail ID
      kill_id = enriched.killmail_id

      IO.puts("\n=====================================================")
      IO.puts("🔍 ANALYZING ENRICHED KILLMAIL #{kill_id}")
      IO.puts("=====================================================\n")

      # Log victim data
      log_enriched_victim_data(enriched)

      # Log attacker sample data
      log_enriched_attacker_data(enriched)

      # Reset the flag after both persistence and enrichment logging is complete
      Application.put_env(:wanderer_notifier, :log_next_killmail, false)
    end

    {:ok, enriched}
  rescue
    error ->
      stacktrace = __STACKTRACE__
      log_killmail_error(killmail, nil, {error, stacktrace})
      {:error, :enrichment_failed}
  end

  # Log what would be enriched for the victim
  defp log_enriched_victim_data(killmail) do
    victim = Killmail.get_victim(killmail) || %{}
    victim_id = Map.get(victim, "character_id", "unknown")
    victim_name = Map.get(victim, "character_name", "Unknown")

    IO.puts("------ VICTIM ENRICHED DATA ------")
    IO.puts("KILLMAIL_ID: #{killmail.killmail_id}")
    IO.puts("CHARACTER_ID: #{victim_id}")
    IO.puts("CHARACTER_NAME: #{victim_name}")

    # Solar system info
    esi_data = killmail.esi_data || %{}
    solar_system_id = Map.get(esi_data, "solar_system_id", "unknown")
    solar_system_name = Map.get(esi_data, "solar_system_name", "unknown")

    IO.puts("SOLAR_SYSTEM_ID: #{solar_system_id}")
    IO.puts("SOLAR_SYSTEM_NAME: #{solar_system_name}")

    # Ship info
    ship_type_id = Map.get(victim, "ship_type_id", "unknown")
    ship_type_name = Map.get(victim, "ship_type_name", "unknown")

    IO.puts("SHIP_TYPE_ID: #{ship_type_id}")
    IO.puts("SHIP_TYPE_NAME: #{ship_type_name}")

    # Corp/alliance info
    corp_id = Map.get(victim, "corporation_id", "unknown")
    corp_name = Map.get(victim, "corporation_name", "unknown")
    alliance_id = Map.get(victim, "alliance_id", "unknown")
    alliance_name = Map.get(victim, "alliance_name", "unknown")

    IO.puts("CORPORATION_ID: #{corp_id}")
    IO.puts("CORPORATION_NAME: #{corp_name}")
    IO.puts("ALLIANCE_ID: #{alliance_id}")
    IO.puts("ALLIANCE_NAME: #{alliance_name}")

    # ZKB data
    zkb_data = killmail.zkb || %{}
    total_value = Map.get(zkb_data, "totalValue", "unknown")
    zkb_hash = Map.get(zkb_data, "hash", "unknown")

    IO.puts("ZKB_HASH: #{zkb_hash}")
    IO.puts("TOTAL_VALUE: #{total_value}")

    # Timestamp
    kill_time = Map.get(esi_data, "killmail_time", "unknown")
    IO.puts("KILL_TIME: #{kill_time}")

    IO.puts("\n")
  end

  # Log what would be enriched for a sample attacker
  defp log_enriched_attacker_data(killmail) do
    attackers = Killmail.get_attacker(killmail) || []

    if Enum.empty?(attackers) do
      IO.puts("------ ATTACKER ENRICHED DATA ------")
      IO.puts("NO ATTACKERS FOUND")
      IO.puts("\n")
    else
      # Use first attacker (or final blow attacker if available)
      attacker =
        Enum.find(attackers, &Map.get(&1, "final_blow", false)) ||
          List.first(attackers)

      attacker_id = Map.get(attacker, "character_id", "unknown")
      attacker_name = Map.get(attacker, "character_name", "Unknown")

      IO.puts("------ ATTACKER ENRICHED DATA ------")
      IO.puts("KILLMAIL_ID: #{killmail.killmail_id}")
      IO.puts("CHARACTER_ID: #{attacker_id}")
      IO.puts("CHARACTER_NAME: #{attacker_name}")
      IO.puts("ROLE: attacker")
      IO.puts("FINAL_BLOW: #{Map.get(attacker, "final_blow", false)}")

      # Solar system info (same as victim)
      esi_data = killmail.esi_data || %{}
      solar_system_id = Map.get(esi_data, "solar_system_id", "unknown")
      solar_system_name = Map.get(esi_data, "solar_system_name", "unknown")

      IO.puts("SOLAR_SYSTEM_ID: #{solar_system_id}")
      IO.puts("SOLAR_SYSTEM_NAME: #{solar_system_name}")

      # Ship info
      ship_type_id = Map.get(attacker, "ship_type_id", "unknown")
      ship_type_name = Map.get(attacker, "ship_type_name", "unknown")

      IO.puts("SHIP_TYPE_ID: #{ship_type_id}")
      IO.puts("SHIP_TYPE_NAME: #{ship_type_name}")

      # Weapon info
      weapon_type_id = Map.get(attacker, "weapon_type_id", "unknown")
      weapon_type_name = Map.get(attacker, "weapon_type_name", "unknown")

      IO.puts("WEAPON_TYPE_ID: #{weapon_type_id}")
      IO.puts("WEAPON_TYPE_NAME: #{weapon_type_name}")

      # Corp/alliance info
      corp_id = Map.get(attacker, "corporation_id", "unknown")
      corp_name = Map.get(attacker, "corporation_name", "unknown")
      alliance_id = Map.get(attacker, "alliance_id", "unknown")
      alliance_name = Map.get(attacker, "alliance_name", "unknown")

      IO.puts("CORPORATION_ID: #{corp_id}")
      IO.puts("CORPORATION_NAME: #{corp_name}")
      IO.puts("ALLIANCE_ID: #{alliance_id}")
      IO.puts("ALLIANCE_NAME: #{alliance_name}")

      # ZKB data (same as victim)
      zkb_data = killmail.zkb || %{}
      total_value = Map.get(zkb_data, "totalValue", "unknown")
      zkb_hash = Map.get(zkb_data, "hash", "unknown")

      IO.puts("ZKB_HASH: #{zkb_hash}")
      IO.puts("TOTAL_VALUE: #{total_value}")

      # Timestamp (same as victim)
      kill_time = Map.get(esi_data, "killmail_time", "unknown")
      IO.puts("KILL_TIME: #{kill_time}")

      IO.puts("\n")
    end
  end

  @spec check_tracking(killmail()) :: result()
  defp check_tracking(killmail) do
    AppLogger.kill_debug("[Pipeline] Checking if killmail should be tracked", %{
      kill_id: killmail.killmail_id,
      available_victim_fields: killmail |> Killmail.get_victim() |> Map.keys(),
      available_attacker_fields: killmail |> Killmail.get_attacker() |> List.first() |> Map.keys()
    })

    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: true}} ->
        AppLogger.kill_debug("[Pipeline] Killmail should be tracked", %{
          kill_id: killmail.killmail_id
        })

        {:ok, killmail}

      {:ok, %{should_notify: false, reason: reason}} ->
        AppLogger.kill_debug("[Pipeline] Killmail should NOT be tracked", %{
          kill_id: killmail.killmail_id,
          reason: reason
        })

        {:error, {:skipped, reason}}
    end
  end

  @spec maybe_persist_killmail(killmail(), Context.t()) :: result()
  defp maybe_persist_killmail(killmail, ctx) do
    AppLogger.kill_debug("[Pipeline] Deciding whether to persist killmail", %{
      kill_id: killmail.killmail_id,
      character_id: ctx.character_id
    })

    case KillmailPersistence.maybe_persist_killmail(killmail, ctx.character_id) do
      {:ok, :persisted} ->
        AppLogger.kill_debug("[Pipeline] Killmail was newly persisted", %{
          kill_id: killmail.killmail_id,
          character_id: ctx.character_id
        })

        Metrics.track_persistence(ctx)
        {:ok, killmail}

      {:ok, :already_exists} ->
        AppLogger.kill_debug("[Pipeline] Killmail already existed", %{
          kill_id: killmail.killmail_id
        })

        {:ok, killmail}

      # Successfully saved to database and returned the record
      {:ok, record} when is_struct(record) ->
        AppLogger.kill_debug("[Pipeline] Killmail was persisted to database", %{
          kill_id: killmail.killmail_id,
          character_id: ctx.character_id,
          record_id: Map.get(record, :id, "unknown")
        })

        Metrics.track_persistence(ctx)
        {:ok, killmail}

      :ignored ->
        AppLogger.kill_debug("[Pipeline] Killmail persistence was ignored", %{
          kill_id: killmail.killmail_id,
          reason: "Not tracked by any character"
        })

        {:ok, killmail}

      error ->
        AppLogger.kill_error("[Pipeline] Killmail persistence failed", %{
          kill_id: killmail.killmail_id,
          error: inspect(error)
        })

        error
    end
  end

  @spec check_notification(killmail(), Context.t()) :: {:ok, boolean(), String.t()}
  defp check_notification(killmail, ctx) do
    # Only send notifications for realtime processing
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: should_notify, reason: reason}} ->
        should_notify = Context.realtime?(ctx) and should_notify
        {:ok, should_notify, reason}

      error ->
        error
    end
  end

  @spec maybe_send_notification(killmail(), boolean(), Context.t()) :: result()
  defp maybe_send_notification(killmail, true, ctx) do
    case Notification.send_kill_notification(killmail, killmail.killmail_id) do
      {:ok, _} ->
        Metrics.track_notification_sent(ctx)
        {:ok, killmail}

      error ->
        log_killmail_error(killmail, ctx, error)
        error
    end
  end

  defp maybe_send_notification(killmail, false, _ctx) do
    {:ok, killmail}
  end

  # Logging helpers

  defp log_killmail_outcome(killmail, ctx,
         persisted: persisted,
         notified: notified,
         reason: reason
       ) do
    kill_id = get_kill_id(killmail)
    kill_time = Map.get(killmail, "killmail_time")

    metadata = %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: ctx && ctx.character_id,
      character_name: ctx && ctx.character_name,
      batch_id: ctx && ctx.batch_id,
      reason: reason,
      processing_mode: ctx && ctx.mode && ctx.mode.mode
    }

    # Determine status and message based on outcomes
    {message, status} = get_log_details(persisted, notified, reason)

    # Add status to metadata and log with appropriate level
    updated_metadata = Map.put(metadata, :status, status)

    # Most individual killmail logs should be debug level
    # Only keep "saved_and_notified" at info level
    if status == "saved_and_notified" do
      AppLogger.kill_info(message, updated_metadata)
    else
      # All other statuses (skipped, duplicate, saved without notification) should be debug
      AppLogger.kill_debug(message, updated_metadata)
    end
  end

  # Helper function to get log message and status based on outcomes
  defp get_log_details(persisted, notified, reason) do
    case {persisted, notified, reason} do
      {true, true, _} ->
        {"Killmail saved and notified", "saved_and_notified"}

      {true, false, "Duplicate kill"} ->
        {"Killmail already exists", "duplicate"}

      {true, false, _} ->
        {"Killmail saved without notification", "saved"}

      {false, false, _} ->
        {"Killmail processing skipped", "skipped"}
    end
  end

  defp log_killmail_error(killmail, ctx, error) do
    kill_id = get_kill_id(killmail)
    kill_time = Map.get(killmail, "killmail_time")

    # Safely extract context values with default fallbacks
    character_id = ctx && ctx.character_id
    character_name = (ctx && ctx.character_name) || "unknown"
    batch_id = (ctx && ctx.batch_id) || "unknown"
    processing_mode = ctx && ctx.mode && ctx.mode.mode

    # Create base metadata
    metadata = %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: character_id,
      character_name: character_name,
      batch_id: batch_id,
      status: "error",
      processing_mode: processing_mode
    }

    # Format error information based on error type
    error_info = format_error_info(error)

    # Log the error with formatted information
    AppLogger.kill_error(
      "Killmail processing failed",
      Map.merge(metadata, error_info)
    )
  end

  # Helper to format error information based on error type
  defp format_error_info({exception, stacktrace}) when is_list(stacktrace) do
    %{
      error: Exception.message(exception),
      stacktrace: Exception.format_stacktrace(stacktrace)
    }
  end

  defp format_error_info(error) do
    %{error: inspect(error)}
  end

  defp get_kill_id(%Killmail{} = killmail), do: killmail.killmail_id
  defp get_kill_id(%{"killmail_id" => id}), do: id
  defp get_kill_id(%{killmail_id: id}), do: id

  defp get_kill_id(data) do
    AppLogger.kill_error("Failed to extract kill_id", %{
      data: inspect(data)
    })

    nil
  end
end
