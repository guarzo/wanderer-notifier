defmodule WandererNotifier.Domains.Killmail.Processor do
  @moduledoc """
  Processes incoming ZKillboard messages, runs them through the killmail pipeline,
  and dispatches notifications when appropriate.
  """

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Shared.Utils.TimeUtils

  # ──────────────────────────────────────────────────────────────────────────────
  # Context Definition (merged from Domains.Killmail.Context)
  # ──────────────────────────────────────────────────────────────────────────────

  defmodule Context do
    @moduledoc """
    Defines the context for killmail processing, containing all necessary information
    for processing a killmail through the pipeline.

    This module implements the Access behaviour, allowing field access with pattern matching
    and providing a consistent interface for passing processing context through the
    killmail pipeline.
    """

    @type t :: %__MODULE__{
            # Essential killmail data
            killmail_id: String.t() | integer() | nil,
            system_id: integer() | nil,
            system_name: String.t() | nil,
            # A simple map of additional options
            options: map()
          }

    defstruct [
      :killmail_id,
      :system_id,
      :system_name,
      :options
    ]

    # Implement the Access behaviour for the Context struct
    @behaviour Access

    @impl Access
    @spec fetch(t(), atom() | String.t()) :: {:ok, any()} | :error
    def fetch(struct, key) do
      Map.fetch(struct, key)
    end

    # This is not part of the Access behaviour, but a helpful utility function
    @spec get(t(), atom() | String.t(), any()) :: any()
    def get(struct, key, default \\ nil) do
      Map.get(struct, key, default)
    end

    @impl Access
    @spec get_and_update(t(), atom() | String.t(), (any() -> {any(), any()})) :: {any(), t()}
    def get_and_update(struct, key, fun) do
      current = Map.get(struct, key)
      {get, update} = fun.(current)
      {get, Map.put(struct, key, update)}
    end

    @impl Access
    @spec pop(t(), atom() | String.t()) :: {any(), t()}
    def pop(struct, key) do
      value = Map.get(struct, key)
      {value, Map.put(struct, key, nil)}
    end

    @doc """
    Creates a new context for killmail processing.

    ## Parameters
    - killmail_id: The ID of the killmail
    - system_name: The name of the system where the kill occurred
    - options: Additional options for processing

    ## Returns
    A new context struct
    """
    @spec new(String.t() | integer() | nil, String.t() | nil, map()) :: t()
    def new(killmail_id \\ nil, system_name \\ nil, options \\ %{}) do
      %__MODULE__{
        killmail_id: killmail_id,
        system_id: nil,
        system_name: system_name || "unknown",
        options: options
      }
    end
  end

  @type state :: term()
  @type kill_id :: String.t()
  @type kill_data :: map()

  @spec init() :: :ok
  def init do
    AppLogger.info("Initializing killmail processor")
    :ok
  end

  @spec schedule_tasks() :: :ok
  def schedule_tasks do
    :ok
  end

  @spec process_websocket_killmail(map(), state) :: {:ok, kill_id | :skipped} | {:error, term()}
  def process_websocket_killmail(killmail, state) do
    # WebSocket killmails come pre-enriched, so we can process them directly
    # Data is now normalized to string keys
    killmail_id = Map.get(killmail, "killmail_id")

    if killmail_id do
      case should_notify_websocket_killmail?(killmail) do
        {:ok, %{should_notify: true}} ->
          # Process the pre-enriched killmail
          process_websocket_kill_data(killmail, state)

        {:ok, %{should_notify: false} = result} ->
          reason = Map.get(result, :reason, "unknown")
          log_skipped_websocket(killmail, reason)
          {:ok, :skipped}

        {:error, reason} ->
          {:error, reason}
      end
    else
      AppLogger.kill_error("WebSocket killmail missing killmail_id",
        data: inspect(killmail),
        module: __MODULE__
      )

      {:error, :invalid_killmail_id}
    end
  end

  @spec log_stats() :: :ok
  def log_stats do
    :ok
  end

  @spec get_recent_kills() :: {:ok, list(kill_data())}
  def get_recent_kills do
    case Cache.get("zkill:recent_kills") do
      {:ok, kills} when is_list(kills) -> {:ok, kills}
      {:error, :not_found} -> {:ok, []}
      _ -> {:ok, []}
    end
  end

  # Creates a context for processing a killmail
  defp create_context(kill_data, source, state) do
    kill_id = Map.get(kill_data, "killmail_id", "unknown")
    system_id = Map.get(kill_data, "solar_system_id")
    system_name = get_system_name(system_id)

    context_opts = %{
      source: source,
      processing_started_at: TimeUtils.now()
    }

    context_opts = if state, do: Map.put(context_opts, :original_state, state), else: context_opts

    Context.new(kill_id, system_name, context_opts)
  end

  @doc """
  Processes a raw killmail data map.

  ## Options
    - `:source` - The source of the killmail (e.g. :zkill_websocket, :direct, :test_notification)
    - `:state` - Optional state to include in the context (used by websocket handler)

  ## Returns
    - `{:ok, kill_id}` - Killmail was processed successfully
    - `{:ok, :skipped}` - Killmail was skipped (e.g. not relevant)
    - `{:error, reason}` - Processing failed
  """
  @spec process_killmail(map(), keyword()) :: {:ok, kill_id | :skipped} | {:error, term()}
  def process_killmail(killmail, opts \\ []) do
    source = Keyword.get(opts, :source, :direct)
    state = Keyword.get(opts, :state)
    context = create_context(killmail, source, state)

    # Process through pipeline and let it handle notification
    case killmail_pipeline().process_killmail(killmail, context) do
      {:ok, :skipped} ->
        # Pipeline indicated this should be skipped
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        # Successfully processed and notified in pipeline
        {:ok, context.killmail_id}

      error ->
        # Handle pipeline errors
        AppLogger.kill_error("Failed to process kill data",
          kill_id: context.killmail_id,
          error: inspect(error)
        )

        error
    end
  end

  @doc """
  Sends a test notification using the most recent kill data.
  This is useful for verifying that the notification system is working correctly.

  ## Returns
    - `{:ok, kill_id}` - Test notification was sent successfully
    - `{:error, reason}` - Test notification failed
  """
  @spec send_test_kill_notification() :: {:ok, kill_id} | {:error, term()}
  def send_test_kill_notification do
    case get_recent_kills() do
      {:ok, [kill_data | _]} ->
        process_killmail(kill_data, source: :test_notification)

      {:ok, []} ->
        {:error, :no_recent_kills}
    end
  end

  @spec process_kill_data(kill_data, state) ::
          {:ok, kill_id | :skipped} | {:error, term()}
  def process_kill_data(kill_data, state) do
    context = create_context(kill_data, :zkill_websocket, state)

    # Process through pipeline and let it handle notification
    case killmail_pipeline().process_killmail(kill_data, context) do
      {:ok, :skipped} ->
        # Pipeline indicated this should be skipped
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        # Successfully processed and notified in pipeline
        {:ok, context.killmail_id}

      error ->
        # Handle pipeline errors
        AppLogger.kill_error("Failed to process kill data",
          kill_id: context.killmail_id,
          error: inspect(error)
        )

        error
    end
  end

  # -- Private helpers -------------------------------------------------------

  defp get_system_name(nil), do: "unknown"

  defp get_system_name(system_id) do
    case esi_service().get_system(system_id, []) do
      {:ok, %{"name" => name}} -> name
      _ -> "System #{system_id}"
    end
  end

  # WebSocket killmail specific helpers

  defp should_notify_websocket_killmail?(killmail) do
    # WebSocket killmails come pre-enriched, so we can use them directly
    # Convert to format expected by KillDeterminer
    KillDeterminer.should_notify?(killmail)
  end

  defp process_websocket_kill_data(killmail, state) do
    # Create context for WebSocket killmail
    # Data is now normalized to string keys
    killmail_id = Map.get(killmail, "killmail_id")
    system_id = Map.get(killmail, "system_id")
    system_name = get_system_name(system_id)

    context_opts = %{
      source: :websocket,
      processing_started_at: TimeUtils.now()
    }

    context_opts = if state, do: Map.put(context_opts, :original_state, state), else: context_opts

    context =
      killmail_id
      |> to_string()
      |> Context.new(system_name, context_opts)

    # Process through pipeline - it will handle the pre-enriched data
    case killmail_pipeline().process_killmail(killmail, context) do
      {:ok, :skipped} ->
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        {:ok, context.killmail_id}

      error ->
        AppLogger.kill_error("Failed to process WebSocket kill data",
          kill_id: context.killmail_id,
          error: inspect(error)
        )

        error
    end
  end

  @doc """
  Sends a notification for a killmail.
  Merged from WandererNotifier.Domains.Killmail.Notification.

  ## Parameters
    - killmail: The killmail data to send a notification for
    - kill_id: The ID of the kill for logging purposes

  ## Returns
    - {:ok, notification_result} on success
    - {:error, reason} on failure
  """
  def send_kill_notification(killmail, kill_id) do
    try do
      # Create the notification using the KillmailNotification module
      notification = killmail_notification_module().create(killmail)

      # Send the notification through the notification service
      case notification_service_module().send_message(notification) do
        {:ok, :sent} ->
          {:ok, notification}

        {:error, :notifications_disabled} ->
          {:ok, :disabled}

        {:error, reason} = error ->
          logger_module().notification_error("Failed to send kill notification", %{
            kill_id: kill_id,
            error: inspect(reason)
          })

          error
      end
    rescue
      e ->
        logger_module().notification_error("Exception sending kill notification", %{
          kill_id: kill_id,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:error, :notification_failed}
    end
  end

  defp log_skipped_websocket(killmail, reason) do
    # Data is now normalized to string keys
    killmail_id = Map.get(killmail, "killmail_id")
    system_id = Map.get(killmail, "system_id")

    AppLogger.processor_debug("WebSocket killmail skipped",
      killmail_id: killmail_id,
      system_id: system_id,
      reason: reason
    )

    :ok
  end

  defp killmail_pipeline,
    do: WandererNotifier.Application.Services.Dependencies.killmail_pipeline()

  defp esi_service, do: WandererNotifier.Application.Services.Dependencies.esi_service()

  # Dependency injection helpers (merged from Notification module)
  defp killmail_notification_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_notification_module,
      WandererNotifier.Domains.Notifications.KillmailNotification
    )
  end

  defp notification_service_module do
    Application.get_env(
      :wanderer_notifier,
      :notification_service_module,
      WandererNotifier.Domains.Notifications.NotificationService
    )
  end

  defp logger_module do
    Application.get_env(
      :wanderer_notifier,
      :logger_module,
      WandererNotifier.Shared.Logger.Logger
    )
  end
end
