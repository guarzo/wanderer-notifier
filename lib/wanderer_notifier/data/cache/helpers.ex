defmodule WandererNotifier.Data.Cache.Helpers do
  @moduledoc """
  Centralized cache helper functions.
  Implements the CacheBehaviour and provides all caching functionality.
  """

  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Get the configured cache repository module
  defp repo_module do
    Application.get_env(
      :wanderer_notifier,
      :cache_repository,
      WandererNotifier.Data.Cache.Repository
    )
  end

  @impl true
  def get(key), do: repo_module().get(key)

  @impl true
  def set(key, value, ttl), do: repo_module().set(key, value, ttl)

  @impl true
  def put(key, value), do: repo_module().put(key, value)

  @impl true
  def delete(key), do: repo_module().delete(key)

  @impl true
  def clear, do: repo_module().clear()

  @impl true
  def get_and_update(key, fun), do: repo_module().get_and_update(key, fun)

  @doc """
  Gets the list of tracked systems from the cache.
  Returns an empty list if no systems are tracked.
  """
  def get_tracked_systems do
    case repo_module().get(CacheKeys.tracked_systems_list()) do
      nil -> []
      systems when is_list(systems) -> systems
      _ -> []
    end
  end

  @doc """
  Gets tracked characters from cache.
  """
  def get_tracked_characters do
    case repo_module().get("tracked:characters") do
      nil -> []
      characters when is_list(characters) -> characters
      _ -> []
    end
  end

  @doc """
  Gets cached ship name.
  """
  def get_ship_name(ship_type_id) do
    case repo_module().get("ship:#{ship_type_id}") do
      nil -> {:error, :not_found}
      name when is_binary(name) -> {:ok, name}
      _ -> {:error, :invalid_data}
    end
  end

  @doc """
  Gets cached character name.
  """
  def get_character_name(character_id) do
    case repo_module().get("character:#{character_id}") do
      nil -> {:error, :not_found}
      name when is_binary(name) -> {:ok, name}
      _ -> {:error, :invalid_data}
    end
  end

  @doc """
  Gets cached kills.
  """
  def get_cached_kills(system_id) do
    case repo_module().get("kills:#{system_id}") do
      nil -> {:ok, []}
      kills when is_list(kills) -> {:ok, kills}
      _ -> {:error, :invalid_data}
    end
  end

  @doc """
  Adds a system to tracking and caches its data.
  Accepts both integer and string system IDs.

  ## Parameters
    - system_id: Integer or string system ID
    - system_data: Map containing system data

  ## Returns
    - :ok on success
  """
  def add_system_to_tracked(system_id, system_data) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, _} -> add_system_to_tracked(id, system_data)
      :error -> {:error, :invalid_system_id}
    end
  end

  def add_system_to_tracked(system_id, system_data) when is_integer(system_id) do
    # First, ensure the system data is cached
    system_key = CacheKeys.system(system_id)
    existing_data = repo_module().get(system_key)

    if is_nil(existing_data) do
      repo_module().put(system_key, system_data)
    end

    # Then mark the system as tracked
    tracked_key = CacheKeys.tracked_system(system_id)
    repo_module().put(tracked_key, true)

    # Finally, update the tracked systems list
    # Use a simple put operation instead of get_and_update to avoid deadlocks
    tracked_systems = repo_module().get(CacheKeys.tracked_systems_list()) || []
    system_entry = %{"system_id" => to_string(system_id)}
    updated_systems = [system_entry | tracked_systems] |> Enum.uniq()
    repo_module().put(CacheKeys.tracked_systems_list(), updated_systems)

    :ok
  end

  def add_system_to_tracked(_, _), do: {:error, :invalid_system_id}

  @doc """
  Adds a character to the tracked characters list.
  """
  def add_character_to_tracked(character_id, character_data) when is_binary(character_id) do
    case Integer.parse(character_id) do
      {id, _} -> add_character_to_tracked(id, character_data)
      :error -> {:error, :invalid_character_id}
    end
  end

  def add_character_to_tracked(character_id, character_data) when is_integer(character_id) do
    # Log the operation
    AppLogger.api_info("[CacheHelpers] Adding character to tracked characters",
      character_id: character_id,
      character_name: character_data["name"] || character_data[:name]
    )

    # First, ensure the character data is cached
    character_key = CacheKeys.character(character_id)
    existing_data = repo_module().get(character_key)

    if is_nil(existing_data) do
      repo_module().put(character_key, character_data)
    end

    # Then mark the character as tracked
    tracked_key = CacheKeys.tracked_character(character_id)
    repo_module().put(tracked_key, true)

    :ok
  end

  def add_character_to_tracked(_, _), do: {:error, :invalid_character_id}

  @doc """
  Removes a system from the tracked systems list.
  """
  def remove_system_from_tracked(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, _} -> remove_system_from_tracked(id)
      :error -> {:error, :invalid_system_id}
    end
  end

  def remove_system_from_tracked(system_id) when is_integer(system_id) do
    # Get current tracked systems
    systems = repo_module().get(CacheKeys.tracked_systems_list()) || []

    # Update tracked systems list
    updated_systems = Enum.reject(systems, &(&1["system_id"] == to_string(system_id)))
    repo_module().put(CacheKeys.tracked_systems_list(), updated_systems)

    # Remove system tracking
    repo_module().delete(CacheKeys.tracked_system(system_id))

    :ok
  end

  @doc """
  Removes a character from the tracked characters list.
  """
  def remove_character_from_tracked(character_id) when is_binary(character_id) do
    case Integer.parse(character_id) do
      {id, _} -> remove_character_from_tracked(id)
      :error -> {:error, :invalid_character_id}
    end
  end

  def remove_character_from_tracked(character_id) when is_integer(character_id) do
    # Get current tracked characters
    characters = repo_module().get("tracked:characters") || []

    # Update tracked characters list
    updated_characters = Enum.reject(characters, &(&1["character_id"] == to_string(character_id)))
    repo_module().put("tracked:characters", updated_characters)

    # Remove character tracking
    repo_module().delete("tracked:character:#{character_id}")

    :ok
  end
end
