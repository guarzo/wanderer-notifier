defmodule WandererNotifier.Infrastructure.Cache.Warming do
  @moduledoc """
  Cache warming utilities for improved application performance.

  Provides systematic cache pre-loading for frequently accessed data
  to reduce cold cache penalties. This module handles both synchronous
  and asynchronous cache warming with progress tracking.
  """

  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Infrastructure.Adapters.ESI.Service, as: ESI
  require Logger

  @type warming_result :: {:ok, integer()} | {:error, term()}
  @type progress_callback :: (integer(), integer() -> :ok) | nil

  # Batch sizes for warming operations (reduced to avoid rate limiting)
  @character_batch_size 10
  @system_batch_size 20
  @type_batch_size 20

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Warms the character cache with the provided character IDs.

  Returns the number of successfully cached characters.

  ## Examples
      iex> Warming.warm_character_cache([123, 456, 789])
      {:ok, 3}
  """
  @spec warm_character_cache([integer()]) :: warming_result()
  def warm_character_cache(character_ids) when is_list(character_ids) do
    warm_character_cache(character_ids, nil)
  end

  @spec warm_character_cache([integer()], progress_callback()) :: warming_result()
  def warm_character_cache(character_ids, progress_callback) when is_list(character_ids) do
    Logger.info("Starting character cache warming for #{length(character_ids)} characters")

    # First check what's already cached
    cached_results = Cache.get_characters_batch(character_ids)
    missing_ids = get_missing_ids(cached_results)

    if Enum.empty?(missing_ids) do
      Logger.info("All #{length(character_ids)} characters already cached")
      {:ok, length(character_ids)}
    else
      Logger.info("Warming cache for #{length(missing_ids)} missing characters")
      warm_missing_characters(missing_ids, character_ids, progress_callback)
    end
  end

  @doc """
  Warms the system cache with the provided system IDs.

  Returns the number of successfully cached systems.

  ## Examples
      iex> Warming.warm_system_cache([30000142, 30000143])
      {:ok, 2}
  """
  @spec warm_system_cache([integer()]) :: warming_result()
  def warm_system_cache(system_ids) when is_list(system_ids) do
    warm_system_cache(system_ids, nil)
  end

  @spec warm_system_cache([integer()], progress_callback()) :: warming_result()
  def warm_system_cache(system_ids, progress_callback) when is_list(system_ids) do
    Logger.info("Starting system cache warming for #{length(system_ids)} systems")

    # First check what's already cached
    cached_results = Cache.get_systems_batch(system_ids)
    missing_ids = get_missing_ids(cached_results)

    if Enum.empty?(missing_ids) do
      Logger.info("All #{length(system_ids)} systems already cached")
      {:ok, length(system_ids)}
    else
      Logger.info("Warming cache for #{length(missing_ids)} missing systems")
      warm_missing_systems(missing_ids, system_ids, progress_callback)
    end
  end

  @doc """
  Warms the universe type cache with the provided type IDs.

  Returns the number of successfully cached types.

  ## Examples
      iex> Warming.warm_universe_types([587, 588, 589])
      {:ok, 3}
  """
  @spec warm_universe_types([integer()]) :: warming_result()
  def warm_universe_types(type_ids) when is_list(type_ids) do
    warm_universe_types(type_ids, nil)
  end

  @spec warm_universe_types([integer()], progress_callback()) :: warming_result()
  def warm_universe_types(type_ids, progress_callback) when is_list(type_ids) do
    Logger.info("Starting universe type cache warming for #{length(type_ids)} types")

    # First check what's already cached
    cached_results = Cache.get_universe_types_batch(type_ids)
    missing_ids = get_missing_ids(cached_results)

    if Enum.empty?(missing_ids) do
      Logger.info("All #{length(type_ids)} types already cached")
      {:ok, length(type_ids)}
    else
      Logger.info("Warming cache for #{length(missing_ids)} missing types")
      warm_missing_types(missing_ids, type_ids, progress_callback)
    end
  end

  @doc """
  Warms essential data that is frequently accessed.

  This includes:
  - Common ship types
  - Common solar systems
  - NPC corporations

  ## Examples
      iex> Warming.warm_essential_data()
      :ok
  """
  @spec warm_essential_data() :: :ok
  def warm_essential_data do
    Logger.info("Warming essential cache data")

    # Common ship types (frigates, cruisers, battleships)
    common_ship_types = [
      # T1 Frigates
      # Minmatar
      582,
      583,
      584,
      585,
      # Caldari
      586,
      587,
      588,
      589,
      # Amarr
      590,
      591,
      592,
      593,
      # Gallente
      594,
      595,
      596,
      597,

      # T1 Cruisers
      # Minmatar
      620,
      621,
      622,
      623,
      # Caldari
      624,
      625,
      626,
      627,
      # Amarr
      628,
      629,
      630,
      631,
      # Gallente
      632,
      633,
      634,
      635
    ]

    # Common trade hub systems
    trade_hub_systems = [
      # Jita
      30_000_142,
      # Amarr
      30_002_187,
      # Dodixie
      30_002_659,
      # Hek
      30_002_053,
      # Rens
      30_002_510
    ]

    # Warm ship types in background
    Task.start(fn ->
      warm_universe_types(common_ship_types)
    end)

    # Warm systems in background
    Task.start(fn ->
      warm_system_cache(trade_hub_systems)
    end)

    :ok
  end

  @doc """
  Gets statistics about the warming operations.

  Returns information about what types of data can be warmed
  and recommended batch sizes.
  """
  @spec get_warming_stats() :: map()
  def get_warming_stats do
    %{
      character_batch_size: @character_batch_size,
      system_batch_size: @system_batch_size,
      type_batch_size: @type_batch_size,
      warming_types: [:characters, :systems, :universe_types],
      async_supported: true
    }
  end

  @doc """
  Asynchronously warms the character cache with progress tracking.

  The progress callback receives (completed, total) as arguments.

  ## Examples
      Warming.warm_character_cache_async([123, 456, 789], fn done, total ->
        IO.puts("Progress: " <> to_string(done) <> "/" <> to_string(total))
      end)
  """
  @spec warm_character_cache_async([integer()], progress_callback()) :: :ok
  def warm_character_cache_async(character_ids, progress_callback \\ nil) do
    Task.start(fn ->
      warm_character_cache(character_ids, progress_callback)
    end)

    :ok
  end

  @doc """
  Asynchronously warms the system cache with progress tracking.
  """
  @spec warm_system_cache_async([integer()], progress_callback()) :: :ok
  def warm_system_cache_async(system_ids, progress_callback \\ nil) do
    Task.start(fn ->
      warm_system_cache(system_ids, progress_callback)
    end)

    :ok
  end

  @doc """
  Asynchronously warms the universe type cache with progress tracking.
  """
  @spec warm_universe_types_async([integer()], progress_callback()) :: :ok
  def warm_universe_types_async(type_ids, progress_callback \\ nil) do
    Task.start(fn ->
      warm_universe_types(type_ids, progress_callback)
    end)

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_missing_ids(cached_results) do
    cached_results
    |> Enum.filter(fn {_id, result} -> match?({:error, :not_found}, result) end)
    |> Enum.map(fn {id, _} -> id end)
  end

  defp warm_missing_characters(missing_ids, all_ids, progress_callback) do
    total = length(all_ids)
    already_cached = total - length(missing_ids)

    # Notify initial progress
    maybe_call_progress(progress_callback, already_cached, total)

    # Process in batches
    {_completed, success_count} =
      process_character_batches(missing_ids, already_cached, total, progress_callback)

    total_success = already_cached + success_count
    Logger.info("Character cache warming completed: #{total_success}/#{total} cached")
    {:ok, total_success}
  end

  defp process_character_batches(missing_ids, initial_completed, total, progress_callback) do
    missing_ids
    |> Enum.chunk_every(@character_batch_size)
    |> Enum.reduce({initial_completed, 0}, fn batch, {completed, success_count} ->
      process_character_batch(batch, completed, success_count, total, progress_callback)
    end)
  end

  defp process_character_batch(batch, completed, success_count, total, progress_callback) do
    case fetch_and_cache_characters(batch) do
      {:ok, batch_success} ->
        new_completed = completed + length(batch)
        maybe_call_progress(progress_callback, new_completed, total)
        {new_completed, success_count + batch_success}

      {:error, _reason} ->
        # Even on error, update progress
        new_completed = completed + length(batch)
        maybe_call_progress(progress_callback, new_completed, total)
        {new_completed, success_count}
    end
  end

  defp warm_missing_systems(missing_ids, all_ids, progress_callback) do
    total = length(all_ids)
    already_cached = total - length(missing_ids)

    # Notify initial progress
    maybe_call_progress(progress_callback, already_cached, total)

    # Process in batches
    {_completed, success_count} =
      process_system_batches(missing_ids, already_cached, total, progress_callback)

    total_success = already_cached + success_count
    Logger.info("System cache warming completed: #{total_success}/#{total} cached")
    {:ok, total_success}
  end

  defp process_system_batches(missing_ids, initial_completed, total, progress_callback) do
    missing_ids
    |> Enum.chunk_every(@system_batch_size)
    |> Enum.reduce({initial_completed, 0}, fn batch, {completed, success_count} ->
      process_system_batch(batch, completed, success_count, total, progress_callback)
    end)
  end

  defp process_system_batch(batch, completed, success_count, total, progress_callback) do
    case fetch_and_cache_systems(batch) do
      {:ok, batch_success} ->
        new_completed = completed + length(batch)
        maybe_call_progress(progress_callback, new_completed, total)
        {new_completed, success_count + batch_success}

      {:error, _reason} ->
        # Even on error, update progress
        new_completed = completed + length(batch)
        maybe_call_progress(progress_callback, new_completed, total)
        {new_completed, success_count}
    end
  end

  defp warm_missing_types(missing_ids, all_ids, progress_callback) do
    total = length(all_ids)
    already_cached = total - length(missing_ids)

    # Notify initial progress
    maybe_call_progress(progress_callback, already_cached, total)

    # Process in batches
    {_completed, success_count} =
      process_type_batches(missing_ids, already_cached, total, progress_callback)

    total_success = already_cached + success_count
    Logger.info("Type cache warming completed: #{total_success}/#{total} cached")
    {:ok, total_success}
  end

  defp process_type_batches(missing_ids, initial_completed, total, progress_callback) do
    missing_ids
    |> Enum.chunk_every(@type_batch_size)
    |> Enum.reduce({initial_completed, 0}, fn batch, {completed, success_count} ->
      process_type_batch(batch, completed, success_count, total, progress_callback)
    end)
  end

  defp process_type_batch(batch, completed, success_count, total, progress_callback) do
    case fetch_and_cache_types(batch) do
      {:ok, batch_success} ->
        new_completed = completed + length(batch)
        maybe_call_progress(progress_callback, new_completed, total)
        {new_completed, success_count + batch_success}

      {:error, _reason} ->
        # Even on error, update progress
        new_completed = completed + length(batch)
        maybe_call_progress(progress_callback, new_completed, total)
        {new_completed, success_count}
    end
  end

  defp fetch_and_cache_characters(character_ids) do
    # Fetch each character from ESI - rate limiting handled by HTTP middleware
    results =
      Enum.map(character_ids, fn id ->
        case ESI.get_character(id) do
          {:ok, character_data} ->
            {id, character_data}

          {:error, reason} ->
            Logger.debug("Failed to fetch character #{id}: #{inspect(reason)}")
            nil
        end
      end)

    # Filter out failures
    successful = Enum.reject(results, &is_nil/1)

    # Batch cache the successful results
    if Enum.empty?(successful) do
      {:ok, 0}
    else
      case Cache.put_characters_batch(successful) do
        :ok -> {:ok, length(successful)}
        error -> error
      end
    end
  end

  defp fetch_and_cache_systems(system_ids) do
    # Fetch each system from ESI - rate limiting handled by HTTP middleware
    results =
      Enum.map(system_ids, fn id ->
        case ESI.get_system(id) do
          {:ok, system_data} ->
            {id, system_data}

          {:error, reason} ->
            Logger.debug("Failed to fetch system #{id}: #{inspect(reason)}")
            nil
        end
      end)

    # Filter out failures
    successful = Enum.reject(results, &is_nil/1)

    # Batch cache the successful results
    if Enum.empty?(successful) do
      {:ok, 0}
    else
      case Cache.put_systems_batch(successful) do
        :ok -> {:ok, length(successful)}
        error -> error
      end
    end
  end

  defp fetch_and_cache_types(type_ids) do
    # Fetch each type from ESI - rate limiting handled by HTTP middleware
    results =
      Enum.map(type_ids, fn id ->
        case ESI.get_type(id) do
          {:ok, type_data} ->
            {id, type_data}

          {:error, reason} ->
            Logger.debug("Failed to fetch type #{id}: #{inspect(reason)}")
            nil
        end
      end)

    # Filter out failures
    successful = Enum.reject(results, &is_nil/1)

    # Batch cache the successful results
    if Enum.empty?(successful) do
      {:ok, 0}
    else
      case Cache.put_universe_types_batch(successful) do
        :ok -> {:ok, length(successful)}
        error -> error
      end
    end
  end

  defp maybe_call_progress(nil, _completed, _total), do: :ok

  defp maybe_call_progress(callback, completed, total) when is_function(callback, 2) do
    callback.(completed, total)
  end
end
