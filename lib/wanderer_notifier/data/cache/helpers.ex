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
  def get(key) do
    AppLogger.cache_debug("Low-level cache get operation", %{key: key})
    repo_module().get(key)
  end

  @impl true
  def set(key, value, ttl) do
    AppLogger.cache_debug("Low-level cache set operation", %{key: key, ttl: ttl})
    repo_module().set(key, value, ttl)
  end

  @impl true
  def put(key, value) do
    AppLogger.cache_debug("Low-level cache put operation", %{key: key})
    repo_module().put(key, value)
  end

  @impl true
  def delete(key) do
    AppLogger.cache_debug("Low-level cache delete operation", %{key: key})
    repo_module().delete(key)
  end

  @impl true
  def clear do
    AppLogger.cache_info("Clearing entire cache")
    repo_module().clear()
  end

  @impl true
  def get_and_update(key, fun) do
    AppLogger.cache_debug("Low-level cache get_and_update operation", %{key: key})
    repo_module().get_and_update(key, fun)
  end

  @doc """
  Gets the list of tracked systems from the cache.
  Returns an empty list if no systems are tracked.
  """
  def get_tracked_systems do
    key = CacheKeys.tracked_systems_list()
    AppLogger.cache_debug("Getting tracked systems list from cache", %{key: key})

    case repo_module().get(key) do
      nil ->
        AppLogger.cache_debug("No tracked systems found in cache", %{key: key})
        []

      systems when is_list(systems) ->
        count = length(systems)

        AppLogger.cache_debug("Retrieved tracked systems from cache", %{
          key: key,
          count: count,
          sample: Enum.take(systems, min(3, count))
        })

        systems

      invalid ->
        AppLogger.cache_warn("Invalid tracked systems data in cache", %{
          key: key,
          type: typeof(invalid)
        })

        []
    end
  end

  @doc """
  Gets tracked characters from cache.
  """
  def get_tracked_characters do
    key = CacheKeys.character_list()
    AppLogger.cache_debug("Getting tracked characters list from cache", %{key: key})

    case repo_module().get(key) do
      nil ->
        AppLogger.cache_debug("No tracked characters found in cache", %{key: key})
        []

      characters when is_list(characters) ->
        count = length(characters)

        AppLogger.cache_debug("Retrieved tracked characters from cache", %{
          key: key,
          count: count,
          sample: Enum.take(characters, min(3, count))
        })

        characters

      invalid ->
        AppLogger.cache_warn("Invalid tracked characters data in cache", %{
          key: key,
          type: typeof(invalid)
        })

        []
    end
  end

  @doc """
  Gets cached ship name.
  """
  def get_ship_name(ship_type_id) do
    key = CacheKeys.ship_type(ship_type_id)
    AppLogger.cache_debug("Getting ship name from cache", %{key: key, ship_type_id: ship_type_id})

    case repo_module().get(key) do
      nil ->
        AppLogger.cache_debug("Ship name not found in cache", %{
          key: key,
          ship_type_id: ship_type_id
        })

        {:error, :not_found}

      name when is_binary(name) ->
        AppLogger.cache_debug("Retrieved ship name from cache", %{
          key: key,
          ship_type_id: ship_type_id,
          name: name
        })

        {:ok, name}

      invalid ->
        AppLogger.cache_warn("Invalid ship name data in cache", %{
          key: key,
          ship_type_id: ship_type_id,
          type: typeof(invalid)
        })

        {:error, :invalid_data}
    end
  end

  @doc """
  Gets cached character name.
  """
  def get_character_name(character_id) do
    key = CacheKeys.character(character_id)

    AppLogger.cache_debug("Getting character name from cache", %{
      key: key,
      character_id: character_id
    })

    case repo_module().get(key) do
      nil ->
        AppLogger.cache_debug("Character name not found in cache", %{
          key: key,
          character_id: character_id
        })

        # Attempt to fetch from ESI and cache it
        case fetch_and_cache_character_name(character_id) do
          {:ok, name} -> {:ok, name}
          error -> error
        end

      # Valid name found in cache
      name when is_binary(name) and name != "" and name != "Unknown" and name != "Unknown Pilot" ->
        AppLogger.cache_debug("Retrieved character name from cache", %{
          key: key,
          character_id: character_id,
          name: name
        })

        {:ok, name}

      # Return "Unknown" or "Unknown Pilot" without retrying if it was cached recently
      name when is_binary(name) and name in ["Unknown", "Unknown Pilot"] ->
        AppLogger.cache_debug("Retrieved fallback character name from cache", %{
          key: key,
          character_id: character_id,
          name: name
        })

        # Return the name even though it's a fallback - this prevents constant retries
        {:ok, name}

      invalid ->
        AppLogger.cache_warn("Invalid character name data in cache", %{
          key: key,
          character_id: character_id,
          type: typeof(invalid),
          value: inspect(invalid)
        })

        # Clear the invalid cache entry
        repo_module().delete(key)

        # Attempt to fetch from ESI and cache it
        case fetch_and_cache_character_name(character_id) do
          {:ok, name} -> {:ok, name}
          error -> error
        end
    end
  end

  # Helper to fetch character name from ESI and cache it
  defp fetch_and_cache_character_name(character_id) do
    AppLogger.cache_debug("Fetching character name from ESI", %{
      character_id: character_id
    })

    # Get ESI service module from application config
    esi_module =
      Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.Service)

    case esi_module.get_character(character_id) do
      {:ok, character_data} when is_map(character_data) ->
        name = Map.get(character_data, "name")

        if is_binary(name) && name != "" do
          # Cache the name
          cache_character_info(%{
            "character_id" => character_id,
            "name" => name
          })

          AppLogger.cache_debug("Fetched and cached character name from ESI", %{
            character_id: character_id,
            character_name: name
          })

          {:ok, name}
        else
          AppLogger.cache_warn("ESI returned invalid character name", %{
            character_id: character_id,
            name: name
          })

          # Cache the "Unknown" result to prevent repeated lookups
          cache_unknown_character(character_id)

          {:error, :invalid_esi_data}
        end

      error ->
        AppLogger.cache_warn("Failed to fetch character name from ESI", %{
          character_id: character_id,
          error: inspect(error)
        })

        # Cache the "Unknown" result to prevent repeated lookups
        cache_unknown_character(character_id)

        {:error, :esi_fetch_failed}
    end
  end

  # Helper to cache an "Unknown" character name with a shorter TTL
  defp cache_unknown_character(character_id) do
    character_key = CacheKeys.character(character_id)

    AppLogger.cache_debug("Caching 'Unknown' for failed character lookup", %{
      character_id: character_id,
      key: character_key
    })

    # Cache for 5 minutes to prevent constant retries
    repo_module().set(character_key, "Unknown", 300)
  end

  @doc """
  Gets cached kills.
  """
  def get_cached_kills(system_id) do
    key = CacheKeys.system_kills(system_id)
    AppLogger.cache_debug("Getting cached kills from cache", %{key: key, system_id: system_id})

    case repo_module().get(key) do
      nil ->
        AppLogger.cache_debug("No cached kills found", %{key: key, system_id: system_id})
        {:ok, []}

      kills when is_list(kills) ->
        count = length(kills)

        AppLogger.cache_debug("Retrieved cached kills", %{
          key: key,
          system_id: system_id,
          count: count,
          sample: (count > 0 && Enum.take(kills, min(2, count))) || []
        })

        {:ok, kills}

      invalid ->
        AppLogger.cache_warn("Invalid cached kills data", %{
          key: key,
          system_id: system_id,
          type: typeof(invalid)
        })

        {:error, :invalid_data}
    end
  end

  # Helper to get type of value for logs
  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_boolean(value), do: "boolean"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_tuple(value), do: "tuple"
  defp typeof(value) when is_atom(value), do: "atom"
  defp typeof(value) when is_function(value), do: "function"
  defp typeof(value) when is_pid(value), do: "pid"
  defp typeof(value) when is_reference(value), do: "reference"
  defp typeof(value) when is_port(value), do: "port"
  defp typeof(_value), do: "unknown"

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
    AppLogger.cache_debug("Converting string system_id to integer", %{system_id: system_id})

    case Integer.parse(system_id) do
      {id, _} ->
        AppLogger.cache_debug("Successfully parsed system_id", %{
          string_id: system_id,
          integer_id: id
        })

        add_system_to_tracked(id, system_data)

      :error ->
        AppLogger.cache_warn("Invalid system_id format", %{system_id: system_id})
        {:error, :invalid_system_id}
    end
  end

  def add_system_to_tracked(system_id, system_data) when is_integer(system_id) do
    AppLogger.cache_debug("Adding system to tracked systems", %{
      system_id: system_id,
      system_name: system_data["name"] || system_data[:name]
    })

    # First, ensure the system data is cached
    system_key = CacheKeys.system(system_id)
    existing_data = repo_module().get(system_key)

    if is_nil(existing_data) do
      AppLogger.cache_debug("Caching system data", %{system_id: system_id, key: system_key})
      repo_module().put(system_key, system_data)
    else
      AppLogger.cache_debug("System data already exists in cache", %{
        system_id: system_id,
        key: system_key
      })
    end

    # Then mark the system as tracked
    tracked_key = CacheKeys.tracked_system(system_id)
    AppLogger.cache_debug("Marking system as tracked", %{system_id: system_id, key: tracked_key})
    repo_module().put(tracked_key, true)

    # Finally, update the tracked systems list
    # Use a simple put operation instead of get_and_update to avoid deadlocks
    tracked_systems_key = CacheKeys.tracked_systems_list()
    tracked_systems = repo_module().get(tracked_systems_key) || []
    AppLogger.cache_debug("Current tracked systems count", %{count: length(tracked_systems)})

    system_entry = %{"system_id" => to_string(system_id)}
    updated_systems = [system_entry | tracked_systems] |> Enum.uniq()

    new_count = length(updated_systems)

    AppLogger.cache_debug("Updating tracked systems list", %{
      previous_count: length(tracked_systems),
      new_count: new_count,
      key: tracked_systems_key
    })

    repo_module().put(tracked_systems_key, updated_systems)

    AppLogger.cache_debug("System tracking complete", %{
      system_id: system_id,
      total_systems: new_count
    })

    :ok
  end

  def add_system_to_tracked(system_id, _) do
    AppLogger.cache_warn("Invalid system_id type", %{
      system_id: system_id,
      type: typeof(system_id)
    })

    {:error, :invalid_system_id}
  end

  @doc """
  Adds a character to the tracked characters list.
  """
  def add_character_to_tracked(character_id, character_data) when is_binary(character_id) do
    AppLogger.cache_debug("Converting string character_id to integer", %{
      character_id: character_id
    })

    case Integer.parse(character_id) do
      {id, _} ->
        AppLogger.cache_debug("Successfully parsed character_id", %{
          string_id: character_id,
          integer_id: id
        })

        add_character_to_tracked(id, character_data)

      :error ->
        AppLogger.cache_warn("Invalid character_id format", %{character_id: character_id})
        {:error, :invalid_character_id}
    end
  end

  def add_character_to_tracked(character_id, character_data) when is_integer(character_id) do
    # Log the operation - change from info to debug level
    character_name = character_data["name"] || character_data[:name] || "Unknown Character"

    AppLogger.cache_debug("Adding character to tracked characters", %{
      character_id: character_id,
      character_name: character_name
    })

    # First, ensure the character data is cached
    character_key = CacheKeys.character(character_id)
    existing_data = repo_module().get(character_key)

    if is_nil(existing_data) do
      AppLogger.cache_debug("Caching character data", %{
        character_id: character_id,
        key: character_key
      })

      repo_module().put(character_key, character_data)
    else
      AppLogger.cache_debug("Character data already exists in cache", %{
        character_id: character_id,
        key: character_key
      })
    end

    # Then mark the character as tracked
    tracked_key = CacheKeys.tracked_character(character_id)

    AppLogger.cache_debug("Marking character as tracked", %{
      character_id: character_id,
      key: tracked_key
    })

    repo_module().put(tracked_key, true)

    AppLogger.cache_debug("Character tracking complete", %{
      character_id: character_id,
      character_name: character_name
    })

    :ok
  end

  def add_character_to_tracked(character_id, _) do
    AppLogger.cache_warn("Invalid character_id type", %{
      character_id: character_id,
      type: typeof(character_id)
    })

    {:error, :invalid_character_id}
  end

  @doc """
  Removes a system from the tracked systems list.
  """
  def remove_system_from_tracked(system_id) when is_binary(system_id) do
    AppLogger.cache_debug("Converting string system_id to integer", %{system_id: system_id})

    case Integer.parse(system_id) do
      {id, _} ->
        AppLogger.cache_debug("Successfully parsed system_id", %{
          string_id: system_id,
          integer_id: id
        })

        remove_system_from_tracked(id)

      :error ->
        AppLogger.cache_warn("Invalid system_id format", %{system_id: system_id})
        {:error, :invalid_system_id}
    end
  end

  def remove_system_from_tracked(system_id) when is_integer(system_id) do
    AppLogger.cache_debug("Removing system from tracked systems", %{system_id: system_id})

    # Get current tracked systems
    tracked_systems_key = CacheKeys.tracked_systems_list()
    systems = repo_module().get(tracked_systems_key) || []

    previous_count = length(systems)
    AppLogger.cache_debug("Current tracked systems count", %{count: previous_count})

    # Update tracked systems list
    updated_systems = Enum.reject(systems, &(&1["system_id"] == to_string(system_id)))
    new_count = length(updated_systems)

    AppLogger.cache_debug("Updating tracked systems list", %{
      previous_count: previous_count,
      new_count: new_count,
      key: tracked_systems_key
    })

    repo_module().put(tracked_systems_key, updated_systems)

    # Remove system tracking
    tracked_key = CacheKeys.tracked_system(system_id)

    AppLogger.cache_debug("Removing system tracking flag", %{
      system_id: system_id,
      key: tracked_key
    })

    repo_module().delete(tracked_key)

    AppLogger.cache_debug("System untracking complete", %{
      system_id: system_id,
      total_systems: new_count
    })

    :ok
  end

  def remove_system_from_tracked(system_id) do
    AppLogger.cache_warn("Invalid system_id type", %{
      system_id: system_id,
      type: typeof(system_id)
    })

    {:error, :invalid_system_id}
  end

  @doc """
  Removes a character from the tracked characters list.
  """
  def remove_character_from_tracked(character_id) when is_binary(character_id) do
    AppLogger.cache_debug("Converting string character_id to integer", %{
      character_id: character_id
    })

    case Integer.parse(character_id) do
      {id, _} ->
        AppLogger.cache_debug("Successfully parsed character_id", %{
          string_id: character_id,
          integer_id: id
        })

        remove_character_from_tracked(id)

      :error ->
        AppLogger.cache_warn("Invalid character_id format", %{character_id: character_id})
        {:error, :invalid_character_id}
    end
  end

  def remove_character_from_tracked(character_id) when is_integer(character_id) do
    AppLogger.cache_debug("Removing character from tracked characters", %{
      character_id: character_id
    })

    # Get current tracked characters
    character_list_key = CacheKeys.character_list()
    characters = repo_module().get(character_list_key) || []

    previous_count = length(characters)
    AppLogger.cache_debug("Current tracked characters count", %{count: previous_count})

    # Update tracked characters list
    updated_characters = Enum.reject(characters, &(&1["character_id"] == to_string(character_id)))
    new_count = length(updated_characters)

    AppLogger.cache_debug("Updating tracked characters list", %{
      previous_count: previous_count,
      new_count: new_count,
      key: character_list_key
    })

    repo_module().put(character_list_key, updated_characters)

    # Remove character tracking
    tracked_key = CacheKeys.tracked_character(character_id)

    AppLogger.cache_debug("Removing character tracking flag", %{
      character_id: character_id,
      key: tracked_key
    })

    repo_module().delete(tracked_key)

    AppLogger.cache_debug("Character untracking complete", %{
      character_id: character_id,
      total_characters: new_count
    })

    :ok
  end

  def remove_character_from_tracked(character_id) do
    AppLogger.cache_warn("Invalid character_id type", %{
      character_id: character_id,
      type: typeof(character_id)
    })

    {:error, :invalid_character_id}
  end

  @doc """
  Caches character information, including the name.
  This is used to ensure character names are available for later use.

  ## Parameters
    - character_data: Map containing character data with "character_id" and "name" fields

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def cache_character_info(character_data) when is_map(character_data) do
    character_id = character_data["character_id"] || character_data[:character_id]
    character_name = character_data["name"] || character_data[:name]

    # Enhanced logging for debugging
    AppLogger.cache_debug("Character info received for caching", %{
      character_id: character_id,
      character_name: character_name,
      data_keys: Map.keys(character_data)
    })

    if is_nil(character_id) do
      AppLogger.cache_warn("Missing character_id in cache_character_info", %{
        character_data: inspect(character_data, limit: 500)
      })

      {:error, :missing_character_id}
    else
      # Convert character_id to integer if it's a string
      char_id =
        if is_binary(character_id) do
          case Integer.parse(character_id) do
            {id, _} -> id
            :error -> nil
          end
        else
          character_id
        end

      if is_nil(char_id) do
        AppLogger.cache_warn("Invalid character_id format in cache_character_info", %{
          character_id: character_id,
          type: typeof(character_id)
        })

        {:error, :invalid_character_id}
      else
        # Check for valid character name
        valid_character_name =
          is_binary(character_name) &&
            character_name != "" &&
            character_name != "Unknown" &&
            character_name != "Unknown Pilot"

        if valid_character_name do
          # Store character name in character key
          character_key = CacheKeys.character(char_id)

          AppLogger.cache_debug("Caching valid character name", %{
            character_id: char_id,
            character_name: character_name,
            key: character_key
          })

          # Cache for 24 hours
          repo_module().set(character_key, character_name, 86400)
          :ok
        else
          # If the name is "Unknown" or "Unknown Pilot", still cache it but with shorter TTL
          # to prevent constant re-fetching
          if is_binary(character_name) && character_name != "" do
            character_key = CacheKeys.character(char_id)

            AppLogger.cache_debug("Caching fallback character name with shorter TTL", %{
              character_id: char_id,
              character_name: character_name,
              key: character_key
            })

            # Cache for 1 hour instead of 24 hours
            repo_module().set(character_key, character_name, 3600)
            :ok
          else
            # Query the character directly from ESI
            AppLogger.cache_debug("Fetching character name from ESI", %{
              character_id: char_id,
              reason: "Invalid name in provided data"
            })

            # Get ESI service module from application config
            esi_module =
              Application.get_env(
                :wanderer_notifier,
                :esi_service,
                WandererNotifier.Api.ESI.Service
              )

            case esi_module.get_character(char_id) do
              {:ok, esi_data} when is_map(esi_data) ->
                esi_name = Map.get(esi_data, "name")

                if is_binary(esi_name) && esi_name != "" do
                  # Store valid ESI name
                  character_key = CacheKeys.character(char_id)

                  AppLogger.cache_info("Caching character name from ESI", %{
                    character_id: char_id,
                    character_name: esi_name,
                    key: character_key
                  })

                  # Cache for 24 hours
                  repo_module().set(character_key, esi_name, 86400)
                  :ok
                else
                  AppLogger.cache_warn("ESI returned invalid character name", %{
                    character_id: char_id,
                    esi_name: esi_name
                  })

                  {:error, :invalid_esi_character_name}
                end

              error ->
                AppLogger.cache_warn("Failed to fetch character name from ESI", %{
                  character_id: char_id,
                  error: inspect(error)
                })

                {:error, :esi_fetch_failed}
            end
          end
        end
      end
    end
  end

  def cache_character_info(invalid_data) do
    AppLogger.cache_warn("Invalid data provided to cache_character_info", %{
      data: inspect(invalid_data, limit: 500),
      type: typeof(invalid_data)
    })

    {:error, :invalid_data}
  end
end
