defmodule WandererNotifier.Domains.Tracking.Handlers.GenericEventHandler do
  @moduledoc """
  Generic event handler providing shared cache and notification operations.

  This module extracts common patterns from character and system handlers,
  reducing code duplication while maintaining entity-specific behavior through
  configuration parameters.

  ## Entity Types
  - `:character` - Uses map_characters cache key, matches by "eve_id"
  - `:system` - Uses map_systems cache key, matches by solar_system_id

  ## Usage
  Handlers delegate cache and notification operations to this module while
  keeping entity-specific data extraction logic in their own modules.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Determiner

  # ══════════════════════════════════════════════════════════════════════════════
  # Entity Type Configuration
  # ══════════════════════════════════════════════════════════════════════════════

  @type entity_type :: :character | :system

  @doc """
  Returns the cache key for the given entity type.
  """
  @spec cache_key(entity_type()) :: String.t()
  def cache_key(:character), do: Cache.Keys.map_characters()
  def cache_key(:system), do: Cache.Keys.map_systems()

  @doc """
  Extracts the unique identifier from an entity based on its type.
  """
  @spec entity_id(entity_type(), map() | struct()) :: term()
  def entity_id(:character, entity), do: get_character_id(entity)
  def entity_id(:system, entity), do: get_system_id(entity)

  # ══════════════════════════════════════════════════════════════════════════════
  # Generic Cache List Operations
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Adds an entity to the cached list if it doesn't already exist.

  ## Parameters
  - `entity_type` - The type of entity (:character or :system)
  - `entity` - The entity to add
  - `opts` - Options:
    - `:ttl` - Custom TTL for the cache entry (optional, system only)

  ## Returns
  - `:ok` on success
  """
  @spec add_to_cache_list(entity_type(), map() | struct(), keyword()) :: :ok
  def add_to_cache_list(entity_type, entity, opts \\ []) do
    key = cache_key(entity_type)

    case Cache.get(key) do
      {:ok, cached_list} when is_list(cached_list) ->
        entity_identifier = entity_id(entity_type, entity)

        if entity_exists?(entity_type, cached_list, entity_identifier) do
          :ok
        else
          updated_list = [entity | cached_list]
          put_cache(entity_type, key, updated_list, opts)
          :ok
        end

      {:ok, nil} ->
        put_cache(entity_type, key, [entity], opts)
        :ok

      {:error, :not_found} ->
        put_cache(entity_type, key, [entity], opts)
        :ok
    end
  end

  @doc """
  Removes an entity from the cached list.

  ## Parameters
  - `entity_type` - The type of entity (:character or :system)
  - `entity` - The entity to remove (or map with identifier)

  ## Returns
  - `:ok` on success
  """
  @spec remove_from_cache_list(entity_type(), map() | struct()) :: :ok
  def remove_from_cache_list(entity_type, entity) do
    key = cache_key(entity_type)
    entity_identifier = entity_id(entity_type, entity)

    case Cache.get(key) do
      {:ok, cached_list} when is_list(cached_list) ->
        updated_list = reject_entity(entity_type, cached_list, entity_identifier)
        put_cache(entity_type, key, updated_list, [])
        :ok

      {:ok, nil} ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  @doc """
  Updates an entity in the cached list, or adds it if not found.

  ## Parameters
  - `entity_type` - The type of entity (:character or :system)
  - `entity` - The entity with updated data
  - `match_fn` - Optional custom matching function (default: match by entity_id)
  - `opts` - Options:
    - `:ttl` - Custom TTL for the cache entry (optional, system only)
    - `:add_if_missing` - Whether to add if not found (default: true)

  ## Returns
  - `:ok` on success
  """
  @spec update_in_cache_list(entity_type(), map() | struct(), function() | nil, keyword()) :: :ok
  def update_in_cache_list(entity_type, entity, match_fn \\ nil, opts \\ []) do
    key = cache_key(entity_type)
    entity_identifier = entity_id(entity_type, entity)
    match_function = build_match_function(match_fn, entity_type, entity_identifier)

    key
    |> Cache.get()
    |> do_update_in_cache(entity_type, key, entity, entity_identifier, match_function, opts)
  end

  defp build_match_function(nil, entity_type, entity_identifier) do
    fn cached -> matches_entity?(entity_type, cached, entity_identifier) end
  end

  defp build_match_function(match_fn, _entity_type, _entity_identifier), do: match_fn

  defp do_update_in_cache(
         {:ok, cached_list},
         entity_type,
         key,
         entity,
         entity_identifier,
         match_fn,
         opts
       )
       when is_list(cached_list) do
    add_if_missing = Keyword.get(opts, :add_if_missing, true)
    {matched, updated_list} = update_entity_in_list(cached_list, entity, match_fn, entity_type)

    final_list =
      maybe_add_entity(updated_list, entity, entity_identifier, matched, add_if_missing)

    put_cache(entity_type, key, final_list, opts)
    :ok
  end

  defp do_update_in_cache(
         {:ok, nil},
         entity_type,
         key,
         entity,
         entity_identifier,
         _match_fn,
         opts
       ) do
    maybe_add_new_entity(entity_type, key, entity, entity_identifier, opts)
  end

  defp do_update_in_cache(
         {:error, :not_found},
         entity_type,
         key,
         entity,
         entity_identifier,
         _match_fn,
         opts
       ) do
    maybe_add_new_entity(entity_type, key, entity, entity_identifier, opts)
  end

  defp maybe_add_entity(list, entity, entity_identifier, matched, add_if_missing) do
    if not matched and add_if_missing and entity_identifier do
      [entity | list]
    else
      list
    end
  end

  defp maybe_add_new_entity(entity_type, key, entity, entity_identifier, opts) do
    add_if_missing = Keyword.get(opts, :add_if_missing, true)

    if add_if_missing and entity_identifier do
      put_cache(entity_type, key, [entity], opts)
    end

    :ok
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Generic Notification Operations
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if a notification should be sent for the given entity type and ID.

  ## Parameters
  - `entity_type` - The type of entity (:character or :system)
  - `entity_identifier` - The unique identifier for the entity
  - `entity` - The full entity data for context

  ## Returns
  - `true` if notification should be sent
  - `false` otherwise
  """
  @spec should_notify?(entity_type(), term(), map() | struct()) :: boolean()
  def should_notify?(_entity_type, nil, _entity), do: false

  def should_notify?(entity_type, entity_identifier, entity) do
    Determiner.should_notify?(entity_type, entity_identifier, entity)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # ID Normalization and Comparison
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Normalizes an ID to a consistent format for comparison.
  Converts string integers to integers, leaves other values unchanged.
  """
  @spec normalize_id(term()) :: term()
  def normalize_id(id) when is_integer(id), do: id

  def normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> id
    end
  end

  def normalize_id(id), do: id

  @doc """
  Compares two IDs after normalization.
  """
  @spec ids_equal?(term(), term()) :: boolean()
  def ids_equal?(id1, id2) do
    normalize_id(id1) == normalize_id(id2)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers - Entity ID Extraction
  # ══════════════════════════════════════════════════════════════════════════════

  defp get_character_id(%{"eve_id" => eve_id}), do: eve_id
  defp get_character_id(%{eve_id: eve_id}), do: eve_id
  defp get_character_id(_), do: nil

  defp get_system_id(%WandererNotifier.Domains.Tracking.Entities.System{solar_system_id: id}),
    do: id

  defp get_system_id(%{solar_system_id: id}), do: id
  defp get_system_id(%{"solar_system_id" => id}), do: id
  defp get_system_id(%{id: id}), do: id
  defp get_system_id(%{"id" => id}), do: id
  defp get_system_id(_), do: nil

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers - Entity Matching
  # ══════════════════════════════════════════════════════════════════════════════

  defp entity_exists?(entity_type, list, entity_identifier) do
    Enum.any?(list, fn cached -> matches_entity?(entity_type, cached, entity_identifier) end)
  end

  defp matches_entity?(:character, cached, entity_identifier) do
    get_character_id(cached) == entity_identifier
  end

  defp matches_entity?(:system, cached, entity_identifier) do
    ids_equal?(get_system_id(cached), entity_identifier)
  end

  defp reject_entity(entity_type, list, entity_identifier) do
    Enum.reject(list, fn cached -> matches_entity?(entity_type, cached, entity_identifier) end)
  end

  defp update_entity_in_list(list, new_entity, match_fn, entity_type) do
    {matched, updated_list} =
      Enum.reduce(list, {false, []}, fn cached, {was_matched, acc} ->
        if match_fn.(cached) do
          merged = merge_entity(entity_type, cached, new_entity)
          {true, [merged | acc]}
        else
          {was_matched, [cached | acc]}
        end
      end)

    {matched, Enum.reverse(updated_list)}
  end

  defp merge_entity(:character, cached, new_entity) do
    # Preserve eve_id from cache when merging
    merged = Map.merge(cached, new_entity)

    if cached["eve_id"] && !new_entity["eve_id"] do
      Map.put(merged, "eve_id", cached["eve_id"])
    else
      merged
    end
  end

  defp merge_entity(:system, _cached, new_entity) do
    # For systems, we typically replace entirely since they're structs
    new_entity
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers - Cache Operations
  # ══════════════════════════════════════════════════════════════════════════════

  defp put_cache(:character, key, list, _opts) do
    Cache.put(key, list)
  end

  defp put_cache(:system, key, list, opts) do
    ttl = Keyword.get(opts, :ttl, Cache.ttl(:map_data))
    Cache.put_with_ttl(key, list, ttl)
  end
end
