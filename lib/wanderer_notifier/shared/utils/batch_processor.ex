defmodule WandererNotifier.Shared.Utils.BatchProcessor do
  @moduledoc """
  Utility module for processing collections in configurable batches.

  This module provides reusable batch processing functionality with:
  - Configurable batch sizes
  - Optional delays between batches for garbage collection
  - Order-preserving processing
  - Parallel and sequential processing strategies
  - Memory-efficient accumulation patterns

  ## Usage Examples

      # Simple synchronous batch processing
      BatchProcessor.process_sync(items, &process_item/1, batch_size: 50)
      
      # With delay between batches for GC
      BatchProcessor.process_sync(items, &expensive_operation/1, 
        batch_size: 25, 
        batch_delay: 100
      )
      
      # Parallel processing with Task.async_stream
      BatchProcessor.process_parallel(items, &fetch_data/1,
        batch_size: 10,
        max_concurrency: 5,
        timeout: 30_000
      )
  """

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  @type process_fun :: (any() -> any())
  @type batch_opts :: [
          batch_size: pos_integer(),
          batch_delay: non_neg_integer(),
          log_progress: boolean(),
          logger_metadata: map()
        ]
  @type parallel_opts :: [
          batch_size: pos_integer(),
          max_concurrency: pos_integer(),
          timeout: timeout(),
          on_timeout: :kill_task | :ignore,
          log_progress: boolean(),
          logger_metadata: map()
        ]

  @default_batch_size 50
  @default_batch_delay 0
  @default_max_concurrency System.schedulers_online()
  @default_timeout 30_000

  @doc """
  Processes a collection in batches synchronously with optional delays.

  This is the memory-efficient version that maintains order while avoiding
  O(n²) complexity from repeated list concatenation.

  ## Options
  - `:batch_size` - Number of items per batch (default: 50)
  - `:batch_delay` - Milliseconds to sleep between batches (default: 0)
  - `:log_progress` - Whether to log batch progress (default: false)
  - `:logger_metadata` - Additional metadata for logging (default: %{})

  ## Examples

      # Process with default settings
      BatchProcessor.process_sync(items, &String.upcase/1)
      
      # Process with custom batch size and delay
      BatchProcessor.process_sync(items, &expensive_operation/1,
        batch_size: 25,
        batch_delay: 100,
        log_progress: true,
        logger_metadata: %{operation: "data_enrichment"}
      )
  """
  @spec process_sync(Enumerable.t(), process_fun(), batch_opts()) :: list()
  def process_sync(collection, process_fun, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_delay = Keyword.get(opts, :batch_delay, @default_batch_delay)
    log_progress = Keyword.get(opts, :log_progress, false)
    logger_metadata = Keyword.get(opts, :logger_metadata, %{})

    items = Enum.to_list(collection)
    total_items = length(items)

    if total_items == 0 do
      []
    else
      batches = Enum.chunk_every(items, batch_size)
      batch_count = length(batches)

      if log_progress do
        AppLogger.api_info(
          "Starting batch processing",
          Map.merge(logger_metadata, %{
            total_items: total_items,
            batch_size: batch_size,
            batch_count: batch_count,
            batch_delay: batch_delay
          })
        )
      end

      process_batches_sync(batches, process_fun, batch_delay, log_progress, logger_metadata, 1)
    end
  end

  @doc """
  Processes a collection in batches using parallel Task.async_stream.

  Each batch is processed in parallel up to the max_concurrency limit.
  Order is preserved within batches but not necessarily between batches.

  ## Options
  - `:batch_size` - Number of items per batch (default: 50)
  - `:max_concurrency` - Maximum concurrent tasks (default: System.schedulers_online())
  - `:timeout` - Timeout per item in milliseconds (default: 30_000)
  - `:on_timeout` - Action on timeout: :kill_task or :ignore (default: :kill_task)
  - `:log_progress` - Whether to log batch progress (default: false)
  - `:logger_metadata` - Additional metadata for logging (default: %{})

  ## Examples

      # Process with default settings
      BatchProcessor.process_parallel(urls, &fetch_url/1)
      
      # Process with custom settings
      BatchProcessor.process_parallel(items, &api_call/1,
        batch_size: 10,
        max_concurrency: 5,
        timeout: 60_000,
        log_progress: true
      )
  """
  @spec process_parallel(Enumerable.t(), process_fun(), parallel_opts()) ::
          {:ok, list()} | {:error, list({:exit, any()} | {:error, any()})}
  def process_parallel(collection, process_fun, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_timeout = Keyword.get(opts, :on_timeout, :kill_task)
    log_progress = Keyword.get(opts, :log_progress, false)
    logger_metadata = Keyword.get(opts, :logger_metadata, %{})

    items = Enum.to_list(collection)
    total_items = length(items)

    if total_items == 0 do
      {:ok, []}
    else
      batches = Enum.chunk_every(items, batch_size)
      batch_count = length(batches)

      if log_progress do
        AppLogger.api_info(
          "Starting parallel batch processing",
          Map.merge(logger_metadata, %{
            total_items: total_items,
            batch_size: batch_size,
            batch_count: batch_count,
            max_concurrency: max_concurrency,
            timeout: timeout
          })
        )
      end

      stream_opts = [
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: on_timeout
      ]

      results =
        batches
        |> Task.async_stream(
          fn batch ->
            Enum.map(batch, process_fun)
          end,
          stream_opts
        )
        |> Enum.to_list()

      process_parallel_results(results, log_progress, logger_metadata)
    end
  end

  @doc """
  Creates a stream that processes items in batches.

  This is useful for lazy evaluation and composing with other Stream operations.

  ## Options
  - `:batch_size` - Number of items per batch (default: 50)

  ## Examples

      items
      |> BatchProcessor.stream(&process_item/1, batch_size: 100)
      |> Stream.filter(&filter_condition/1)
      |> Enum.to_list()
  """
  @spec stream(Enumerable.t(), process_fun(), batch_size: pos_integer()) :: Enumerable.t()
  def stream(collection, process_fun, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    collection
    |> Stream.chunk_every(batch_size)
    |> Stream.map(fn batch ->
      Enum.map(batch, process_fun)
    end)
    |> Stream.flat_map(&Function.identity/1)
  end

  @doc """
  Processes items in batches with a stateful accumulator.

  Similar to Enum.reduce but processes items in batches.

  ## Options
  - `:batch_size` - Number of items per batch (default: 50)
  - `:batch_delay` - Milliseconds to sleep between batches (default: 0)

  ## Examples

      # Sum values in batches
      BatchProcessor.reduce(numbers, 0, fn num, acc -> acc + num end,
        batch_size: 100
      )
      
      # Build a map in batches
      BatchProcessor.reduce(items, %{}, fn item, acc ->
        Map.put(acc, item.id, item)
      end, batch_size: 50)
  """
  @spec reduce(Enumerable.t(), any(), (any(), any() -> any()), Keyword.t()) :: any()
  def reduce(collection, initial_acc, reducer_fun, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_delay = Keyword.get(opts, :batch_delay, @default_batch_delay)

    collection
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce(initial_acc, fn batch, acc ->
      result = Enum.reduce(batch, acc, reducer_fun)

      if batch_delay > 0 do
        Process.sleep(batch_delay)
      end

      result
    end)
  end

  # Private helper functions

  defp process_batches_sync([], _process_fun, _delay, _log, _metadata, _batch_num) do
    []
  end

  defp process_batches_sync([batch | remaining], process_fun, delay, log, metadata, batch_number) do
    if log do
      AppLogger.api_debug(
        "Processing batch",
        Map.merge(metadata, %{
          batch_number: batch_number,
          batch_size: length(batch)
        })
      )
    end

    # Process current batch
    processed_batch = Enum.map(batch, process_fun)

    # Add delay if specified
    if delay > 0 do
      Process.sleep(delay)
    end

    # Process remaining batches and concatenate results
    processed_batch ++
      process_batches_sync(remaining, process_fun, delay, log, metadata, batch_number + 1)
  end

  defp process_parallel_results(results, log_progress, metadata) do
    {successes, failures} =
      Enum.reduce(results, {[], []}, fn
        {:ok, batch_results}, {succ, fail} ->
          {batch_results ++ succ, fail}

        {:exit, reason}, {succ, fail} ->
          {succ, [{:exit, reason} | fail]}

        error, {succ, fail} ->
          {succ, [error | fail]}
      end)

    if log_progress do
      AppLogger.api_info(
        "Parallel batch processing completed",
        Map.merge(metadata, %{
          successful_items: length(successes),
          failed_items: length(failures)
        })
      )
    end

    if failures == [] do
      {:ok, Enum.reverse(successes)}
    else
      {:error, Enum.reverse(failures)}
    end
  end
end
