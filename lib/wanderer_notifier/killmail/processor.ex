defmodule WandererNotifier.Killmail.Processor do
  @moduledoc """
  Processes killmails and handles notifications.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Context

  @doc """
  Initializes the killmail processor.
  """
  def init do
    AppLogger.info("Initializing killmail processor")
    :ok
  end

  @doc """
  Schedules killmail-related tasks.
  """
  def schedule_tasks do
    AppLogger.info("Scheduling killmail tasks")
    :ok
  end

  @doc """
  Processes a ZKillboard websocket message.

  ## Parameters
    - message: The message to process
    - state: The current state

  ## Returns
    - {:ok, kill_id} if processed successfully
    - {:ok, :skipped} if processing was skipped
    - state on error or when notification is not needed
  """
  def process_zkill_message(message, state) do
    with {:ok, kill_data} <- decode_zkill_message(message),
         {:ok, should_notify, reason} <- determine_notification(kill_data) do
      if should_notify do
        process_kill_data(kill_data, state)
      else
        log_skipped_kill(kill_data, reason)
        # Return state when notification is not needed, to match the documentation
        state
      end
    else
      {:error, reason} ->
        AppLogger.error("Failed to process ZKill message", %{
          error: inspect(reason),
          message: inspect(message)
        })

        state
    end
  end

  @doc """
  Logs killmail processing statistics.
  """
  def log_stats do
    AppLogger.info("Logging killmail stats")
    :ok
  end

  @doc """
  Gets recent kills from the cache.

  ## Returns
    - {:ok, kills} on success
    - {:error, reason} on failure
  """
  def get_recent_kills do
    case cache_repo().get(WandererNotifier.Cache.Keys.zkill_recent_kills()) do
      {:ok, [kill | _]} -> {:ok, kill}
      _ -> {:error, :no_recent_kills}
    end
  end

  @doc """
  Processes a kill notification.

  ## Parameters
    - kill_data: The kill data to process
    - context: The context for processing

  ## Returns
    - {:ok, kill_id} on success
    - {:error, reason} on failure
  """
  def process_kill_data(kill_data, context) do
    kill_id = Map.get(kill_data, "killmail_id", "unknown")

    AppLogger.kill_info("Processing kill data", %{kill_id: kill_id})

    case killmail_pipeline().process_killmail(kill_data, context) do
      {:ok, enriched_kill} ->
        AppLogger.kill_info("Kill data processed successfully", %{kill_id: kill_id})

        # Handle the case when the pipeline returns :skipped
        if enriched_kill == :skipped do
          {:ok, :skipped}
        else
          # Only try to send notification if we got actual killmail data
          killmail_notification().send_kill_notification(enriched_kill, "kill", %{})
          {:ok, kill_id}
        end

      {:error, reason} = error ->
        AppLogger.kill_error("Failed to process kill data", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        error
    end
  end

  @doc """
  Sends a test kill notification.
  """
  def send_test_kill_notification do
    with {:ok, recent_kill} <- get_recent_kills(),
         kill_id = extract_kill_id(recent_kill),
         killmail = ensure_data_killmail(recent_kill),
         {:ok, enriched_kill} <- killmail_pipeline().process_killmail(killmail, %Context{}) do
      killmail_notification().send_kill_notification(enriched_kill, "test", %{})
      {:ok, kill_id}
    else
      {:error, :no_recent_kills} ->
        AppLogger.kill_warn("No recent kills found in shared cache repository")
        {:error, :no_recent_kills}

      {:error, reason} ->
        error_message = "Cannot send test notification: #{reason}"
        AppLogger.kill_error(error_message)
        {:error, error_message}
    end
  end

  # Private helper functions

  defp decode_zkill_message(message) do
    case Jason.decode(message) do
      {:ok, decoded} -> {:ok, decoded}
      error -> error
    end
  end

  defp determine_notification(kill_data) do
    case WandererNotifier.Notifications.Determiner.Kill.should_notify?(kill_data) do
      {:ok, %{should_notify: true}} -> {:ok, true, nil}
      {:ok, %{should_notify: false, reason: reason}} -> {:ok, false, reason}
      _ -> {:error, :unexpected_response}
    end
  end

  defp log_skipped_kill(kill_data, reason) do
    system_id = Map.get(kill_data, "solar_system_id")
    killmail_id = Map.get(kill_data, "killmail_id")
    system_name = get_system_name(system_id)

    AppLogger.processor_info(
      "Skipping killmail: #{reason} (killmail_id=#{killmail_id}, system_id=#{system_id}, system_name=#{system_name})"
    )
  end

  defp get_system_name(system_id) do
    # First check the process dict cache to avoid repeated ESI calls for the same system
    process_cache_key = {:system_name_cache, system_id}
    cached_name = Process.get(process_cache_key)

    if cached_name do
      cached_name
    else
      try do
        case WandererNotifier.ESI.Service.get_system(system_id) do
          {:ok, %{"name" => name}} ->
            # Only cache successful results
            Process.put(process_cache_key, name)
            name

          {:error, _} ->
            # Don't cache failures - return a temporary value
            "Unknown (#{system_id})"

          _ ->
            "Unknown (#{system_id})"
        end
      rescue
        e ->
          AppLogger.api_error("Failed to get system name",
            system_id: system_id,
            error: Exception.message(e)
          )

          # Don't cache errors
          "Unknown (#{system_id})"
      end
    end
  end

  defp extract_kill_id(killmail) do
    cond do
      is_map(killmail) && Map.has_key?(killmail, :killmail_id) ->
        killmail.killmail_id

      is_map(killmail) && Map.has_key?(killmail, "killmail_id") ->
        killmail["killmail_id"]

      true ->
        "unknown"
    end
  end

  defp ensure_data_killmail(killmail) do
    if is_struct(killmail, WandererNotifier.Killmail.Killmail) do
      killmail
    else
      # Try to convert map to struct
      if is_map(killmail) do
        struct(WandererNotifier.Killmail.Killmail, Map.delete(killmail, :__struct__))
      else
        # Fallback empty struct with required fields
        %WandererNotifier.Killmail.Killmail{
          killmail_id: "unknown",
          zkb: %{}
        }
      end
    end
  end

  # Get dependencies from application config
  defp killmail_pipeline do
    Application.get_env(
      :wanderer_notifier,
      :killmail_pipeline,
      WandererNotifier.Killmail.Pipeline
    )
  end

  defp killmail_notification do
    Application.get_env(
      :wanderer_notifier,
      :killmail_notification,
      WandererNotifier.Notifications.KillmailNotification
    )
  end

  defp cache_repo do
    repo =
      Application.get_env(
        :wanderer_notifier,
        :cache_repo,
        WandererNotifier.Cache.CachexImpl
      )

    # Ensure the module is loaded and available
    if Code.ensure_loaded?(repo) do
      repo
    else
      # Log this only once per minute to avoid log spam
      cache_error_key = :cache_repo_error_logged
      last_logged = Process.get(cache_error_key)
      now = System.monotonic_time(:second)

      if is_nil(last_logged) || now - last_logged > 60 do
        AppLogger.error(
          "Cache repository module #{inspect(repo)} not available or not configured"
        )

        Process.put(cache_error_key, now)
      end

      # Return a dummy cache module that won't crash
      SafeCache
    end
  end

  # Fallback module that returns safe defaults to prevent crashes
  defmodule SafeCache do
    @moduledoc """
    A fallback module that provides safe access to cache functions when the real cache is unavailable.
    Returns default values to prevent application crashes when cache access fails.
    """
    def get(_key), do: {:error, :cache_not_available}
    def put(_key, _value), do: {:error, :cache_not_available}
    def delete(_key), do: {:error, :cache_not_available}
    def exists?(_key), do: false
  end
end
