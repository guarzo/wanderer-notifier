defmodule WandererNotifier.Contexts.ProcessingContext do
  @moduledoc """
  Context module for data processing operations.

  Provides a clean API boundary for all data processing functionality including:
  - Killmail processing and enrichment
  - Data validation and transformation
  - Processing pipeline coordination
  - Stream connection management

  This context consolidates processing logic that was previously scattered
  and provides a unified interface for all data processing operations.
  """

  require Logger
  alias WandererNotifier.Domains.Killmail.{Pipeline, Enrichment}
  alias WandererNotifier.Application.Services.ApplicationService
  alias WandererNotifier.Infrastructure.Cache

  # ──────────────────────────────────────────────────────────────────────────────
  # Killmail Processing
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Processes a killmail through the complete processing pipeline.

  This is the main entry point for killmail processing. It handles:
  - Data validation and normalization
  - Enrichment with additional game data
  - Notification generation and delivery
  - Metrics tracking and logging

  ## Examples

      iex> ProcessingContext.process_killmail(%{"killmail_id" => 123})
      {:ok, "notification_sent"}
      
      iex> ProcessingContext.process_killmail(%{})
      {:error, :invalid_killmail}
  """
  @spec process_killmail(map()) :: {:ok, String.t() | :skipped} | {:error, term()}
  def process_killmail(killmail_data) do
    killmail_id = get_killmail_id(killmail_data)

    Logger.debug("Processing killmail through ProcessingContext",
      killmail_id: killmail_id,
      data_keys: Map.keys(killmail_data),
      category: :processing
    )

    # Track processing start
    ApplicationService.increment_metric(:killmail_processing_start)

    try do
      case Pipeline.process_killmail(killmail_data) do
        {:ok, result} = success ->
          # Track successful completion
          ApplicationService.increment_metric(:killmail_processing_complete)
          ApplicationService.increment_metric(:killmail_processing_complete_success)

          Logger.info("Killmail processed successfully",
            killmail_id: killmail_id,
            result: result,
            category: :processing
          )

          success

        {:error, reason} = error ->
          # Track processing error
          ApplicationService.increment_metric(:killmail_processing_complete)
          ApplicationService.increment_metric(:killmail_processing_complete_error)

          Logger.warning("Killmail processing failed",
            killmail_id: killmail_id,
            reason: inspect(reason),
            category: :processing
          )

          error
      end
    rescue
      exception ->
        # Track processing exception
        ApplicationService.increment_metric(:killmail_processing_error)

        Logger.error("Exception during killmail processing",
          killmail_id: killmail_id,
          exception: Exception.message(exception),
          stacktrace: __STACKTRACE__,
          category: :processing
        )

        {:error, {:exception, exception}}
    end
  end

  @doc """
  Gets enriched killmail data with additional context.

  This function retrieves and enriches killmail data with:
  - Character, corporation, and alliance information
  - Ship and item details
  - System information
  - Recent kill history for context
  """
  @spec get_enriched_killmail(map()) :: {:ok, map()} | {:error, term()}
  def get_enriched_killmail(killmail_data) do
    killmail_id = get_killmail_id(killmail_data)

    Logger.debug("Enriching killmail data",
      killmail_id: killmail_id,
      category: :processing
    )

    # Check if we have cached enriched data
    cache_key = "enriched:killmail:#{killmail_id}"

    case Cache.get(cache_key) do
      {:ok, enriched_data} ->
        {:ok, enriched_data}

      _ ->
        # If not cached, enrich the killmail data
        enriched = enrich_killmail_data(killmail_data)

        # Cache the enriched data
        Cache.put(cache_key, enriched, :timer.minutes(30))

        {:ok, enriched}
    end
  end

  defp enrich_killmail_data(killmail_data) do
    killmail_data
    |> Map.put(:enriched, true)
    |> enrich_with_system_name()
    |> enrich_with_victim_name()
  end

  defp enrich_with_system_name(killmail_data) do
    system_id = extract_system_id(killmail_data)

    case system_id do
      nil -> killmail_data
      id -> add_system_name(killmail_data, id)
    end
  end

  defp enrich_with_victim_name(killmail_data) do
    victim_id = extract_victim_id(killmail_data)

    case victim_id do
      nil -> killmail_data
      id -> add_victim_name(killmail_data, id)
    end
  end

  defp extract_system_id(killmail_data) do
    get_in(killmail_data, ["solar_system_id"]) || get_in(killmail_data, [:solar_system_id])
  end

  defp extract_victim_id(killmail_data) do
    get_in(killmail_data, ["victim", "character_id"]) ||
      get_in(killmail_data, [:victim, :character_id])
  end

  defp add_system_name(killmail_data, system_id) do
    case Cache.get_system(system_id) do
      {:ok, system} -> Map.put(killmail_data, :system_name, system.name)
      _ -> killmail_data
    end
  end

  defp add_victim_name(killmail_data, victim_id) do
    case Cache.get_character(victim_id) do
      {:ok, character} -> Map.put(killmail_data, :victim_name, character.name)
      _ -> killmail_data
    end
  end

  @doc """
  Gets recent kills for a specific system for context.

  This is useful for providing additional context in notifications,
  showing patterns of activity in a system.
  """
  @spec get_recent_system_kills(integer(), integer()) :: String.t()
  def get_recent_system_kills(system_id, limit \\ 3) do
    Logger.debug("Getting recent kills for system",
      system_id: system_id,
      limit: limit,
      category: :processing
    )

    try do
      Enrichment.recent_kills_for_system(system_id, limit)
    rescue
      exception ->
        Logger.error("Exception getting recent system kills",
          system_id: system_id,
          exception: Exception.message(exception),
          category: :processing
        )

        "Recent kills unavailable"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Processing Pipeline Status
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Checks if the killmail processing stream is connected and operational.
  """
  @spec stream_connected?() :: boolean()
  def stream_connected? do
    # Check if the PipelineWorker (which manages WebSocket client) is running
    pipeline_pid = Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker)
    connected = is_pid(pipeline_pid) and Process.alive?(pipeline_pid)

    Logger.debug("Checked killmail stream connection status",
      connected: connected,
      pipeline_pid: pipeline_pid,
      category: :processing
    )

    connected
  end

  @doc """
  Gets comprehensive processing status and metrics.
  """
  @spec get_processing_status() :: map()
  def get_processing_status do
    stats = ApplicationService.get_stats()
    counters = Map.get(stats, :counters, %{})

    %{
      stream_connected: stream_connected?(),
      metrics: %{
        processing_started: Map.get(counters, :killmail_processing_start, 0),
        processing_completed: Map.get(counters, :killmail_processing_complete, 0),
        processing_successful: Map.get(counters, :killmail_processing_complete_success, 0),
        processing_errors: Map.get(counters, :killmail_processing_complete_error, 0),
        processing_exceptions: Map.get(counters, :killmail_processing_error, 0),
        processing_skipped: Map.get(counters, :killmail_processing_skipped, 0)
      },
      health: %{
        success_rate: calculate_success_rate(counters),
        error_rate: calculate_error_rate(counters)
      }
    }
  end

  @doc """
  Validates killmail data structure.

  Performs basic validation to ensure the killmail data contains
  the minimum required fields for processing.
  """
  @spec validate_killmail(map()) :: {:ok, map()} | {:error, term()}
  def validate_killmail(killmail_data) when is_map(killmail_data) do
    case get_killmail_id(killmail_data) do
      nil ->
        Logger.warning("Killmail validation failed: missing killmail_id",
          data_keys: Map.keys(killmail_data),
          category: :processing
        )

        {:error, :missing_killmail_id}

      killmail_id when is_integer(killmail_id) or is_binary(killmail_id) ->
        Logger.debug("Killmail validation passed",
          killmail_id: killmail_id,
          category: :processing
        )

        {:ok, killmail_data}

      invalid_id ->
        Logger.warning("Killmail validation failed: invalid killmail_id",
          killmail_id: invalid_id,
          category: :processing
        )

        {:error, {:invalid_killmail_id, invalid_id}}
    end
  end

  def validate_killmail(invalid_data) do
    Logger.warning("Killmail validation failed: not a map",
      data_type: typeof(invalid_data),
      category: :processing
    )

    {:error, {:invalid_data_type, typeof(invalid_data)}}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_killmail_id(killmail_data) do
    Map.get(killmail_data, :killmail_id) ||
      Map.get(killmail_data, "killmail_id") ||
      Map.get(killmail_data, "killID")
  end

  defp calculate_success_rate(counters) do
    completed = Map.get(counters, :killmail_processing_complete, 0)
    successful = Map.get(counters, :killmail_processing_complete_success, 0)

    if completed > 0 do
      Float.round(successful / completed * 100, 2)
    else
      0.0
    end
  end

  defp calculate_error_rate(counters) do
    completed = Map.get(counters, :killmail_processing_complete, 0)
    errors = Map.get(counters, :killmail_processing_complete_error, 0)
    exceptions = Map.get(counters, :killmail_processing_error, 0)

    if completed > 0 do
      Float.round((errors + exceptions) / completed * 100, 2)
    else
      0.0
    end
  end

  defp typeof(%{__struct__: module}), do: module
  defp typeof(data) when is_map(data), do: :map
  defp typeof(data) when is_list(data), do: :list
  defp typeof(data) when is_binary(data), do: :binary
  defp typeof(data) when is_integer(data), do: :integer
  defp typeof(data) when is_float(data), do: :float
  defp typeof(data) when is_boolean(data), do: :boolean
  defp typeof(data) when is_atom(data), do: :atom
  defp typeof(data) when is_tuple(data), do: :tuple
  defp typeof(data) when is_pid(data), do: :pid
  defp typeof(data) when is_reference(data), do: :reference
  defp typeof(data) when is_function(data), do: :function
  defp typeof(_data), do: :unknown
end
