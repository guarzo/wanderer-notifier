defmodule WandererNotifier.Infrastructure.Cache.Deduplication do
  @moduledoc """
  Centralized deduplication service for consistent duplicate prevention.

  Provides type-aware deduplication with appropriate TTLs for different
  data types across the application.
  """

  alias WandererNotifier.Infrastructure.Cache
  require Logger

  # Deduplication TTL constants
  @killmail_dedup_ttl :timer.minutes(5)
  @notification_kill_ttl :timer.minutes(30)
  @notification_system_ttl :timer.minutes(15)
  @notification_character_ttl :timer.minutes(15)
  @notification_rally_ttl :timer.minutes(5)
  @status_report_ttl :timer.minutes(1)
  @websocket_dedup_ttl :timer.minutes(5)

  @type dedup_type ::
          :killmail
          | :notification_kill
          | :notification_system
          | :notification_character
          | :notification_rally
          | :status_report
          | :websocket

  @type dedup_result :: :new | :duplicate

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Checks if an item is a duplicate based on type and identifier.

  ## Examples
      iex> Deduplication.is_duplicate?(:killmail, "12345")
      false

      iex> Deduplication.is_duplicate?(:notification_kill, "kill_67890")
      true  # if already processed
  """
  @spec is_duplicate?(dedup_type(), String.t()) :: boolean()
  def is_duplicate?(type, identifier) when is_atom(type) and is_binary(identifier) do
    key = build_dedup_key(type, identifier)
    Cache.exists?(key)
  end

  @doc """
  Marks an item as processed to prevent duplicates.

  ## Examples
      iex> Deduplication.mark_processed(:killmail, "12345")
      :ok
  """
  @spec mark_processed(dedup_type(), String.t()) :: :ok | {:error, term()}
  def mark_processed(type, identifier) when is_atom(type) and is_binary(identifier) do
    key = build_dedup_key(type, identifier)
    ttl = get_ttl_for_type(type)

    case Cache.put(key, %{processed_at: DateTime.utc_now()}, ttl) do
      :ok ->
        Logger.debug("Marked #{type} #{identifier} as processed",
          type: type,
          identifier: identifier,
          ttl_seconds: div(ttl, 1000)
        )

        :ok

      error ->
        Logger.error("Failed to mark #{type} #{identifier} as processed",
          type: type,
          identifier: identifier,
          error: inspect(error)
        )

        error
    end
  end

  @doc """
  Checks and marks in a single atomic operation using Cachex.transaction.
  Returns {:ok, :new} if this is a new item, {:ok, :duplicate} if already seen,
  or {:error, reason} on failure.

  Uses Cachex.transaction/3 to ensure atomicity, preventing TOCTOU race conditions.

  ## Examples
      iex> Deduplication.check_and_mark(:killmail, "12345")
      {:ok, :new}

      iex> Deduplication.check_and_mark(:killmail, "12345")
      {:ok, :duplicate}
  """
  @spec check_and_mark(dedup_type(), String.t()) :: {:ok, dedup_result()} | {:error, term()}
  def check_and_mark(type, identifier) when is_atom(type) and is_binary(identifier) do
    key = build_dedup_key(type, identifier)
    ttl = get_ttl_for_type(type)

    # Use Cache.transaction for atomic check-and-mark operation
    result =
      Cache.transaction([key], fn ->
        do_atomic_check_and_mark(key, ttl)
      end)

    handle_check_and_mark_result(result, type, identifier, ttl)
  end

  # Dialyzer reports the catch-all error clause as unreachable because current Cache
  # implementation only returns :not_found errors. Added for defensive programming.
  @dialyzer {:nowarn_function, do_atomic_check_and_mark: 2}
  defp do_atomic_check_and_mark(key, ttl) do
    case Cache.get(key) do
      {:error, :not_found} ->
        # Not a duplicate, mark as processed
        case Cache.put(key, %{processed_at: DateTime.utc_now()}, ttl) do
          :ok -> :new
          {:error, reason} -> {:error, reason}
        end

      {:ok, _value} ->
        # Already exists, it's a duplicate
        :duplicate

      {:error, reason} ->
        # Propagate error
        {:error, reason}
    end
  end

  defp handle_check_and_mark_result({:ok, :new}, type, identifier, ttl) do
    Logger.debug("Marked #{type} #{identifier} as processed (atomic)",
      type: type,
      identifier: identifier,
      ttl_seconds: div(ttl, 1000)
    )

    {:ok, :new}
  end

  defp handle_check_and_mark_result({:ok, :duplicate}, _type, _identifier, _ttl),
    do: {:ok, :duplicate}

  defp handle_check_and_mark_result({:ok, {:error, reason}}, _type, _identifier, _ttl) do
    # Error from within transaction, propagate
    {:error, reason}
  end

  defp handle_check_and_mark_result({:error, reason}, _type, _identifier, _ttl) do
    # Transaction failed, propagate the error
    {:error, reason}
  end

  @doc """
  Deletes a specific deduplication key from the cache.

  ## Examples
      iex> Deduplication.delete(:killmail, "12345")
      {:ok, :deleted}
  """
  @spec delete(dedup_type(), String.t()) :: {:ok, :deleted} | {:error, term()}
  def delete(type, identifier) when is_atom(type) and is_binary(identifier) do
    key = build_dedup_key(type, identifier)
    Cache.delete(key)
  end

  @doc """
  Clears all duplicates for a specific type.

  ## Examples
      iex> Deduplication.clear_duplicates(:killmail)
      :ok
  """
  @spec clear_duplicates(dedup_type()) :: :ok | {:error, term()}
  def clear_duplicates(type) when is_atom(type) do
    prefix = get_prefix_for_type(type)

    Logger.info("Clearing all duplicates for type #{type}", type: type, prefix: prefix)

    try do
      # Stream all keys from the cache and filter by prefix
      keys_to_delete =
        Cache.stream_keys()
        |> Stream.filter(&String.starts_with?(&1, prefix))
        |> Enum.to_list()

      # Delete all matching keys
      deletion_results =
        keys_to_delete
        |> Enum.map(&Cache.delete/1)
        |> Enum.all?(&match?({:ok, _}, &1))

      if deletion_results do
        Logger.info("Successfully cleared #{length(keys_to_delete)} duplicates for type #{type}",
          type: type,
          keys_cleared: length(keys_to_delete)
        )

        :ok
      else
        Logger.error("Some deletions failed for type #{type}", type: type)
        {:error, :partial_deletion_failure}
      end
    rescue
      error ->
        Logger.error("Failed to clear duplicates for type #{type}",
          type: type,
          error: inspect(error)
        )

        {:error, error}
    end
  end

  @doc """
  Gets deduplication statistics for monitoring.

  Returns a map with counts and information for each dedup type.
  """
  @spec get_dedup_stats() :: map()
  def get_dedup_stats do
    %{
      killmail: %{
        ttl_seconds: div(@killmail_dedup_ttl, 1000),
        description: "Killmail deduplication"
      },
      notification_kill: %{
        ttl_seconds: div(@notification_kill_ttl, 1000),
        description: "Kill notification deduplication"
      },
      notification_system: %{
        ttl_seconds: div(@notification_system_ttl, 1000),
        description: "System notification deduplication"
      },
      notification_character: %{
        ttl_seconds: div(@notification_character_ttl, 1000),
        description: "Character notification deduplication"
      },
      notification_rally: %{
        ttl_seconds: div(@notification_rally_ttl, 1000),
        description: "Rally point notification deduplication"
      },
      status_report: %{
        ttl_seconds: div(@status_report_ttl, 1000),
        description: "Status report deduplication"
      },
      websocket: %{
        ttl_seconds: div(@websocket_dedup_ttl, 1000),
        description: "WebSocket message deduplication"
      }
    }
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec build_dedup_key(dedup_type(), String.t()) :: String.t()
  defp build_dedup_key(type, identifier) do
    prefix = get_prefix_for_type(type)
    "#{prefix}:#{identifier}"
  end

  @spec get_prefix_for_type(dedup_type()) :: String.t()
  defp get_prefix_for_type(:killmail), do: "dedup:killmail"
  defp get_prefix_for_type(:notification_kill), do: "notification:dedup:kill"
  defp get_prefix_for_type(:notification_system), do: "notification:dedup:system"
  defp get_prefix_for_type(:notification_character), do: "notification:dedup:character"
  defp get_prefix_for_type(:notification_rally), do: "notification:dedup:rally"
  defp get_prefix_for_type(:status_report), do: "status_report"
  defp get_prefix_for_type(:websocket), do: "websocket_dedup"

  defp get_prefix_for_type(unknown_type) do
    raise ArgumentError,
          "Unknown deduplication type: #{inspect(unknown_type)}. " <>
            "Expected one of: :killmail, :notification_kill, :notification_system, " <>
            ":notification_character, :notification_rally, :status_report, :websocket"
  end

  @spec get_ttl_for_type(dedup_type()) :: pos_integer()
  defp get_ttl_for_type(:killmail), do: @killmail_dedup_ttl
  defp get_ttl_for_type(:notification_kill), do: @notification_kill_ttl
  defp get_ttl_for_type(:notification_system), do: @notification_system_ttl
  defp get_ttl_for_type(:notification_character), do: @notification_character_ttl
  defp get_ttl_for_type(:notification_rally), do: @notification_rally_ttl
  defp get_ttl_for_type(:status_report), do: @status_report_ttl
  defp get_ttl_for_type(:websocket), do: @websocket_dedup_ttl
end
