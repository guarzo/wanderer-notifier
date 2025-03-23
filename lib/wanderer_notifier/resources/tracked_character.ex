defmodule WandererNotifier.Resources.TrackedCharacter do
  @moduledoc """
  Ash resource representing a tracked character.
  Uses Postgres as the data layer for persistence.
  """
  require Logger

  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  require Ash.Query

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

    # Add timestamps but don't add explicit attributes for them
    timestamps()
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
    defaults([:read, :update, :destroy])

    # Define create action with explicit accepted attributes
    create :create do
      primary?(true)

      # Specify which attributes we accept in the create action
      accept([
        :character_id,
        :character_name,
        :corporation_id,
        :corporation_name,
        :alliance_id,
        :alliance_name
      ])

      # Add a change function to set the timestamps
      change(fn changeset, _context ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        changeset
        |> Ash.Changeset.force_change_attribute(:inserted_at, now)
        |> Ash.Changeset.force_change_attribute(:updated_at, now)
      end)
    end

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

        # Debug: Log the format of the first few characters in the cache
        if length(cached_characters) > 0 do
          sample = Enum.take(cached_characters, min(3, length(cached_characters)))

          Logger.info(
            "[TrackedCharacter] DEBUG: Sample characters from cache: #{inspect(sample)}"
          )
        end

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
                      # Log the parsed integer ID
                      Logger.debug("[TrackedCharacter] DEBUG: Parsed character ID: #{int_id}")
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
              Logger.debug(
                "[TrackedCharacter] DEBUG: Looking for existing character with ID #{character_id} in database"
              )

              # Use Ash.Query to build the query with a filter - don't pass filter directly to read
              read_result =
                __MODULE__
                |> Ash.Query.filter(character_id: character_id)
                |> WandererNotifier.Resources.Api.read()

              Logger.debug("[TrackedCharacter] DEBUG: Read result: #{inspect(read_result)}")

              case read_result do
                {:ok, [existing | _]} ->
                  # Character exists, update if needed
                  Logger.debug(
                    "[TrackedCharacter] DEBUG: Found existing character: #{inspect(existing)}"
                  )

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

                    update_result =
                      WandererNotifier.Resources.Api.update(__MODULE__, existing.id, changes)

                    Logger.debug(
                      "[TrackedCharacter] DEBUG: Update result: #{inspect(update_result)}"
                    )

                    update_result
                  else
                    Logger.debug(
                      "[TrackedCharacter] No changes needed for character #{character_id}"
                    )

                    {:ok, :unchanged}
                  end

                {:ok, []} ->
                  # Character doesn't exist, create it
                  Logger.info(
                    "[TrackedCharacter] Creating new character: #{character_name || "Unknown"} (#{character_id})"
                  )

                  create_attrs = %{
                    character_id: character_id,
                    character_name: character_name || "Unknown Character",
                    corporation_id: extract_corporation_id(char_data),
                    corporation_name: extract_corporation_name(char_data),
                    alliance_id: extract_alliance_id(char_data),
                    alliance_name: extract_alliance_name(char_data)
                  }

                  Logger.debug(
                    "[TrackedCharacter] DEBUG: Create attributes: #{inspect(create_attrs)}"
                  )

                  create_result = WandererNotifier.Resources.Api.create(__MODULE__, create_attrs)

                  Logger.debug(
                    "[TrackedCharacter] DEBUG: Create result: #{inspect(create_result)}"
                  )

                  create_result

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

        # Track specific error reasons
        errors =
          Enum.filter(results, fn
            {:error, _} -> true
            _ -> false
          end)

        if length(errors) > 0 do
          error_sample = Enum.take(errors, min(5, length(errors)))
          Logger.error("[TrackedCharacter] Error samples: #{inspect(error_sample)}")
        end

        Logger.info(
          "[TrackedCharacter] Sync complete: #{successes} successful, #{failures} failed"
        )

        # After sync, verify the count in the database
        db_count_result =
          __MODULE__
          |> WandererNotifier.Resources.Api.read()

        db_count =
          case db_count_result do
            {:ok, chars} -> length(chars)
            _ -> 0
          end

        Logger.info("[TrackedCharacter] After sync, database contains #{db_count} characters")

        {:ok, %{successes: successes, failures: failures, db_count: db_count}}
      end)
    end

    # Helper functions for extracting character information
    defp extract_character_id_from_data(char_data) do
      extract_from_struct(char_data) ||
        extract_from_map(char_data) ||
        extract_from_primitive(char_data)
    end

    # Extract character ID from struct
    defp extract_from_struct(char_data) do
      if is_struct(char_data) && Map.has_key?(char_data, :character_id) do
        to_string(char_data.character_id)
      end
    end

    # Extract character ID from map
    defp extract_from_map(char_data) do
      if is_map(char_data) &&
           (Map.has_key?(char_data, "character_id") || Map.has_key?(char_data, :character_id)) do
        char_id = char_data["character_id"] || char_data[:character_id]
        if char_id, do: to_string(char_id), else: nil
      end
    end

    # Extract character ID from primitive value
    defp extract_from_primitive(char_data) do
      if is_integer(char_data) || is_binary(char_data) do
        to_string(char_data)
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

  @doc """
  Verifies database permissions by attempting a simple write/read operation.
  Returns :ok if successful or {:error, reason} if there's an issue.
  """
  def verify_database_permissions do
    require Logger
    Logger.info("[TrackedCharacter] Verifying database permissions and table existence...")

    # First check if the table exists by querying the database directly
    try do
      query = "SELECT EXISTS (
                 SELECT FROM pg_tables
                 WHERE schemaname = 'public'
                 AND tablename = 'tracked_characters'
               )"

      case Ecto.Adapters.SQL.query(WandererNotifier.Repo, query) do
        {:ok, %{rows: [[true]]}} ->
          Logger.info("[TrackedCharacter] tracked_characters table exists")

          # Continue with permission check
          check_read_write_permissions()

        {:ok, %{rows: [[false]]}} ->
          Logger.error(
            "[TrackedCharacter] tracked_characters table does not exist! Run migrations."
          )

          {:error, :table_not_exists}

        {:error, error} ->
          Logger.error("[TrackedCharacter] Failed to check table existence: #{inspect(error)}")
          {:error, {:table_check_failed, error}}
      end
    rescue
      e ->
        Logger.error("[TrackedCharacter] Exception while checking table: #{Exception.message(e)}")
        {:error, {:exception, Exception.message(e)}}
    end
  end

  # Separate function to check read/write permissions
  defp check_read_write_permissions do
    require Logger

    # Create a test character with an ID unlikely to conflict
    test_id = 999_999_999

    test_attrs = %{
      character_id: test_id,
      character_name: "DB Permission Test Character"
    }

    # Try the full create, read, delete cycle
    with {:create, {:ok, record}} <-
           {:create, WandererNotifier.Resources.Api.create(__MODULE__, test_attrs)},
         _ <- Logger.info("[TrackedCharacter] Successfully created test record"),
         {:read, {:ok, [_fetched_record | _]}} <- {:read, read_test_record(test_id)},
         _ <- Logger.info("[TrackedCharacter] Successfully read test record"),
         {:delete, {:ok, _}} <-
           {:delete, WandererNotifier.Resources.Api.destroy(__MODULE__, record.id)},
         _ <- Logger.info("[TrackedCharacter] Successfully deleted test record") do
      # All operations successful
      :ok
    else
      # Handle create failures
      {:create, {:error, create_error}} ->
        Logger.error("[TrackedCharacter] Failed to create test record: #{inspect(create_error)}")
        {:error, {:create_failed, create_error}}

      # Handle read failures
      {:read, {:ok, []}} ->
        Logger.error("[TrackedCharacter] Created test record but couldn't find it")
        {:error, :record_not_found}

      {:read, {:error, read_error}} ->
        Logger.error("[TrackedCharacter] Failed to read test record: #{inspect(read_error)}")
        {:error, {:read_failed, read_error}}

      # Handle delete failures
      {:delete, {:error, delete_error}} ->
        Logger.error("[TrackedCharacter] Failed to delete test record: #{inspect(delete_error)}")
        {:error, {:delete_failed, delete_error}}
    end
  end

  # Helper to read a test record by character_id
  defp read_test_record(test_id) do
    __MODULE__
    |> Ash.Query.filter(character_id: test_id)
    |> WandererNotifier.Resources.Api.read()
  end

  @doc """
  Force syncs characters by clearing all tracked characters from the database and repopulating from cache.
  This is a destructive operation that will delete all existing tracked characters first.
  """
  def force_sync_from_cache do
    require Logger
    Logger.warning("[TrackedCharacter] Starting forced sync from cache (destructive operation)")

    # First, verify we can write to the database
    with :ok <- verify_database_permissions(),
         {:ok, _deleted_count} <- delete_existing_characters(),
         {:ok, stats} <- sync_characters_from_cache() do
      Logger.info("[TrackedCharacter] Force sync completed: #{inspect(stats)}")
      {:ok, stats}
    else
      {:error, reason} = error ->
        log_sync_error(reason)
        error
    end
  end

  # Handle database permission failures
  defp log_sync_error({:db_permissions, reason}) do
    Logger.error(
      "[TrackedCharacter] Cannot proceed with sync - database permission check failed: #{inspect(reason)}"
    )
  end

  defp log_sync_error(reason) do
    Logger.error("[TrackedCharacter] Force sync failed: #{inspect(reason)}")
  end

  # Delete all existing characters from the database
  defp delete_existing_characters do
    # Get current tracked characters from database
    db_result = __MODULE__ |> WandererNotifier.Resources.Api.read()

    existing_chars =
      case db_result do
        {:ok, chars} -> chars
        _ -> []
      end

    Logger.info(
      "[TrackedCharacter] Found #{length(existing_chars)} existing characters in database"
    )

    # Don't proceed if we got an error reading the characters
    if match?({:error, _}, db_result) do
      {:error, :failed_to_read_existing_characters}
    else
      perform_character_deletion(existing_chars)
    end
  end

  # Perform the actual deletion of characters
  defp perform_character_deletion(existing_chars) do
    # Delete all existing characters - do this in blocks to avoid memory issues
    deletion_results =
      Enum.chunk_every(existing_chars, 50)
      |> Enum.map(fn batch ->
        Enum.map(batch, fn char ->
          WandererNotifier.Resources.Api.destroy(__MODULE__, char.id)
        end)
      end)
      |> List.flatten()

    # Count successful deletions
    deletion_successes =
      Enum.count(deletion_results, fn
        {:ok, _} -> true
        _ -> false
      end)

    Logger.info(
      "[TrackedCharacter] Deleted #{deletion_successes}/#{length(existing_chars)} characters from database"
    )

    {:ok, deletion_successes}
  end

  # Sync characters from cache to database
  defp sync_characters_from_cache do
    # Get characters from cache
    cached_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []
    Logger.info("[TrackedCharacter] Found #{length(cached_characters)} characters in cache")

    # Now perform a clean sync
    case sync_from_cache() do
      {:ok, _stats} = result -> result
      error -> error
    end
  end
end
