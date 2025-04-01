defmodule WandererNotifier.Data.Cache.Helpers do
  @moduledoc """
  Centralized cache helper functions.
  Implements the CacheBehaviour and provides all caching functionality.
  """

  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  # Get the configured cache repository module
  defp repo_module do
    Application.get_env(
      :wanderer_notifier,
      :cache_repository,
      WandererNotifier.Data.Cache.Repository
    )
  end

  @doc """
  Gets tracked systems from cache.
  """
  def get_tracked_systems do
    case repo_module().get("tracked:systems") do
      nil -> []
      systems when is_list(systems) -> systems
      _ -> []
    end
  end

  @doc """
  Gets tracked characters from cache.
  """
  @impl true
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
  @impl true
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
  @impl true
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
  @impl true
  def get_cached_kills(system_id) do
    case repo_module().get("kills:#{system_id}") do
      nil -> {:ok, []}
      kills when is_list(kills) -> {:ok, kills}
      _ -> {:error, :invalid_data}
    end
  end

  @doc """
  Adds a system to the tracked systems list.
  """
  def add_system_to_tracked(system_id, system_data) when is_binary(system_id) do
    add_system_to_tracked(String.to_integer(system_id), system_data)
  end

  def add_system_to_tracked(system_id, system_data) when is_integer(system_id) do
    # Update tracked systems list
    {_, _} =
      repo_module().get_and_update("tracked:systems", fn current_systems ->
        current_systems = current_systems || []
        updated_systems = Enum.uniq([%{"system_id" => to_string(system_id)} | current_systems])
        {current_systems, updated_systems}
      end)

    # Mark system as tracked
    repo_module().put("tracked:system:#{system_id}", true)

    # Store system data if not already stored
    case repo_module().get("map:system:#{system_id}") do
      nil -> repo_module().put("map:system:#{system_id}", system_data)
      _ -> :ok
    end

    :ok
  end

  @doc """
  Adds a character to the tracked characters list.
  """
  def add_character_to_tracked(character_id, character_data) when is_binary(character_id) do
    add_character_to_tracked(String.to_integer(character_id), character_data)
  end

  def add_character_to_tracked(character_id, character_data) when is_integer(character_id) do
    # Update tracked characters list
    {_, _} =
      repo_module().get_and_update("tracked:characters", fn current_characters ->
        current_characters = current_characters || []

        updated_characters =
          Enum.uniq([%{"character_id" => to_string(character_id)} | current_characters])

        {current_characters, updated_characters}
      end)

    # Mark character as tracked
    repo_module().put("tracked:character:#{character_id}", true)

    # Store character data if not already stored
    case repo_module().get("map:character:#{character_id}") do
      nil -> repo_module().put("map:character:#{character_id}", character_data)
      _ -> :ok
    end

    :ok
  end

  @doc """
  Removes a system from the tracked systems list.
  """
  def remove_system_from_tracked(system_id) when is_binary(system_id) do
    remove_system_from_tracked(String.to_integer(system_id))
  end

  def remove_system_from_tracked(system_id) when is_integer(system_id) do
    # Get current tracked systems
    systems = repo_module().get("tracked:systems") || []

    # Update tracked systems list
    updated_systems = Enum.reject(systems, &(&1["system_id"] == to_string(system_id)))
    repo_module().put("tracked:systems", updated_systems)

    # Remove system tracking
    repo_module().delete("tracked:system:#{system_id}")

    :ok
  end

  @doc """
  Removes a character from the tracked characters list.
  """
  def remove_character_from_tracked(character_id) when is_binary(character_id) do
    remove_character_from_tracked(String.to_integer(character_id))
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
