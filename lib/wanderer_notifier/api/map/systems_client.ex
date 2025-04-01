defmodule WandererNotifier.Api.Map.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
  """
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Map.SystemStaticInfo
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  @doc """
  Updates the systems in the cache.

  If cached_systems is provided, it will also identify and notify about new systems.

  ## Parameters
    - cached_systems: Optional list of cached systems for comparison

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems(cached_systems \\ nil) do
    # Log cache status before update
    pre_cache = CacheRepo.get(CacheKeys.map_systems())
    pre_cache_size = if is_list(pre_cache), do: length(pre_cache), else: 0
    AppLogger.api_info("[SystemsClient] Pre-update cache status: #{pre_cache_size} systems")

    case UrlBuilder.build_url("map/systems") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()

        # Process the systems request
        case Client.get(url, headers) do
          {:ok, response} ->
            process_systems_response(response, cached_systems)

          {:error, reason} ->
            AppLogger.api_error("[SystemsClient] HTTP request failed: #{inspect(reason)}")
            {:error, {:http_error, reason}}
        end

      {:error, reason} ->
        AppLogger.api_error("[SystemsClient] Failed to build URL or headers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_systems_response(response, cached_systems) do
    alias WandererNotifier.Api.Http.ErrorHandler

    case ErrorHandler.handle_http_response(response, domain: :map, tag: "SystemsClient") do
      {:ok, parsed_response} ->
        # Process and cache the system data
        process_and_cache_systems(parsed_response, cached_systems)

      {:error, reason} ->
        AppLogger.api_error("[SystemsClient] Failed to process API response: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_and_cache_systems(parsed_response, cached_systems) do
    # Extract systems data with fallbacks for different API formats
    systems_data = extract_systems_data(parsed_response)

    AppLogger.api_info("[SystemsClient] Received #{length(systems_data)} systems from API")

    # Create MapSystem structs
    systems = Enum.map(systems_data, &MapSystem.new/1)

    # Filter systems based on configuration
    tracked_systems = filter_systems_for_tracking(systems)

    # Enrich all systems before caching any of them
    enriched_systems = enrich_tracked_systems(tracked_systems)

    # Cache the ENRICHED systems
    AppLogger.api_info("[SystemsClient] Caching #{length(enriched_systems)} enriched systems")
    updated_systems = update_systems_cache(enriched_systems)

    # Verify systems were cached successfully
    verify_systems_cached(updated_systems)

    # Check for new systems
    AppLogger.api_info("[SystemsClient] Checking for new systems to notify about")
    notify_new_systems(enriched_systems, cached_systems)

    # Return the enriched systems
    {:ok, updated_systems}
  rescue
    e ->
      # Log the error with full details
      AppLogger.api_error(
        "[SystemsClient] Exception in process_and_cache_systems",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      # Return any successfully cached systems if possible
      cached = cached_systems || CacheRepo.get(CacheKeys.map_systems()) || []
      {:ok, cached}
  end

  # Extract systems data from different response formats
  defp extract_systems_data(parsed_response) do
    case parsed_response do
      %{"data" => data} when is_list(data) -> data
      %{"systems" => systems} when is_list(systems) -> systems
      data when is_list(data) -> data
      _ -> []
    end
  end

  # Filter systems based on configuration
  defp filter_systems_for_tracking(systems) do
    # Use the Features module for configuration
    track_kspace_systems = Features.track_kspace_systems?()
    # Filter the systems based on the configuration
    if track_kspace_systems do
      # If tracking K-space systems is enabled, return all systems
      systems
    else
      # If tracking K-space systems is disabled, filter out K-space systems
      systems
      |> Enum.filter(fn system ->
        # Keep only wormhole systems (class 1-6)
        system.security_class in ["C1", "C2", "C3", "C4", "C5", "C6", "C13"]
      end)
    end
  end

  # Enrich tracked systems with static data
  defp enrich_tracked_systems(tracked_systems) do
    # Create a map of system_id => system for easier lookup and replacement
    system_map =
      Enum.reduce(tracked_systems, %{}, fn sys, acc ->
        Map.put(acc, sys.solar_system_id, sys)
      end)

    # Process each system
    enriched_map = process_systems_for_enrichment(tracked_systems, system_map)

    # Convert the map back to a list
    enriched_systems = Map.values(enriched_map)

    enriched_systems
  end

  # Process each system for enrichment
  defp process_systems_for_enrichment(tracked_systems, system_map) do
    Enum.reduce(tracked_systems, system_map, fn system, acc ->
      if MapSystem.wormhole?(system) do
        process_wormhole_system(system, acc)
      else
        process_non_wormhole_system(system, acc)
      end
    end)
  end

  # Process a wormhole system with enrichment
  defp process_wormhole_system(system, acc) do
    # Try to enrich with a strict timeout
    task =
      Task.async(fn ->
        try do
          SystemStaticInfo.enrich_system(system)
        rescue
          e ->
            AppLogger.api_error(
              "[SystemsClient] Enrichment failed for system #{system.name}: #{Exception.message(e)}"
            )

            {:error, :exception}
        end
      end)

    # Wait for enrichment with a 2 second timeout per system
    case Task.yield(task, 2_000) do
      {:ok, {:ok, enriched_system}} ->
        # Update the map with the enriched system
        Map.put(acc, system.solar_system_id, enriched_system)

      _ ->
        # Enrichment error or timeout - kill the task and keep the original system
        Task.shutdown(task, :brutal_kill)

        AppLogger.api_debug(
          "[SystemsClient] Using basic system info for #{system.name} (enrichment skipped or failed)"
        )

        # Ensure statics is never nil
        updated_system = ensure_statics_not_nil(system)
        Map.put(acc, system.solar_system_id, updated_system)
    end
  end

  # Process a non-wormhole system (no enrichment needed)
  defp process_non_wormhole_system(system, acc) do
    # Update the map with the original system
    Map.put(acc, system.solar_system_id, system)
  end

  # Ensure statics field is never nil
  defp ensure_statics_not_nil(system) do
    if is_nil(system.statics) do
      %{system | statics: []}
    else
      system
    end
  end

  # Make sure systems are actually in the cache
  defp verify_systems_cached(systems) do
    # Wait a moment to ensure cache has time to update
    Process.sleep(100)

    # Check the cache
    cached_systems = CacheRepo.get(CacheKeys.map_systems())
    cached_count = if is_list(cached_systems), do: length(cached_systems), else: 0
    expected_count = length(systems)

    AppLogger.api_info(
      "[SystemsClient] Cache verification - Expected: #{expected_count}, Found: #{cached_count}"
    )

    # Log some sample systems for debugging
    if is_list(cached_systems) && length(cached_systems) > 0 do
      sample = List.first(cached_systems)
      AppLogger.api_debug("[SystemsClient] Cache sample: #{inspect(sample, limit: 200)}")
    else
      AppLogger.api_error("[SystemsClient] CRITICAL: Cache appears to be empty after updating!")
    end
  end

  # Update the systems cache with the latest data
  defp update_systems_cache(systems) do
    # Use a hard-coded long TTL (24 hours) for persistence
    long_ttl = 86_400

    AppLogger.api_info(
      "[SystemsClient] Updating systems cache with #{length(systems)} systems and TTL: #{long_ttl}"
    )

    # Log the current cache content for verification
    current_systems = CacheRepo.get(CacheKeys.map_systems()) || []
    current_count = length(current_systems)
    AppLogger.api_info("[SystemsClient] Current systems in cache before update: #{current_count}")

    try do
      # First update the main caches - these are critical operations
      result = CacheRepo.set(CacheKeys.map_systems(), systems, long_ttl)
      AppLogger.api_info("[SystemsClient] Main cache set result: #{inspect(result)}")

      system_ids = Enum.map(systems, & &1.solar_system_id)
      CacheRepo.set(CacheKeys.map_system_ids(), system_ids, long_ttl)

      # Now handle individual system caching and tracking concurrently
      # Use Task.async_stream with a reasonable concurrency limit
      systems
      |> Task.async_stream(
        fn system ->
          system_id = system.solar_system_id

          if system_id do
            # Cache individual system
            system_cache_key = CacheKeys.system(system_id)
            CacheRepo.set(system_cache_key, system, long_ttl)
            # Mark as tracked
            CacheHelpers.add_system_to_tracked(system_id, system)
          end
        end,
        max_concurrency: 5,
        timeout: 5000
      )
      |> Stream.run()

      # Verify the update with brief delay
      Process.sleep(100)
      post_update_count = length(CacheRepo.get(CacheKeys.map_systems()) || [])

      AppLogger.api_info(
        "[SystemsClient] Systems cache updated - stored: #{post_update_count}, expected: #{length(systems)}"
      )

      systems
    rescue
      e ->
        AppLogger.api_error(
          "[SystemsClient] Exception in update_systems_cache",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Return systems anyway to prevent cascading failures
        systems
    end
  end

  @doc """
  Returns systems from the cache, or fetches and caches them if they're not available.
  This is similar to the character approach and provides a direct way to get systems.

  ## Returns
    - list of systems on success (may be empty)
  """
  def get_systems do
    # Try to get systems from cache first
    case CacheRepo.get(CacheKeys.map_systems()) do
      systems when is_list(systems) and length(systems) > 0 ->
        AppLogger.api_info("[SystemsClient] Retrieved #{length(systems)} systems from cache")
        systems

      nil ->
        # Cache key doesn't exist
        AppLogger.api_warn(
          "[SystemsClient] No systems found in cache (nil), returning empty list"
        )

        []

      [] ->
        # Empty list
        AppLogger.api_warn(
          "[SystemsClient] Cache key exists but systems list is empty, returning empty list"
        )

        []

      other ->
        # Unexpected format
        AppLogger.api_warn(
          "[SystemsClient] Unexpected format in cache",
          value_type: typeof(other),
          value_preview: inspect(other, limit: 50)
        )

        []
    end
  end

  # Helper function to determine type for logging
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_integer(term), do: "integer"
  defp typeof(term) when is_float(term), do: "float"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(term) when is_pid(term), do: "pid"
  defp typeof(term) when is_reference(term), do: "reference"
  defp typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
  defp typeof(_), do: "unknown"

  @doc """
  Returns a system for testing notifications.
  Attempts to enrich a wormhole system, but only for notification tests.

  ## Returns
    - {:ok, system} on success
    - {:error, reason} on failure
  """
  def get_system_for_notification do
    # Try to get systems from cache first
    systems = get_systems()

    # Check if we have systems in cache
    if is_list(systems) and length(systems) > 0 do
      # Select just one random system for notification
      selected_system = Enum.random(systems)

      # Log selection
      AppLogger.api_info(
        "[SystemsClient] Selected system #{selected_system.name} for notification test"
      )

      # Handle wormhole systems differently
      if MapSystem.wormhole?(selected_system) do
        # Try to enrich with a timeout using Task
        AppLogger.api_info(
          "[SystemsClient] Attempting to enrich wormhole system #{selected_system.name} for test notification"
        )

        # Try to enrich the wormhole system
        enrich_system_with_timeout(selected_system)
      else
        # Non-wormhole systems don't need enrichment
        {:ok, selected_system}
      end
    else
      # No systems in cache, return error
      AppLogger.api_error("[SystemsClient] No systems found in cache for notification")
      {:error, :no_systems_in_cache}
    end
  end

  # Helper to enrich a system with a timeout
  defp enrich_system_with_timeout(system) do
    # Create a task for the enrichment to add timeout handling
    task =
      Task.async(fn ->
        try do
          SystemStaticInfo.enrich_system(system)
        rescue
          e ->
            AppLogger.api_error(
              "[SystemsClient] Enrichment failed with exception: #{Exception.message(e)}"
            )

            {:error, :exception}
        end
      end)

    # Wait for enrichment with a timeout (5 seconds maximum)
    case Task.yield(task, 5_000) do
      {:ok, {:ok, enriched_system}} ->
        AppLogger.api_info("[SystemsClient] Successfully enriched system for test notification")

        {:ok, enriched_system}

      {:ok, {:error, reason}} ->
        AppLogger.api_warn(
          "[SystemsClient] Enrichment failed: #{inspect(reason)}. Using basic system."
        )

        {:ok, system}

      nil ->
        # Enrichment took too long, kill the task
        Task.shutdown(task, :brutal_kill)

        AppLogger.api_warn(
          "[SystemsClient] Enrichment timed out after 5 seconds. Using basic system."
        )

        {:ok, system}
    end
  end

  @doc """
  Identifies new systems by comparing with cached systems and sends notifications.

  ## Parameters
    - fresh_systems: List of newly fetched systems
    - cached_systems: List of previously cached systems

  ## Returns
    - {:ok, added_systems} with list of newly added systems
  """
  def notify_new_systems(fresh_systems, cached_systems) do
    if Config.system_notifications_enabled?() do
      process_system_notifications(fresh_systems, cached_systems)
    else
      AppLogger.api_info("[SystemsClient] System notifications are disabled, skipping")
      {:ok, []}
    end
  end

  defp process_system_notifications(fresh_systems, cached_systems) do
    # Ensure we have both fresh and cached systems as lists
    fresh = fresh_systems || []
    cached = cached_systems || []

    # Find new systems and send notifications
    added_systems = find_new_systems(fresh, cached)
    log_added_systems(added_systems)

    # Send notifications for each new system
    Enum.each(added_systems, &send_system_notification/1)

    {:ok, added_systems}
  end

  defp find_new_systems(_fresh, []) do
    # If there's no cached systems, this is probably the first run
    # Don't notify about all systems to avoid spamming
    AppLogger.api_info(
      "[SystemsClient] No cached systems found; skipping new system notifications on startup"
    )

    []
  end

  defp find_new_systems(fresh, cached) do
    # Handle both struct and map types in cached systems
    Enum.filter(fresh, fn fresh_sys ->
      not system_exists_in_cache?(fresh_sys, cached)
    end)
  end

  defp system_exists_in_cache?(fresh_sys, cached) do
    fresh_id = extract_system_id(fresh_sys)

    Enum.any?(cached, fn cached_sys ->
      cached_id = extract_system_id(cached_sys)
      fresh_id == cached_id
    end)
  end

  defp extract_system_id(system) do
    # Check solar_system_id first (most common field)
    system_id = extract_id_field(system, [:solar_system_id, "solar_system_id"])

    # If not found, try more generic id fields
    if system_id, do: system_id, else: extract_id_field(system, [:id, "id"])
  end

  # Helper to extract ID from various field names
  defp extract_id_field(system, field_names) do
    Enum.find_value(field_names, fn field ->
      cond do
        is_struct(system) && Map.has_key?(system, field) -> Map.get(system, field)
        is_map(system) && Map.has_key?(system, field) -> Map.get(system, field)
        true -> nil
      end
    end)
  end

  defp log_added_systems([]), do: :ok

  defp log_added_systems(added_systems) do
    AppLogger.api_info(
      "[SystemsClient] Found #{length(added_systems)} new systems to notify about"
    )
  end

  defp send_system_notification(map_system) do
    AppLogger.api_info("Sending notification for new system: #{map_system.name}")
    NotifierFactory.notify(:send_new_system_notification, [map_system])
  end
end
