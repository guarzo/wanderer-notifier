defmodule WandererNotifier.Contexts.Killmail do
  @moduledoc """
  Context module for killmail processing functionality.
  Provides a clean API boundary for all killmail-related operations.
  """

  alias WandererNotifier.Killmail.{
    Pipeline,
    Processor,
    Cache,
    Enrichment,
    RedisQClient
  }

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Processes a killmail through the complete pipeline.

  ## Examples

      iex> Killmail.process_killmail(%{"killmail_id" => 123})
      {:ok, %{processed: true}}
      
      iex> Killmail.process_killmail(%{})
      {:error, :invalid_killmail}
  """
  @spec process_killmail(map()) :: {:ok, String.t() | :skipped} | {:error, term()}
  def process_killmail(killmail) do
    context = WandererNotifier.Killmail.Context.new()
    Pipeline.process_killmail(killmail, context)
  end

  @doc """
  Enriches a killmail with additional data from ESI.
  """
  @spec enrich_killmail(WandererNotifier.Killmail.Killmail.t()) ::
          {:ok, WandererNotifier.Killmail.Killmail.t()} | {:error, term()}
  defdelegate enrich_killmail(killmail), to: Enrichment, as: :enrich_killmail_data

  @doc """
  Caches a killmail for quick access.
  """
  @spec cache_killmail(String.t() | integer(), map()) :: :ok
  defdelegate cache_killmail(killmail_id, killmail), to: Cache, as: :cache_kill

  @doc """
  Retrieves a cached killmail by ID.
  """
  @spec get_cached_killmail(String.t() | integer()) :: {:ok, map()} | {:error, :not_cached}
  defdelegate get_cached_killmail(kill_id), to: Cache, as: :get_kill

  @doc """
  Gets all recent cached kills.
  """
  @spec get_recent_kills() :: {:ok, map()} | {:error, term()}
  defdelegate get_recent_kills(), to: Cache

  @doc """
  Validates a killmail structure.
  """
  @spec process_zkill_message(map(), term()) :: {:ok, String.t() | :skipped} | {:error, term()}
  defdelegate process_zkill_message(kill_data, state), to: Processor

  @doc """
  Gets recent kills for a specific system.
  """
  @spec recent_kills_for_system(integer(), integer()) :: String.t()
  defdelegate recent_kills_for_system(system_id, limit \\ 3), to: Enrichment

  # ──────────────────────────────────────────────────────────────────────────────
  # Client Management
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the RedisQ client for receiving killmail streams.
  Should be called by the supervisor.
  """
  @spec start_redisq_client() :: {:ok, pid()} | {:error, term()}
  def start_redisq_client do
    RedisQClient.start_link([])
  end

  @doc """
  Starts the ZKill WebSocket client for receiving killmail streams.
  Should be called by the supervisor.
  """
  @spec start_zkill_client() :: {:ok, pid()} | {:error, term()}
  def start_zkill_client do
    # ZKillClient is not a GenServer, it's a regular module for API calls
    # The websocket connection is handled by RedisQClient
    {:ok, self()}
  end

  @doc """
  Checks if the killmail stream is connected.
  """
  @spec stream_connected?() :: boolean()
  def stream_connected? do
    # Check if either RedisQ or ZKill client is running
    redisq_pid = Process.whereis(WandererNotifier.Killmail.RedisQClient)
    zkill_pid = Process.whereis(WandererNotifier.Killmail.ZKillClient)

    (is_pid(redisq_pid) and Process.alive?(redisq_pid)) or
      (is_pid(zkill_pid) and Process.alive?(zkill_pid))
  end
end
