defmodule WandererNotifier.PersistentValues do
  @moduledoc """
  Persistent storage for small integer lists that survive application restarts.

  This module uses an Agent to maintain state in memory and persists data to disk
  using Erlang's term_to_binary/binary_to_term serialization. Ideal for storing
  lists like priority system IDs, tracked signature types, etc.

  ## Examples

      # Read a list (returns empty list if key doesn't exist)
      ids = WandererNotifier.PersistentValues.get(:priority_systems)

      # Write a list
      :ok = WandererNotifier.PersistentValues.put(:priority_systems, [1, 2, 3])

      # Add an item to a list (convenience function)
      :ok = WandererNotifier.PersistentValues.add(:priority_systems, 4)

      # Remove an item from a list (convenience function)
      :ok = WandererNotifier.PersistentValues.remove(:priority_systems, 2)
  """

  use Agent
  require Logger

  @type key :: atom()
  @type vals :: [integer()]
  @type state :: %{key() => vals()}

  # File path for persistence - stored in application's priv directory
  @persist_file Path.join([:code.priv_dir(:wanderer_notifier), "persistent_values.bin"])

  @doc """
  Starts the PersistentValues Agent.

  Loads existing state from disk if available, otherwise starts with empty state.
  """
  def start_link(_opts) do
    Agent.start_link(&load_state/0, name: __MODULE__)
  end

  @doc """
  Gets the list of values for the given key.

  Returns an empty list if the key doesn't exist.
  """
  @spec get(key()) :: vals()
  def get(key) when is_atom(key) do
    Agent.get(__MODULE__, &Map.get(&1, key, []))
  end

  @doc """
  Stores a list of values for the given key.

  Overwrites any existing values for the key and persists to disk.
  """
  @spec put(key(), vals()) :: :ok
  def put(key, vals) when is_atom(key) and is_list(vals) do
    # Validate that all values are integers
    if Enum.any?(vals, &(not is_integer(&1))) do
      raise ArgumentError, "All values must be integers, got: #{inspect(vals)}"
    end

    Agent.update(__MODULE__, fn state ->
      new_state = Map.put(state, key, vals)
      persist_state(new_state)
      new_state
    end)
  end

  @doc """
  Adds a value to the list for the given key.

  Values are prepended to the list, creating LIFO (Last In, First Out) ordering.
  Creates the key if it doesn't exist. Does nothing if value already exists.
  """
  @spec add(key(), integer()) :: :ok
  def add(key, value) when is_atom(key) and is_integer(value) do
    current = get(key)

    if value not in current do
      put(key, [value | current])
      Logger.info("Added #{value} to #{key}")
    end

    :ok
  end

  @doc """
  Removes a value from the list for the given key.

  Does nothing if the key doesn't exist or value is not in the list.
  """
  @spec remove(key(), integer()) :: :ok
  def remove(key, value) when is_atom(key) and is_integer(value) do
    current = get(key)

    if value in current do
      put(key, List.delete(current, value))
      Logger.info("Removed #{value} from #{key}")
    end

    :ok
  end

  @doc """
  Returns all keys that have values stored.
  """
  @spec keys() :: [key()]
  def keys do
    Agent.get(__MODULE__, &Map.keys/1)
  end

  @doc """
  Returns the complete state map for debugging.
  """
  @spec all() :: state()
  def all do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Clears all data and removes the persistence file.

  ⚠️ Warning: This operation is irreversible!
  """
  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _state ->
      # Remove the persistence file
      if File.exists?(@persist_file) do
        File.rm!(@persist_file)
        Logger.info("Cleared persistent values file")
      end

      %{}
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

  # Loads state from disk, handling various error conditions gracefully
  defp load_state do
    case File.read(@persist_file) do
      {:ok, binary} ->
        case safe_binary_to_term(binary) do
          {:ok, state} when is_map(state) ->
            Logger.info("Loaded persistent values from disk: #{map_size(state)} keys")
            state

          {:error, reason} ->
            warn_and_return_empty("corrupt data: #{reason}")

          {:ok, _other} ->
            warn_and_return_empty("invalid data format (not a map)")
        end

      {:error, :enoent} ->
        Logger.info("No persistent values file found, starting empty")
        %{}

      {:error, reason} ->
        warn_and_return_empty("could not read file: #{inspect(reason)}")
    end
  end

  # Safely deserialize binary data with error handling
  defp safe_binary_to_term(binary) do
    try do
      term = :erlang.binary_to_term(binary, [:safe])
      {:ok, term}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  # Persists the current state to disk
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

      Logger.info("Persisted values to disk: #{map_size(state)} keys")
    rescue
      error ->
        Logger.error("Failed to persist values",
          error: Exception.message(error),
          file: @persist_file
        )

        # Don't raise - we don't want to crash the Agent for persistence failures
        :error
    end
  end

  # Helper to warn about issues and return empty state
  defp warn_and_return_empty(message) do
    Logger.warning("[PersistentValues] #{message}, starting empty")
    %{}
  end
end
