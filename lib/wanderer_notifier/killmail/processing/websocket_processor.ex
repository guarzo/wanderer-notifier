defmodule WandererNotifier.Killmail.Processing.WebsocketProcessor do
  @moduledoc """
  Processes killmails from the ZKillboard websocket.

  This module handles the processing of killmail data received from the ZKillboard websocket.
  It is separate from the actual WebSocket connection handling, which is managed by the
  WandererNotifier.Api.ZKill.Websocket module.

  The processor is responsible for:
  - Extracting killmail data from the WebSocket messages
  - Processing killmails through the standard pipeline
  - Handling errors and tracking metrics
  """

  require Logger

  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Killmail.Core.Context
  alias WandererNotifier.Killmail.Processing.Processor
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Add dependency injection for Processor and ZKillClient
  defp zkill_client, do: Application.get_env(:wanderer_notifier, :zkill_client, ZKillClient)
  defp processor, do: Application.get_env(:wanderer_notifier, :processor, Processor)

  # API

  @doc """
  Initializes the websocket processor module.
  Called during application startup.
  """
  @spec init() :: :ok
  def init do
    AppLogger.startup_info("Initializing ZKillboard WebsocketProcessor")
    schedule_tasks()
    :ok
  end

  @doc """
  Schedules periodic tasks for the websocket processor.
  """
  @spec schedule_tasks() :: :ok
  def schedule_tasks do
    # Schedule statistics logging every 15 minutes
    schedule_log_stats()
    :ok
  end

  @doc """
  Logs processor statistics.
  """
  @spec log_stats() :: :ok
  def log_stats do
    # Get current statistics
    stats = get_stats()

    # Log the statistics
    AppLogger.processor_info("ZKillboard Processor Statistics", stats)

    # Schedule the next log
    schedule_log_stats()

    :ok
  end

  @doc """
  Processes a message from the ZKillboard websocket.

  ## Parameters
    - message: The message received from the websocket
    - state: Current state of processing metrics (processed count, errors)

  ## Returns
    - {:ok, updated_state} with the updated state including updated metrics
    - {:error, reason} on failure
  """
  @spec process_zkill_message(map(), map()) :: {:ok, map()} | {:error, any()}
  def process_zkill_message(message, state) do
    # Extract the package data from the message
    case extract_package(message) do
      {:ok, package} ->
        # Process the package
        process_package(package, state)

      {:error, :no_package} ->
        # Not a killmail package, might be a heartbeat or other message
        {:ok, state}

      {:error, reason} ->
        # Log the error
        AppLogger.processor_error("Failed to extract package from message", %{
          message: inspect(message),
          error: inspect(reason)
        })

        # Return updated state with incremented error count
        {:ok, update_errors(state)}
    end
  end

  @doc """
  Handles any message received by the websocket.

  ## Parameters
    - message: The message received (can be JSON string or already decoded map)
    - state: Current state of processing metrics

  ## Returns
    - {:ok, updated_state} with the updated state
    - {:error, reason} on failure
  """
  @spec handle_message(map() | String.t(), map()) :: {:ok, map()} | {:error, any()}
  def handle_message(message, state) when is_binary(message) do
    # Parse the message from JSON
    case Jason.decode(message) do
      {:ok, decoded} ->
        # Process the decoded message
        process_zkill_message(decoded, state)

      {:error, reason} ->
        # Log the error
        AppLogger.processor_error("Failed to decode message", %{
          # Limit to avoid huge logs
          message: String.slice(message, 0, 100),
          error: inspect(reason)
        })

        # Return updated state with incremented error count
        {:ok, update_errors(state)}
    end
  end

  def handle_message(message, state) when is_map(message) do
    # Already decoded, process it directly
    process_zkill_message(message, state)
  end

  def handle_message(message, state) do
    # Unexpected message type
    AppLogger.processor_error("Unexpected message type", %{
      message: inspect(message),
      type: type_of(message)
    })

    # Return updated state with incremented error count
    {:ok, update_errors(state)}
  end

  @doc """
  Processes a single killmail package.

  ## Parameters
    - package: The killmail package to process
    - state: The current state with processing metrics

  ## Returns
    - {:ok, updated_state} with the updated state
    - {:error, reason} on failure
  """
  @spec process_package(map(), map()) :: {:ok, map()} | {:error, any()}
  def process_package(package, state) do
    # Extract the killmail data (support both "killID" and "killmail_id" formats)
    killmail_id = get_killmail_id(package)
    hash = get_hash(package)

    # Check if we have the required data
    if killmail_id && hash do
      # Create a context for processing
      context = Context.new_realtime(nil, nil, :websocket)

      # Process the kill
      case process_kill(killmail_id, hash, context, package) do
        {:ok, _result} ->
          # Update state with incremented processed count
          {:ok, update_processed(state)}

        {:error, reason} ->
          # Log error
          AppLogger.processor_error("Failed to process killmail", %{
            kill_id: killmail_id,
            hash: hash,
            error: inspect(reason)
          })

          # Update state with incremented error count
          {:ok, update_errors(state)}
      end
    else
      # Log the error
      AppLogger.processor_error("Invalid package data", %{
        package: inspect(package),
        missing: if(!killmail_id, do: "killmail_id", else: "hash")
      })

      # Update state with incremented error count
      {:ok, update_errors(state)}
    end
  end

  @doc """
  Processes a single kill identified by ID and hash.

  ## Parameters
    - kill_id: The killmail ID
    - hash: The killmail hash
    - context: The processing context
    - package: Optional pre-loaded package data

  ## Returns
    - {:ok, result} with the processing result
    - {:error, reason} on failure
  """
  @spec process_kill(integer() | String.t(), String.t(), Context.t(), map() | nil) ::
          {:ok, term()} | {:error, any()}
  def process_kill(kill_id, hash, context, package \\ nil) do
    # If we already have the package data, use it directly
    if package && is_valid_killmail_data(package) do
      # Log processing
      AppLogger.processor_debug("Processing killmail ##{kill_id} from websocket data")

      # Process the killmail through the standard pipeline
      processor().process_killmail(package, context)
    else
      # Fetch the killmail data from ZKillboard
      case zkill_client().get_single_killmail(kill_id) do
        {:ok, zkill_data} ->
          # Log successful fetch
          AppLogger.processor_debug("Processing killmail ##{kill_id} from fresh fetch")

          # Process the killmail through the standard pipeline
          processor().process_killmail(zkill_data, context)

        {:error, reason} ->
          # Log the error
          AppLogger.processor_error("Failed to fetch killmail from ZKillboard", %{
            kill_id: kill_id,
            hash: hash,
            error: inspect(reason)
          })

          # Return the error
          {:error, reason}
      end
    end
  end

  @doc """
  Gets recent kills from the cache.

  ## Returns
    - List of recent kills
  """
  @spec get_recent_kills() :: list()
  def get_recent_kills do
    # This will be implemented to fetch from our cache
    []
  end

  @doc """
  Sends a test kill notification for debugging purposes.

  ## Returns
    - :ok
  """
  @spec send_test_kill_notification() :: :ok
  def send_test_kill_notification do
    AppLogger.processor_info("Sending test kill notification")

    # Use a hardcoded kill ID for testing
    test_kill_id = 107_688_756

    # Create a test context
    context = Context.new_realtime(nil, "Test", :test, %{force_notification: true})

    # Process the test kill
    case zkill_client().get_single_killmail(test_kill_id) do
      {:ok, zkill_data} ->
        # Process the test killmail with notification forced
        processor().process_killmail(zkill_data, context)

      {:error, reason} ->
        # Log the error
        AppLogger.processor_error("Failed to fetch test killmail", %{
          kill_id: test_kill_id,
          error: inspect(reason)
        })
    end

    :ok
  end

  @doc """
  Processes a single kill from a websocket message.

  ## Parameters
    - kill: The kill data
    - ctx: The processing context

  ## Returns
    - {:ok, result} with the processing result
    - {:error, reason} on failure
  """
  @spec process_single_kill(map(), Context.t()) :: {:ok, term()} | {:error, any()}
  def process_single_kill(kill, ctx) do
    # Process the kill through the standard pipeline
    processor().process_killmail(kill, ctx)
  end

  # Private helper functions

  # Safe update helpers that handle nil values
  defp update_processed(state) do
    Map.update(state, :processed, 1, &(&1 + 1))
  end

  defp update_errors(state) do
    Map.update(state, :errors, 1, &(&1 + 1))
  end

  # Extracts the package data from a message
  defp extract_package(message) when is_map(message) do
    cond do
      # Check if it's a killmail package
      Map.has_key?(message, "package") && is_map(message["package"]) ->
        {:ok, message["package"]}

      # Check if it's already a killmail
      is_valid_killmail_data(message) ->
        {:ok, message}

      # Not a killmail package
      true ->
        {:error, :no_package}
    end
  end

  defp extract_package(_), do: {:error, :invalid_message}

  # Check if the data is a valid killmail
  defp is_valid_killmail_data(data) when is_map(data) do
    # Check for typical killmail fields
    has_killmail_id =
      Map.has_key?(data, "killmail_id") ||
        Map.has_key?(data, "killID") ||
        (Map.has_key?(data, "zkb") && is_map(data["zkb"]))

    has_hash =
      Map.has_key?(data, "hash") ||
        (Map.has_key?(data, "zkb") && is_map(data["zkb"]) && Map.has_key?(data["zkb"], "hash"))

    has_killmail_id && has_hash
  end

  defp is_valid_killmail_data(_), do: false

  # Helper to get killmail ID from various formats
  defp get_killmail_id(data) when is_map(data) do
    cond do
      Map.has_key?(data, "killmail_id") ->
        data["killmail_id"]

      Map.has_key?(data, "killID") ->
        data["killID"]

      Map.has_key?(data, "zkb") && is_map(data["zkb"]) && Map.has_key?(data["zkb"], "killmail_id") ->
        data["zkb"]["killmail_id"]

      true ->
        nil
    end
  end

  defp get_killmail_id(_), do: nil

  # Helper to get hash from various formats
  defp get_hash(data) when is_map(data) do
    cond do
      Map.has_key?(data, "hash") ->
        data["hash"]

      Map.has_key?(data, "zkb") && is_map(data["zkb"]) && Map.has_key?(data["zkb"], "hash") ->
        data["zkb"]["hash"]

      true ->
        nil
    end
  end

  defp get_hash(_), do: nil

  # Gets processor statistics
  defp get_stats do
    %{
      processed: get_stat(:processed),
      errors: get_stat(:errors)
    }
  end

  # Gets a specific statistic value
  defp get_stat(_key) do
    # This would normally use persistent storage or ETS
    # For now we'll just return 0
    0
  end

  # Schedules the next statistics logging
  defp schedule_log_stats do
    # Log stats every 15 minutes
    :timer.apply_after(15 * 60 * 1000, __MODULE__, :log_stats, [])
  end

  # Gets the type of a value for error reporting
  defp type_of(value) do
    cond do
      is_binary(value) -> :string
      is_map(value) -> :map
      is_list(value) -> :list
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_nil(value) -> nil
      is_atom(value) -> :atom
      true -> :unknown
    end
  end
end
