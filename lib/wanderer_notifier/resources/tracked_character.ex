defmodule WandererNotifier.Resources.TrackedCharacter do
  @moduledoc """
  Ash resource representing a tracked character.
  Uses ETS as the data layer since this data is already cached in memory.
  """
  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    data_layer: Ash.DataLayer.Ets,
    extensions: []

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:character_id, :integer, allow_nil?: false)
    attribute(:character_name, :string, allow_nil?: false)
    attribute(:corporation_id, :integer)
    attribute(:corporation_name, :string)
    attribute(:alliance_id, :integer)
    attribute(:alliance_name, :string)
    attribute(:tracked_since, :utc_datetime_usec, default: &DateTime.utc_now/0)
  end

  relationships do
    has_many(:killmails, WandererNotifier.Resources.Killmail,
      destination_attribute: :related_character_id,
      validate_destination_attribute?: false
    )
  end

  aggregates do
  end

  calculations do
  end

  actions do
    defaults([:create, :read, :update, :destroy])

    # Add sync_from_cache as a custom action
    action :sync_from_cache, :map do
      run(fn _, _ ->
        # Get the current cached characters using the Cache Helper
        require Logger

        # Get characters from the map:characters cache
        cached_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []

        Logger.info(
          "[TrackedCharacter] Syncing #{length(cached_characters)} characters from tracking system"
        )

        # Process each tracked character
        results =
          Enum.map(cached_characters, fn char_data ->
            # Extract character ID using the helper function
            character_id =
              case WandererNotifier.Helpers.CacheHelpers.extract_character_id(char_data) do
                nil ->
                  Logger.warning(
                    "[TrackedCharacter] Unable to extract character ID from #{inspect(char_data)}"
                  )

                  nil

                id_str ->
                  # Convert string ID to integer
                  case Integer.parse(id_str) do
                    {int_id, ""} ->
                      int_id

                    _ ->
                      Logger.warning(
                        "[TrackedCharacter] Invalid character ID format: #{inspect(id_str)}"
                      )

                      nil
                  end
              end

            # Skip invalid character IDs
            if is_nil(character_id) do
              Logger.warning(
                "[TrackedCharacter] Skipping character with invalid ID: #{inspect(char_data)}"
              )

              {:error, :invalid_character_id}
            else
              # Get character details
              character_name =
                cond do
                  is_map(char_data) && Map.has_key?(char_data, :name) ->
                    char_data.name

                  is_map(char_data) && Map.has_key?(char_data, "name") ->
                    char_data["name"]

                  is_map(char_data) && Map.has_key?(char_data, :character_name) ->
                    char_data.character_name

                  is_map(char_data) && Map.has_key?(char_data, "character_name") ->
                    char_data["character_name"]

                  true ->
                    "Unknown"
                end

              Logger.debug(
                "[TrackedCharacter] Processing character ID: #{character_id}, Name: #{character_name}"
              )

              # Check if character already exists in the Ash resource using string comparison
              str_char_id = to_string(character_id)
              query = "character_id=#{str_char_id}"

              case WandererNotifier.Resources.TrackedCharacter
                   |> Ash.Query.for_read(:read, %{filter: query})
                   |> WandererNotifier.Resources.Api.read() do
                {:ok, [existing | _]} ->
                  # Character exists, update if needed
                  changes = %{}

                  # Update name if it's different
                  changes =
                    if character_name != "Unknown" && character_name != existing.character_name do
                      Logger.debug(
                        "[TrackedCharacter] Updating name for character #{character_id}: #{existing.character_name} -> #{character_name}"
                      )

                      Map.put(changes, :character_name, character_name)
                    else
                      changes
                    end

                  # Apply updates if needed
                  if map_size(changes) > 0 do
                    Logger.info(
                      "[TrackedCharacter] Updating character: #{character_name} (#{character_id})"
                    )

                    WandererNotifier.Resources.TrackedCharacter.update(existing, changes)
                  else
                    {:ok, :unchanged}
                  end

                {:ok, []} ->
                  # Character doesn't exist, create it
                  Logger.info(
                    "[TrackedCharacter] Creating new character: #{character_name} (#{character_id})"
                  )

                  WandererNotifier.Resources.TrackedCharacter.create(%{
                    character_id: character_id,
                    character_name: character_name,
                    corporation_id: nil,
                    corporation_name: nil,
                    alliance_id: nil,
                    alliance_name: nil
                  })

                {:error, reason} ->
                  # Error querying
                  Logger.error(
                    "[TrackedCharacter] Error checking for existing character #{character_id}: #{inspect(reason)}"
                  )

                  {:error, reason}
              end
            end
          end)

        # Count successes and failures
        successes =
          Enum.count(results, fn
            {:ok, _} -> true
            _ -> false
          end)

        failures = length(results) - successes

        Logger.info(
          "[TrackedCharacter] Sync complete: #{successes} successful, #{failures} failed"
        )

        {:ok, %{successes: successes, failures: failures}}
      end)
    end
  end

  code_interface do
    define(:get, action: :read)
    define(:create, action: :create)
    define(:update, action: :update)
    define(:destroy, action: :destroy)
    define(:sync_from_cache, action: :sync_from_cache)
  end
end
