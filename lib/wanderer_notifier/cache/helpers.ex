defmodule WandererNotifier.Cache.Helpers do
  @moduledoc """
  Centralized cache helper functions.
  Implements the HelpersBehaviour and provides all caching functionality.
  """

  @behaviour WandererNotifier.Cache.HelpersBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Logger.Logger, as: AppLogger

  defp repo_module do
    Application.get_env(:wanderer_notifier, :cache, [])
    |> Keyword.get(:repo, WandererNotifier.Cache.Repository)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def get(key) do
    AppLogger.log_with_timing(:debug, "cache-helpers-get", %{key: key}, fn ->
      repo_module().get(key)
    end)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def set(key, value) do
    AppLogger.log_with_timing(:debug, "cache-helpers-set", %{key: key}, fn ->
      repo_module().set(key, value)
    end)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def put(key, value) do
    AppLogger.log_with_timing(:debug, "cache-helpers-put", %{key: key}, fn ->
      repo_module().put(key, value)
    end)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def delete(key) do
    AppLogger.log_with_timing(:debug, "cache-helpers-delete", %{key: key}, fn ->
      repo_module().delete(key)
    end)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def clear() do
    AppLogger.log_with_timing(:debug, "cache-helpers-clear", %{}, fn ->
      repo_module().clear()
    end)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def get_and_update(key, fun) do
    AppLogger.log_with_timing(:debug, "cache-helpers-get-and-update", %{key: key}, fn ->
      repo_module().get_and_update(key, fun)
    end)
  end

  @impl WandererNotifier.Cache.HelpersBehaviour
  def get_tracked_systems() do
    AppLogger.log_with_timing(:debug, "cache-helpers-get-tracked-systems", %{}, fn ->
      case get(CacheKeys.tracked_systems()) do
        {:ok, tracked_systems} when is_list(tracked_systems) ->
          {:ok, tracked_systems}

        {:ok, tracked_systems} ->
          AppLogger.log(:error, "cache-helpers-get-tracked-systems-invalid-type", %{
            type: typeof(tracked_systems)
          })

          {:error, :invalid_type}

        {:error, _} = error ->
          error
      end
    end)
  end

  @doc """
  Gets the list of tracked characters.
  """
  def get_tracked_characters() do
    AppLogger.log_with_timing(:debug, "cache-helpers-get-tracked-characters", %{}, fn ->
      case get(CacheKeys.tracked_characters_list()) do
        {:ok, tracked_characters} when is_list(tracked_characters) ->
          {:ok, tracked_characters}

        {:ok, tracked_characters} ->
          AppLogger.log(:error, "cache-helpers-get-tracked-characters-invalid-type", %{
            type: typeof(tracked_characters)
          })

          {:error, :invalid_type}

        {:error, _} = error ->
          error
      end
    end)
  end

  @doc """
  Adds a character to the tracked characters list.
  """
  def add_character_to_tracked(character_id, character_data) when is_binary(character_id) do
    AppLogger.log(:debug, "add-character-to-tracked-string", %{character_id: character_id})

    case Integer.parse(character_id) do
      {id, _} -> add_character_to_tracked(id, character_data)
      :error -> {:error, :invalid_character_id}
    end
  end

  def add_character_to_tracked(character_id, character_data) when is_integer(character_id) do
    character_name = extract_name(character_data)

    AppLogger.log(:debug, "add-character-to-tracked", %{
      character_id: character_id,
      character_name: character_name
    })

    # Ensure the character data is cached
    character_key = CacheKeys.character(character_id)
    put(character_key, character_data)

    # Mark the character as tracked
    tracked_key = CacheKeys.tracked_character(character_id)
    put(tracked_key, true)

    :ok
  end

  def add_character_to_tracked(character_id, _) do
    AppLogger.log(:warn, "add-character-to-tracked-invalid-id", %{
      character_id: character_id,
      type: typeof(character_id)
    })

    {:error, :invalid_character_id}
  end

  # Extract name from character data regardless of format
  defp extract_name(character_data) do
    cond do
      is_map(character_data) && Map.has_key?(character_data, :name) -> character_data.name
      is_map(character_data) && Map.has_key?(character_data, "name") -> character_data["name"]
      true -> "Unknown Character"
    end
  end

  @doc """
  Adds a system to the tracked systems list.
  """
  def add_system_to_tracked(system_id, system_name) when is_binary(system_id) do
    AppLogger.log(:debug, "add-system-to-tracked-string", %{system_id: system_id})

    case Integer.parse(system_id) do
      {id, _} -> add_system_to_tracked(id, system_name)
      :error -> {:error, :invalid_system_id}
    end
  end

  def add_system_to_tracked(system_id, system_name) when is_integer(system_id) do
    AppLogger.log(:debug, "add-system-to-tracked", %{
      system_id: system_id,
      system_name: system_name
    })

    # Ensure the system data is cached
    system_key = CacheKeys.system(system_id)

    system_data = %{
      "system_id" => system_id,
      "name" => system_name
    }

    put(system_key, system_data)

    # Mark the system as tracked
    tracked_key = CacheKeys.tracked_system(system_id)
    put(tracked_key, true)

    :ok
  end

  def add_system_to_tracked(system_id, _) do
    AppLogger.log(:warn, "add-system-to-tracked-invalid-id", %{
      system_id: system_id,
      type: typeof(system_id)
    })

    {:error, :invalid_system_id}
  end

  defp typeof(term) when is_nil(term), do: "nil"
  defp typeof(term) when is_binary(term), do: "binary"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_integer(term), do: "integer"
  defp typeof(term) when is_float(term), do: "float"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_pid(term), do: "pid"
  defp typeof(term) when is_port(term), do: "port"
  defp typeof(term) when is_reference(term), do: "reference"
  defp typeof(_term), do: "unknown"

  @doc """
  Get ship name from ship type ID.
  """
  @spec get_ship_name(integer() | String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_ship_name(ship_type_id) do
    AppLogger.log_with_timing(
      :debug,
      "cache-helpers-get-ship-name",
      %{ship_type_id: ship_type_id},
      fn ->
        ship_key = CacheKeys.ship_type(ship_type_id)

        case get(ship_key) do
          {:ok, ship_data} when is_map(ship_data) ->
            name = Map.get(ship_data, "name") || Map.get(ship_data, :name) || "Unknown Ship"
            {:ok, name}

          {:ok, name} when is_binary(name) ->
            {:ok, name}

          {:error, _} = error ->
            error

          _ ->
            {:error, :invalid_ship_data}
        end
      end
    )
  end

  @doc """
  Get character name from character ID.
  """
  @spec get_character_name(integer() | String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_character_name(character_id) do
    AppLogger.log_with_timing(
      :debug,
      "cache-helpers-get-character-name",
      %{character_id: character_id},
      fn ->
        character_key = CacheKeys.character(character_id)

        case get(character_key) do
          {:ok, character_data} when is_map(character_data) ->
            name =
              Map.get(character_data, "name") || Map.get(character_data, :name) ||
                "Unknown Character"

            {:ok, name}

          {:ok, name} when is_binary(name) ->
            {:ok, name}

          {:error, _} = error ->
            error

          _ ->
            {:error, :invalid_character_data}
        end
      end
    )
  end

  @doc """
  Get cached kills for a system.
  """
  @spec get_cached_kills(integer() | String.t()) :: {:ok, list()} | {:error, atom()}
  def get_cached_kills(system_id) do
    AppLogger.log_with_timing(
      :debug,
      "cache-helpers-get-cached-kills",
      %{system_id: system_id},
      fn ->
        system_kills_key = "#{CacheKeys.system(system_id)}:kills"

        case get(system_kills_key) do
          {:ok, kills} when is_list(kills) ->
            {:ok, kills}

          {:ok, _} ->
            {:ok, []}

          {:error, _} ->
            {:ok, []}
        end
      end
    )
  end
end
