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

    AppLogger.kill_info("Processing killmail",
      kill_id: get_in(zkb_data, ["killmail_id"]),
      system_id: system_id,
      victim: get_in(zkb_data, ["victim", "character_id"]),
      module: __MODULE__
    )

    # First check if we should notify without ESI
    case should_notify_without_esi?(zkb_data) do
      {:ok, %{should_notify: false, reason: reason}} ->
        AppLogger.kill_info("Skipping killmail - no notification needed",
          kill_id: get_in(zkb_data, ["killmail_id"]),
          reason: reason,
          system_id: system_id
        )

        handle_notification_skipped(context, reason)

      {:ok, %{should_notify: true}} ->
        # Then ensure we have a valid killmail_id
        with {:ok, killmail_id} <- extract_killmail_id(zkb_data) do
          AppLogger.kill_info("Processing new killmail",
            kill_id: killmail_id,
            system_id: system_id
          )

          # Process the killmail
          case process_new_killmail(zkb_data, context) do
            {:ok, killmail} ->
              # Send notification for the processed killmail
              handle_notification_sent(killmail, context)

            error ->
              AppLogger.kill_error("Failed to process killmail",
                kill_id: killmail_id,
                error: inspect(error),
                system_id: system_id
              )

              error
          end
        else
          {:error, :invalid_killmail_id} ->
            AppLogger.kill_error("Invalid killmail ID",
              data: inspect(zkb_data, pretty: true),
              system_id: system_id
            )

            {:error, :invalid_killmail_id}

          error ->
            AppLogger.kill_error("Error extracting killmail ID",
              error: inspect(error),
              data: inspect(zkb_data, pretty: true),
              system_id: system_id
            )

            {:error, error}
        end

      {:error, reason} ->
        AppLogger.kill_error("Error checking notification requirements",
          error: inspect(reason),
          kill_id: get_in(zkb_data, ["killmail_id"]),
          system_id: system_id
        )

        handle_error(zkb_data, context, reason)
    end
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
    killmail_id = get_in(zkb_data, ["killmail_id"])
    system_id = get_in(zkb_data, ["solar_system_id"])

    AppLogger.kill_info("Processing new killmail",
      kill_id: killmail_id,
      system_id: system_id
    )

    case should_notify_without_esi?(zkb_data) do
      {:ok, %{should_notify: false, reason: reason}} ->
        AppLogger.kill_info("Skipping killmail - no notification needed",
          kill_id: killmail_id,
          reason: reason,
          system_id: system_id
        )

        handle_notification_skipped(ctx, reason)

      {:ok, %{should_notify: true}} ->
        AppLogger.kill_info("Processing tracked killmail",
          kill_id: killmail_id,
          system_id: system_id
        )

        process_tracked_killmail(zkb_data, ctx)

      {:error, reason} ->
        AppLogger.kill_error("Error checking notification requirements",
          error: inspect(reason),
          kill_id: killmail_id,
          system_id: system_id
        )

        handle_error(zkb_data, ctx, reason)
    end
  end

  # Process a killmail that has tracked entities
  defp process_tracked_killmail(zkb_data, ctx) do
    killmail_id = get_in(zkb_data, ["killmail_id"])
    system_id = get_in(zkb_data, ["solar_system_id"])

    AppLogger.kill_info("Building and enriching killmail",
      kill_id: killmail_id,
      system_id: system_id
    )

    with {:ok, killmail} <- build_killmail(zkb_data),
         _ =
           AppLogger.kill_info("Killmail built successfully",
             kill_id: killmail_id,
             system_id: system_id
           ),
         {:ok, enriched} <- enrich(killmail),
         _ =
           AppLogger.kill_info("Killmail enriched successfully",
             kill_id: killmail_id,
             system_id: system_id
           ) do
      check_notification_requirements(enriched, ctx)
    else
      {:error, reason} ->
        AppLogger.kill_error("Failed to process tracked killmail",
          error: inspect(reason),
          kill_id: killmail_id,
          system_id: system_id
        )

        handle_error(zkb_data, ctx, reason)
    end
  end

  # Check if notification should be sent for an enriched killmail
  defp check_notification_requirements(killmail, character_id) do
    config = WandererNotifier.Config.get_config()
    killmail_id = killmail.killmail_id
    system_id = killmail.system_id

    AppLogger.kill_info("Checking notification requirements",
      kill_id: killmail_id,
      system_id: system_id,
      notifications_enabled: config.notifications_enabled,
      system_notifications_enabled: config.system_notifications_enabled,
      character_notifications_enabled: config.character_notifications_enabled,
      kill_notifications_enabled: config.kill_notifications_enabled
    )

    if config.notifications_enabled do
      case killmail do
        %{system_id: system_id} when not is_nil(system_id) ->
          if config.system_notifications_enabled do
            AppLogger.kill_info("System notification requirements met",
              kill_id: killmail_id,
              system_id: system_id
            )

            {:ok, killmail}
          else
            AppLogger.kill_info("System notifications disabled",
              kill_id: killmail_id,
              system_id: system_id
            )

            {:error, :system_notifications_disabled}
          end

        %{victim: %{character_id: ^character_id}} ->
          if config.character_notifications_enabled do
            AppLogger.kill_info("Character notification requirements met",
              kill_id: killmail_id,
              character_id: character_id
            )

            {:ok, killmail}
          else
            AppLogger.kill_info("Character notifications disabled",
              kill_id: killmail_id,
              character_id: character_id
            )

            {:error, :character_notifications_disabled}
          end

        _ ->
          if config.kill_notifications_enabled do
            AppLogger.kill_info("Kill notification requirements met",
              kill_id: killmail_id
            )

            {:ok, killmail}
          else
            AppLogger.kill_info("Kill notifications disabled",
              kill_id: killmail_id
            )

            {:error, :kill_notifications_disabled}
          end
      end
    else
      AppLogger.kill_info("All notifications disabled",
        kill_id: killmail_id
      )

      {:error, :notifications_disabled}
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

  defp handle_notification_skipped(ctx, reason) do
    Stats.track_processing_complete({:ok, :skipped})
    # Get killmail_id from context if available, otherwise use "unknown"
    kill_id = if ctx && ctx.killmail_id, do: ctx.killmail_id, else: "unknown"
    system_name = get_system_name(ctx && ctx.system_id)

    AppLogger.kill_info("Killmail processed but not notified",
      kill_id: kill_id,
      system: system_name,
      module: __MODULE__,
      reason: reason,
      source: get_in(ctx, [:options, :source])
    )

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
        zkb_data = Map.get(zkb_data, "zkb", %{})
        killmail = Killmail.new(id, zkb_data, cached_data)
        {:ok, killmail}

      _ ->
        case esi_service().get_killmail(id, hash, []) do
          {:ok, esi_data} when is_map(esi_data) and map_size(esi_data) > 0 ->
            # Only cache valid ESI data
            Cachex.put(cache_name, cache_key, esi_data)
            zkb_data = Map.get(zkb_data, "zkb", %{})
            killmail = Killmail.new(id, zkb_data, esi_data)
            {:ok, killmail}

          {:ok, nil} ->
            AppLogger.api_error("Received nil ESI data for killmail",
              kill_id: id,
              module: __MODULE__
            )

            {:error, :esi_data_missing}

          {:ok, invalid_data} ->
            AppLogger.api_error("Received invalid ESI data for killmail",
              kill_id: id,
              data: inspect(invalid_data),
              module: __MODULE__
            )

            {:error, :invalid_esi_data}

          error ->
            log_error(zkb_data, nil, error)
            {:error, :create_failed}
        end
    end
  end

  defp build_killmail(_), do: {:error, :invalid_payload}

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

  defp log_outcome(killmail, ctx, opts) do
    kill_id = if killmail, do: killmail.killmail_id, else: "unknown"
    context_id = if ctx, do: ctx.killmail_id, else: nil
    system_name = get_system_name(get_in(killmail, [:system_id]))

    if opts[:notified] do
      AppLogger.kill_info("Killmail processed and notified",
        kill_id: kill_id,
        context_id: context_id,
        system: system_name,
        module: __MODULE__,
        source: get_in(ctx, [:options, :source])
      )
    else
      AppLogger.kill_info("Killmail processed but not notified",
        kill_id: kill_id,
        context_id: context_id,
        system: system_name,
        module: __MODULE__,
        reason: opts[:reason],
        source: get_in(ctx, [:options, :source])
      )
    end

    :ok
  end

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
    case esi_service().get_system_info(system_id) do
      {:ok, data} ->
        case data do
          %{"name" => name} -> name
          _ -> "System #{system_id}"
        end

      _error ->
        "System #{system_id}"
    end
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
