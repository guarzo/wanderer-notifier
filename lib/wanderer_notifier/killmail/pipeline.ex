defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  """

  alias WandererNotifier.Core.Stats

  alias WandererNotifier.Killmail.{
    Context,
    Killmail,
    Enrichment,
    Notification
  }

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type zkb_data :: map()
  @type result :: {:ok, String.t() | :skipped} | {:error, term()}

  # Define error types at compile time
  @timeout_error WandererNotifier.ESI.Service.TimeoutError
  @api_error WandererNotifier.ESI.Service.ApiError

  defp esi_service do
    Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.Service)
  end

  @doc """
  Main entry point: runs the killmail through creation, enrichment,
  tracking, notification decision, and (optional) dispatch.
  """
  @spec process_killmail(map(), Context.t()) :: {:ok, map() | :skipped} | {:error, term()}
  def process_killmail(zkb_data, context) do
    require Logger

    Stats.increment(:kill_processed)
    context = ensure_context(context)
    system_id = get_in(zkb_data, ["solar_system_id"])
    context = %{context | system_id: system_id}
    kill_id = get_in(zkb_data, ["killmail_id"])

    # Check for duplicates first
    case check_deduplication(kill_id) do
      {:ok, :duplicate} ->
        handle_duplicate_killmail(kill_id, system_id)

      {:ok, :new} ->
        # First check if we should notify without ESI
        case should_notify_without_esi?(zkb_data) do
          {:ok, %{should_notify: false, reason: reason}} ->
            handle_notification_skipped(kill_id, system_id, reason)

          {:ok, %{should_notify: true}} ->
            process_tracked_killmail_pipeline(zkb_data, context, kill_id, system_id)

          {:error, reason} ->
            handle_notification_error(zkb_data, context, reason, kill_id, system_id)
        end

      {:error, reason} ->
        handle_deduplication_error(zkb_data, context, reason, kill_id, system_id)
    end
  end

  defp process_tracked_killmail_pipeline(zkb_data, context, kill_id, system_id) do
    case extract_killmail_id(zkb_data) do
      {:ok, killmail_id} ->
        process_valid_killmail(zkb_data, context, killmail_id, system_id)

      {:error, :invalid_killmail_id} ->
        handle_invalid_killmail_id(kill_id, system_id)

      error ->
        handle_killmail_id_extraction_error(kill_id, system_id, error)
    end
  end

  defp process_valid_killmail(zkb_data, context, killmail_id, system_id) do
    case process_new_killmail(zkb_data, context) do
      {:ok, killmail} ->
        handle_notification_sent(killmail, context)

      error ->
        handle_killmail_processing_error(killmail_id, system_id, error)
    end
  end

  defp handle_invalid_killmail_id(kill_id, system_id) do
    system_name = get_system_name(system_id)

    AppLogger.kill_error("Invalid killmail ID",
      kill_id: kill_id,
      system: system_name,
      error: "invalid_killmail_id"
    )

    {:error, :invalid_killmail_id}
  end

  defp handle_killmail_id_extraction_error(kill_id, system_id, error) do
    system_name = get_system_name(system_id)

    AppLogger.kill_error("Error extracting killmail ID",
      kill_id: kill_id,
      system: system_name,
      error: inspect(error)
    )

    {:error, error}
  end

  defp handle_killmail_processing_error(killmail_id, system_id, error) do
    system_name = get_system_name(system_id)

    AppLogger.kill_error("Killmail processing failed",
      kill_id: killmail_id,
      system: system_name,
      error: inspect(error)
    )

    error
  end

  defp handle_notification_error(zkb_data, context, reason, kill_id, system_id) do
    system_name = get_system_name(system_id)

    AppLogger.kill_error("Error checking notification requirements",
      kill_id: kill_id,
      system: system_name,
      error: inspect(reason)
    )

    handle_error(zkb_data, context, reason)
  end

  defp check_deduplication(kill_id) do
    case deduplication_module().check(:kill, kill_id) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_deduplication_response, result}}
    end
  end

  defp handle_duplicate_killmail(kill_id, system_id) do
    Stats.track_processing_complete({:ok, :skipped})
    system_name = get_system_name(system_id)

    AppLogger.kill_info("💀 🔄 ##{kill_id} | #{system_name} | Duplicate killmail")

    {:ok, :skipped}
  end

  defp handle_deduplication_error(zkb_data, context, reason, kill_id, system_id) do
    system_name = get_system_name(system_id)

    AppLogger.kill_error("Error checking deduplication",
      kill_id: kill_id,
      system: system_name,
      error: inspect(reason)
    )

    handle_error(zkb_data, context, reason)
  end

  # Extract killmail_id from the data structure
  defp extract_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: {:ok, to_string(id)}

  defp extract_killmail_id(data) do
    AppLogger.kill_error("Failed to extract killmail_id - expected integer killmail_id field",
      data: inspect(data, pretty: true),
      module: __MODULE__
    )

    {:error, :invalid_killmail_id}
  end

  # Process a new (non-duplicate) killmail
  defp process_new_killmail(zkb_data, ctx) do
    _killmail_id = get_in(zkb_data, ["killmail_id"])
    _system_id = get_in(zkb_data, ["solar_system_id"])

    # We already checked should_notify_without_esi? in the main pipeline
    # so we can directly process the tracked killmail
    process_tracked_killmail(zkb_data, ctx)
  end

  # Process a killmail that has tracked entities
  defp process_tracked_killmail(zkb_data, ctx) do
    _killmail_id = get_in(zkb_data, ["killmail_id"])
    _system_id = get_in(zkb_data, ["solar_system_id"])

    with {:ok, killmail} <- build_killmail(zkb_data),
         {:ok, enriched} <- enrich(killmail),
         {:ok, validated} <- check_notification_requirements(enriched, ctx) do
      {:ok, validated}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Check if notification should be sent for an enriched killmail
  defp check_notification_requirements(killmail, character_id) do
    config = config_module().get_config()

    notifications_enabled = get_in(config, [:notifications, :enabled])

    if notifications_enabled do
      check_specific_notification_type(killmail, character_id, config)
    else
      {:error, :notifications_disabled}
    end
  end

  defp check_specific_notification_type(killmail, character_id, config) do
    case killmail do
      %{system_id: system_id} when not is_nil(system_id) ->
        check_system_notification_enabled(killmail, config)

      %{victim: %{character_id: ^character_id}} ->
        check_character_notification_enabled(killmail, config)

      _ ->
        check_kill_notification_enabled(killmail, config)
    end
  end

  defp check_system_notification_enabled(killmail, config) do
    system_notifications_enabled = get_in(config, [:notifications, :kill, :system, :enabled])

    if system_notifications_enabled do
      {:ok, killmail}
    else
      {:error, :system_notifications_disabled}
    end
  end

  defp check_character_notification_enabled(killmail, config) do
    character_notifications_enabled =
      get_in(config, [:notifications, :kill, :character, :enabled])

    if character_notifications_enabled do
      {:ok, killmail}
    else
      {:error, :character_notifications_disabled}
    end
  end

  defp check_kill_notification_enabled(killmail, config) do
    kill_notifications_enabled = get_in(config, [:notifications, :kill, :enabled])

    if kill_notifications_enabled do
      {:ok, killmail}
    else
      {:error, :kill_notifications_disabled}
    end
  end

  # Checks if we should notify using just zkill data
  defp should_notify_without_esi?(zkb_data) do
    system_id = get_in(zkb_data, ["solar_system_id"])
    victim = get_in(zkb_data, ["victim"])
    killmail_id = get_in(zkb_data, ["killmail_id"])

    with {:ok, system_tracked} <- check_system_tracking(system_id),
         {:ok, character_tracked} <- check_character_tracking(victim) do
      result =
        if system_tracked or character_tracked do
          {:ok, %{should_notify: true}}
        else
          {:ok, %{should_notify: false, reason: :no_tracked_entities}}
        end

      result
    else
      error ->
        AppLogger.kill_error("Error checking notification requirements",
          error: inspect(error),
          kill_id: killmail_id,
          system: get_system_name(system_id),
          module: __MODULE__
        )

        error
    end
  end

  defp check_system_tracking(nil), do: {:ok, false}

  defp check_system_tracking(system_id) do
    case system_module().is_tracked?(system_id) do
      {:ok, tracked} -> {:ok, tracked}
      {:error, reason} -> {:error, reason}
      true -> {:ok, true}
      false -> {:ok, false}
      other -> {:error, {:invalid_system_tracking_response, other}}
    end
  end

  defp check_character_tracking(nil), do: {:ok, false}

  defp check_character_tracking(victim) do
    case victim do
      %{"character_id" => id} when not is_nil(id) ->
        case character_module().is_tracked?(id) do
          {:ok, tracked} -> {:ok, tracked}
          {:error, reason} -> {:error, reason}
          true -> {:ok, true}
          false -> {:ok, false}
          other -> {:error, {:invalid_character_tracking_response, other}}
        end

      _ ->
        {:ok, false}
    end
  end

  defp system_module do
    Application.get_env(:wanderer_notifier, :system_module)
  end

  defp character_module do
    Application.get_env(:wanderer_notifier, :character_module)
  end

  defp handle_notification_sent(enriched, ctx) do
    case Notification.send_kill_notification(enriched, enriched.killmail_id) do
      {:ok, _} ->
        Stats.track_notification_sent()
        log_outcome(enriched, ctx, persisted: true, notified: true, reason: nil)
        {:ok, enriched.killmail_id}

      {:error, reason} ->
        handle_error(enriched, ctx, reason)
    end
  end

  defp handle_notification_skipped(kill_id, system_id, reason) do
    Stats.track_processing_complete({:ok, :skipped})
    system_name = get_system_name(system_id)

    reason_emoji = get_reason_emoji(reason)
    reason_text = get_reason_text(reason)

    AppLogger.kill_info("💀 #{reason_emoji} ##{kill_id} | #{system_name} | #{reason_text}")

    {:ok, :skipped}
  end

  defp handle_error(data, ctx, reason) do
    Stats.track_processing_error()
    log_error(data, ctx, reason)
    {:error, reason}
  end

  # Helper to ensure a proper Context struct
  defp ensure_context(%Context{} = ctx), do: ctx
  defp ensure_context(_), do: Context.new()

  # — build_killmail/1 — fetches ESI and wraps in your Killmail struct
  @spec build_killmail(zkb_data) :: {:ok, Killmail.t()} | {:error, term()}
  defp build_killmail(%{"killmail_id" => id} = zkb_data) do
    hash = get_in(zkb_data, ["zkb", "hash"])
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = "killmail:#{id}"

    # Try cache first
    case Cachex.get(cache_name, cache_key) do
      {:ok, cached_data} when not is_nil(cached_data) ->
        build_killmail_from_cache(id, zkb_data, cached_data)

      _ ->
        fetch_killmail_from_esi(id, hash, zkb_data, cache_name, cache_key)
    end
  end

  defp build_killmail(_), do: {:error, :invalid_payload}

  defp build_killmail_from_cache(id, zkb_data, cached_data) do
    zkb_data = Map.get(zkb_data, "zkb", %{})
    killmail = Killmail.new(id, zkb_data, cached_data)
    {:ok, killmail}
  end

  defp fetch_killmail_from_esi(id, hash, zkb_data, cache_name, cache_key) do
    case esi_service().get_killmail(id, hash, []) do
      {:ok, esi_data} when is_map(esi_data) and map_size(esi_data) > 0 ->
        handle_valid_esi_data(id, zkb_data, esi_data, cache_name, cache_key)

      {:ok, nil} ->
        log_nil_esi_data(id)

      {:ok, invalid_data} ->
        log_invalid_esi_data(id, invalid_data)

      error ->
        log_error(zkb_data, nil, error)
        {:error, :create_failed}
    end
  end

  defp handle_valid_esi_data(id, zkb_data, esi_data, cache_name, cache_key) do
    # Only cache valid ESI data
    Cachex.put(cache_name, cache_key, esi_data)
    zkb_data = Map.get(zkb_data, "zkb", %{})
    killmail = Killmail.new(id, zkb_data, esi_data)
    {:ok, killmail}
  end

  defp log_nil_esi_data(id) do
    AppLogger.api_error("Received nil ESI data for killmail",
      kill_id: id,
      module: __MODULE__
    )

    {:error, :esi_data_missing}
  end

  defp log_invalid_esi_data(id, invalid_data) do
    AppLogger.api_error("Received invalid ESI data for killmail",
      kill_id: id,
      data: inspect(invalid_data),
      module: __MODULE__
    )

    {:error, :invalid_esi_data}
  end

  # — enrich/1 — delegates to your enrichment logic
  @spec enrich(Killmail.t()) :: {:ok, Killmail.t()} | {:error, term()}
  defp enrich(killmail) do
    case Enrichment.enrich_killmail_data(killmail) do
      {:ok, enriched} -> restore_system_id(enriched, killmail)
      error -> error
    end
  rescue
    e in @timeout_error ->
      AppLogger.api_error("ESI timeout during enrichment",
        error: inspect(e),
        module: __MODULE__,
        kill_id: killmail.killmail_id,
        service: "ESI"
      )

      {:error, :timeout}

    e in @api_error ->
      AppLogger.api_error("ESI API error during enrichment",
        error: inspect(e),
        message: Exception.message(e),
        module: __MODULE__,
        kill_id: killmail.killmail_id,
        service: "ESI"
      )

      {:error, :api_error}

    e ->
      # Re-raise any other errors
      reraise(e, __STACKTRACE__)
  end

  # Restores system_id if it was lost during enrichment
  defp restore_system_id(enriched, original) do
    system_id_after = Map.get(enriched, :system_id)
    esi_system_id_after = get_in(enriched, [:esi_data, "solar_system_id"])
    original_esi_system_id = get_in(original, [:esi_data, "solar_system_id"])

    if is_nil(system_id_after) && (esi_system_id_after || original_esi_system_id) do
      {:ok, Map.put(enriched, :system_id, esi_system_id_after || original_esi_system_id)}
    else
      {:ok, enriched}
    end
  end

  # — Logging & metrics helpers ———————————————————————————————————————————

  defp log_outcome(killmail, _ctx, opts) do
    kill_id = if killmail, do: killmail.killmail_id, else: "unknown"
    system_name = get_system_name_from_killmail(killmail)
    notified = Keyword.get(opts, :notified, false)
    reason = Keyword.get(opts, :reason)

    if notified do
      AppLogger.kill_info("💀 ✅ Killmail #{kill_id} | #{system_name} | Notification sent")
    else
      log_skipped_outcome(kill_id, system_name, reason)
    end

    :ok
  end

  defp log_skipped_outcome(kill_id, system_name, reason) do
    reason_emoji = get_reason_emoji(reason)
    reason_text = get_reason_text(reason)

    AppLogger.kill_info("💀 #{reason_emoji} Killmail #{kill_id} | #{system_name} | #{reason_text}")
  end

  defp get_reason_emoji(reason) do
    case reason do
      :no_tracked_entities -> "🚫"
      :notifications_disabled -> "⏸️"
      :system_notifications_disabled -> "🗺️❌"
      :character_notifications_disabled -> "👤❌"
      _ -> "❌"
    end
  end

  defp get_reason_text(reason) do
    case reason do
      :no_tracked_entities -> "No tracked entities"
      :notifications_disabled -> "Notifications disabled"
      :system_notifications_disabled -> "System notifications disabled"
      :character_notifications_disabled -> "Character notifications disabled"
      _ -> reason || "Unknown reason"
    end
  end

  # Get system name from killmail in order of preference
  defp get_system_name_from_killmail(killmail) when is_map(killmail) do
    cond do
      # Try enriched system_name field first
      killmail.system_name && killmail.system_name != "" ->
        killmail.system_name

      # Try ESI data solar_system_name
      esi_system_name = get_in(killmail, [:esi_data, "solar_system_name"]) ->
        esi_system_name

      # Try getting system name from system_id
      system_id = killmail.system_id || get_in(killmail, [:esi_data, "solar_system_id"]) ->
        get_system_name(system_id)

      # Fallback
      true ->
        "unknown"
    end
  end

  defp get_system_name_from_killmail(_), do: "unknown"

  defp log_error(data, ctx, reason) do
    kill_id =
      case extract_killmail_id(data) do
        {:ok, id} -> id
        {:error, _} -> "unknown"
      end

    context_id = if ctx, do: ctx.killmail_id, else: nil
    system_name = get_system_name(get_in(data, ["solar_system_id"]))

    AppLogger.kill_error("Pipeline error processing killmail",
      kill_id: kill_id,
      context_id: context_id,
      system: system_name,
      module: __MODULE__,
      error: inspect(reason),
      source: get_in(ctx, [:options, :source])
    )

    :ok
  end

  defp get_system_name(nil), do: "unknown"

  defp get_system_name(system_id) do
    case esi_service().get_system_info(system_id, []) do
      {:ok, data} ->
        case data do
          %{"name" => name} -> name
          _ -> "System #{system_id}"
        end

      _error ->
        "System #{system_id}"
    end
  end

  defp config_module do
    Application.get_env(:wanderer_notifier, :config_module, WandererNotifier.Config)
  end

  defp deduplication_module do
    Application.get_env(:wanderer_notifier, :deduplication_module)
  end

  @doc """
  Returns the configured killmail pipeline module.
  This allows for dependency injection and testing by swapping the pipeline module.
  """
  def killmail_pipeline do
    Application.get_env(
      :wanderer_notifier,
      :killmail_pipeline,
      WandererNotifier.Killmail.Pipeline
    )
  end
end
