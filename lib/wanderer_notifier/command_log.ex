defmodule WandererNotifier.CommandLog do
  @moduledoc """
  Persistent logging for Discord slash command interactions.

  This module stores a history of all Discord slash commands executed, including
  the command type, parameters, user information, and timestamp. Data is persisted
  to disk and survives application restarts.

  ## Entry Format

  Each log entry is a map with the following keys:
  - `:type` - The command type (e.g. "system", "sig")
  - `:param` - The command parameter value
  - `:user_id` - Discord user ID who executed the command
  - `:username` - Discord username (optional)
  - `:timestamp` - When the command was executed (DateTime)
  - `:guild_id` - Discord guild ID where command was executed (optional)
  - `:channel_id` - Discord channel ID where command was executed (optional)

  ## Examples

      # Log a slash command interaction
      entry = %{
        type: "system",
        param: "Jita",
        user_id: 123456789,
        username: "TestUser",
        timestamp: DateTime.utc_now()
      }
      WandererNotifier.CommandLog.log(entry)

      # Get all command history
      history = WandererNotifier.CommandLog.all()

      # Get recent commands (last N entries)
      recent = WandererNotifier.CommandLog.recent(10)

      # Get commands by user
      user_commands = WandererNotifier.CommandLog.by_user(123456789)
  """

  use Agent
  require Logger

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type entry :: %{
          type: String.t(),
          param: String.t(),
          user_id: integer(),
          username: String.t() | nil,
          timestamp: DateTime.t(),
          guild_id: integer() | nil,
          channel_id: integer() | nil
        }

  @type log_state :: [entry()]

  # File path for persistence
  @persist_file Path.join([:code.priv_dir(:wanderer_notifier), "command_log.bin"])

  # Maximum number of entries to keep in memory (prevent unbounded growth)
  @max_entries 10_000

  @doc """
  Starts the CommandLog Agent.

  Loads existing command history from disk if available.
  """
  def start_link(_opts) do
    Agent.start_link(&load_state/0, name: __MODULE__)
  end

  @doc """
  Logs a Discord slash command interaction.

  The entry should contain at minimum: type, param, user_id, and timestamp.
  Missing timestamp will be added automatically.
  """
  @spec log(map()) :: :ok
  def log(entry) when is_map(entry) do
    # Validate required fields
    validate_entry!(entry)

    # Ensure timestamp is present and valid
    complete_entry =
      entry
      |> ensure_valid_timestamp()
      |> normalize_entry()

    Agent.update(__MODULE__, fn state ->
      new_state = [complete_entry | state]

      # Trim to max entries to prevent unbounded growth
      trimmed_state = Enum.take(new_state, @max_entries)

      persist_state(trimmed_state)
      trimmed_state
    end)

    AppLogger.processor_info("Command logged",
      type: entry[:type],
      param: entry[:param],
      user_id: entry[:user_id]
    )

    :ok
  end

  @doc """
  Returns all command log entries in reverse chronological order (newest first).
  """
  @spec all() :: log_state()
  def all do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Returns the most recent N command entries.
  """
  @spec recent(pos_integer()) :: log_state()
  def recent(count) when is_integer(count) and count > 0 do
    Agent.get(__MODULE__, &Enum.take(&1, count))
  end

  @doc """
  Returns all commands executed by a specific user.
  """
  @spec by_user(integer()) :: log_state()
  def by_user(user_id) when is_integer(user_id) do
    Agent.get(__MODULE__, fn state ->
      Enum.filter(state, &(&1.user_id == user_id))
    end)
  end

  @doc """
  Returns commands of a specific type (e.g., "system", "sig").
  """
  @spec by_type(String.t()) :: log_state()
  def by_type(type) when is_binary(type) do
    Agent.get(__MODULE__, fn state ->
      Enum.filter(state, &(&1.type == type))
    end)
  end

  @doc """
  Returns commands executed within the specified time range.
  """
  @spec by_date_range(DateTime.t(), DateTime.t()) :: log_state()
  def by_date_range(start_date, end_date) do
    Agent.get(__MODULE__, fn state ->
      Enum.filter(state, fn entry ->
        DateTime.compare(entry.timestamp, start_date) in [:gt, :eq] and
          DateTime.compare(entry.timestamp, end_date) in [:lt, :eq]
      end)
    end)
  end

  @doc """
  Returns usage statistics for commands.
  """
  @spec stats() :: %{
          total_commands: non_neg_integer(),
          commands_by_type: %{String.t() => non_neg_integer()},
          unique_users: non_neg_integer(),
          date_range: {DateTime.t() | nil, DateTime.t() | nil}
        }
  def stats do
    Agent.get(__MODULE__, fn state ->
      if Enum.empty?(state) do
        %{
          total_commands: 0,
          commands_by_type: %{},
          unique_users: 0,
          date_range: {nil, nil}
        }
      else
        commands_by_type = Enum.frequencies_by(state, & &1.type)
        unique_users = state |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()
        timestamps = Enum.map(state, & &1.timestamp)
        oldest = Enum.min(timestamps, DateTime)
        newest = Enum.max(timestamps, DateTime)

        %{
          total_commands: length(state),
          commands_by_type: commands_by_type,
          unique_users: unique_users,
          date_range: {oldest, newest}
        }
      end
    end)
  end

  @doc """
  Clears all command history and removes the persistence file.

  ⚠️ Warning: This operation is irreversible!
  """
  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _state ->
      if File.exists?(@persist_file) do
        File.rm!(@persist_file)
        AppLogger.config_info("Cleared command log file")
      end

      []
    end)
  end

  # Private Functions

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # Validates that the entry has required fields
  defp validate_entry!(entry) do
    required_fields = [:type, :param, :user_id]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(entry, &1))

    case missing_fields do
      [] ->
        :ok

      fields ->
        raise ArgumentError,
              "Missing required fields: #{inspect(fields)}. Got: #{inspect(entry)}"
    end

    # Validate field types
    if not is_binary(entry.type) do
      raise ArgumentError, "type must be a string, got: #{inspect(entry.type)}"
    end

    if not is_binary(entry.param) do
      raise ArgumentError, "param must be a string, got: #{inspect(entry.param)}"
    end

    if not is_integer(entry.user_id) do
      raise ArgumentError, "user_id must be an integer, got: #{inspect(entry.user_id)}"
    end
  end

  # Ensures timestamp is present and valid, replacing invalid ones
  defp ensure_valid_timestamp(entry) do
    case Map.get(entry, :timestamp) do
      %DateTime{} = timestamp -> Map.put(entry, :timestamp, timestamp)
      _ -> Map.put(entry, :timestamp, DateTime.utc_now())
    end
  end

  # Normalizes entry fields and converts to proper types
  defp normalize_entry(entry) do
    %{
      type: entry.type,
      param: entry.param,
      user_id: entry.user_id,
      username: Map.get(entry, :username),
      timestamp: entry.timestamp,
      guild_id: Map.get(entry, :guild_id),
      channel_id: Map.get(entry, :channel_id)
    }
  end

  # Loads command history from disk
  defp load_state do
    case File.read(@persist_file) do
      {:ok, binary} -> process_loaded_binary(binary)
      {:error, :enoent} -> handle_missing_file()
      {:error, reason} -> handle_file_error(reason)
    end
  end

  # Processes loaded binary data
  defp process_loaded_binary(binary) do
    case safe_binary_to_term(binary) do
      {:ok, state} when is_list(state) -> validate_and_filter_entries(state)
      {:error, reason} -> warn_and_return_empty("corrupt data: #{reason}")
      {:ok, _other} -> warn_and_return_empty("invalid data format (not a list)")
    end
  end

  # Validates entries and filters out invalid ones
  defp validate_and_filter_entries(state) do
    valid_state = Enum.filter(state, &valid_entry?/1)
    dropped_count = length(state) - length(valid_state)

    if dropped_count > 0 do
      AppLogger.startup_warn("Dropped #{dropped_count} invalid entries from command log")
    end

    AppLogger.startup_info("Loaded command log from disk: #{length(valid_state)} entries")
    valid_state
  end

  # Handles missing persistence file
  defp handle_missing_file do
    AppLogger.startup_info("No command log file found, starting empty")
    []
  end

  # Handles file read errors
  defp handle_file_error(reason) do
    warn_and_return_empty("could not read file: #{inspect(reason)}")
  end

  # Safely deserialize binary data
  defp safe_binary_to_term(binary) do
    try do
      term = :erlang.binary_to_term(binary, [:safe])
      {:ok, term}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  # Validates that an entry has the minimum required structure
  defp valid_entry?(entry) do
    is_map(entry) and
      is_binary(Map.get(entry, :type)) and
      is_binary(Map.get(entry, :param)) and
      is_integer(Map.get(entry, :user_id)) and
      is_struct(Map.get(entry, :timestamp), DateTime)
  end

  # Persists command history to disk
  defp persist_state(state) do
    try do
      # Ensure the priv directory exists
      priv_dir = Path.dirname(@persist_file)
      File.mkdir_p!(priv_dir)

      # Serialize and write atomically
      binary = :erlang.term_to_binary(state)
      temp_file = @persist_file <> ".tmp"

      File.write!(temp_file, binary)
      File.rename!(temp_file, @persist_file)

      AppLogger.config_info("Persisted command log to disk: #{length(state)} entries")
    rescue
      error ->
        AppLogger.config_error("Failed to persist command log",
          error: Exception.message(error),
          file: @persist_file
        )

        # Don't raise - we don't want to crash the Agent for persistence failures
        :error
    end
  end

  # Helper to warn about issues and return empty state
  defp warn_and_return_empty(message) do
    AppLogger.startup_warn("[CommandLog] #{message}, starting empty")
    []
  end
end
