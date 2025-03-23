defmodule WandererNotifier.Resources.TrackedCharacter do
  @moduledoc """
  Ash resource representing a tracked character.
  Uses Postgres as the data layer for persistence.
  """
  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  postgres do
    table("tracked_characters")
    repo(WandererNotifier.Repo)
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

  identities do
    identity(:unique_character_id, [:character_id])
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
            # Extract character ID directly instead of using the helper function
            character_id =
              case extract_character_id_from_data(char_data) do
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
              # Extract character name if available
              character_name = extract_character_name(char_data)

              # Log character details for debugging
              Logger.debug(
                "[TrackedCharacter] Processing character ID: #{character_id}, Name: #{character_name}"
              )

              # Check if character already exists in the Ash resource using string comparison
              str_char_id = to_string(character_id)

              # Use the read function to look for existing character
              case WandererNotifier.Resources.Api.read(__MODULE__,
                     filter: [character_id: [eq: character_id]]
                   ) do
                {:ok, [existing | _]} ->
                  # Character exists, update if needed
                  changes = %{}

                  # Update name if it's different and not nil
                  changes =
                    if character_name && character_name != existing.character_name do
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

                    WandererNotifier.Resources.Api.update(__MODULE__, existing.id, changes)
                  else
                    {:ok, :unchanged}
                  end

                {:ok, []} ->
                  # Character doesn't exist, create it
                  Logger.info(
                    "[TrackedCharacter] Creating new character: #{character_name || "Unknown"} (#{character_id})"
                  )

                  WandererNotifier.Resources.Api.create(__MODULE__, %{
                    character_id: character_id,
                    character_name: character_name || "Unknown Character",
                    corporation_id: extract_corporation_id(char_data),
                    corporation_name: extract_corporation_name(char_data),
                    alliance_id: extract_alliance_id(char_data),
                    alliance_name: extract_alliance_name(char_data)
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

    # Helper functions for extracting character information
    defp extract_character_id_from_data(char_data) do
      cond do
        # Handle Character struct
        is_struct(char_data) && Map.has_key?(char_data, :character_id) ->
          to_string(char_data.character_id)

        # Handle map with string/atom keys
        is_map(char_data) &&
            (Map.has_key?(char_data, "character_id") || Map.has_key?(char_data, :character_id)) ->
          char_id = char_data["character_id"] || char_data[:character_id]
          if char_id, do: to_string(char_id), else: nil

        # Handle direct ID (integer or string)
        is_integer(char_data) || is_binary(char_data) ->
          to_string(char_data)

        # No matching format
        true ->
          nil
      end
    end

    defp extract_character_name(char_data) when is_map(char_data) do
      char_data["name"] ||
        char_data[:name] ||
        char_data["character_name"] ||
        char_data[:character_name]
    end

    defp extract_character_name(_), do: nil

    defp extract_corporation_id(char_data) when is_map(char_data) do
      corp_id = char_data["corporation_id"] || char_data[:corporation_id]
      if is_binary(corp_id), do: String.to_integer(corp_id), else: corp_id
    end

    defp extract_corporation_id(_), do: nil

    defp extract_corporation_name(char_data) when is_map(char_data) do
      char_data["corporation_name"] || char_data[:corporation_name]
    end

    defp extract_corporation_name(_), do: nil

    defp extract_alliance_id(char_data) when is_map(char_data) do
      alliance_id = char_data["alliance_id"] || char_data[:alliance_id]
      if is_binary(alliance_id), do: String.to_integer(alliance_id), else: alliance_id
    end

    defp extract_alliance_id(_), do: nil

    defp extract_alliance_name(char_data) when is_map(char_data) do
      char_data["alliance_name"] || char_data[:alliance_name]
    end

    defp extract_alliance_name(_), do: nil
  end

  code_interface do
    define(:get, action: :read)
    define(:create, action: :create)
    define(:update, action: :update)
    define(:destroy, action: :destroy)
    define(:sync_from_cache, action: :sync_from_cache)
  end
end
