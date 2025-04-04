defmodule WandererNotifier.Resources.TrackedCharacter do
  @moduledoc """
  Ash resource representing a tracked character.
  Uses Postgres as the data layer for persistence.
  """
  require Logger

  alias Ecto.Adapters.SQL
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.Repo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail

  use Ash.Resource,
    domain: Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  require Ash.Query

  postgres do
    table("tracked_characters")
    repo(Repo)
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
    has_many(:killmails, Killmail,
      destination_attribute: :related_character_id,
      validate_destination_attribute?: false
    )
  end

  aggregates do
  end

  calculations do
  end

  actions do
    defaults([:read, :destroy])

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

    # Define update action with explicit accepted attributes to fix the NoSuchInput error
    update :update do
      primary?(true)

      # This action doesn't need to be atomic since we're using a change function
      require_atomic?(false)

      # Explicitly list all fields that can be updated - this is critical to avoid NoSuchInput errors
      accept([
        :character_name,
        :corporation_id,
        :corporation_name,
        :alliance_id,
        :alliance_name
      ])

      # Add a change function to update the timestamps
      change(fn changeset, _context ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        Ash.Changeset.force_change_attribute(changeset, :updated_at, now)
      end)
    end

    # Add sync_from_cache as a custom action
    action :sync_from_cache, :map do
      run(fn _, _ ->
        # Check if database operations are enabled
        if database_enabled?() do
          # Get the current cached characters using the Cache Helper
          require Logger

          # Get characters from the map:characters cache
          cached_characters = CacheRepo.get("map:characters") || []

          AppLogger.persistence_info(
            "Syncing characters from tracking system",
            character_count: length(cached_characters)
          )

          # Debug: Log the format of the first few characters in the cache
          if length(cached_characters) > 0 do
            sample = Enum.take(cached_characters, min(3, length(cached_characters)))

            AppLogger.persistence_debug("Sample characters from cache",
              sample: inspect(sample)
            )
          end

          # Process each tracked character
          results =
            Enum.map(cached_characters, fn char_data ->
              # Extract character ID directly instead of using the helper function
              character_id =
                case extract_character_id_from_data(char_data) do
                  nil ->
                    AppLogger.persistence_warn("Unable to extract character ID",
                      character_data: inspect(char_data)
                    )

                    nil

                  id_str ->
                    # Convert string ID to integer
                    case Integer.parse(to_string(id_str)) do
                      {int_id, ""} ->
                        # Log the parsed integer ID
                        AppLogger.persistence_debug("Parsed character ID", id: int_id)
                        int_id

                      _ ->
                        AppLogger.persistence_warn("Invalid character ID format",
                          id: inspect(id_str)
                        )

                        nil
                    end
                end

              # Skip invalid character IDs
              if is_nil(character_id) do
                AppLogger.persistence_warn("Skipping character with invalid ID",
                  character_data: inspect(char_data)
                )

                {:error, :invalid_character_id}
              else
                # Extract character name if available
                character_name = extract_character_name(char_data)

                # Log character details for debugging
                AppLogger.persistence_debug(
                  "Processing character",
                  character_id: character_id,
                  character_name: character_name
                )

                # Check if character already exists in the Ash resource using string comparison
                str_char_id = to_string(character_id)

                # Use the read function to look for existing character
                AppLogger.persistence_debug(
                  "Looking for existing character in database",
                  character_id: character_id
                )

                # Use Ash.Query to build the query with a filter - don't pass filter directly to read
                read_result =
                  __MODULE__
                  |> Ash.Query.filter(character_id: character_id)
                  |> Api.read()

                AppLogger.persistence_debug("Read result", result: inspect(read_result))

                case read_result do
                  {:ok, [existing | _]} ->
                    # Character exists, update if needed
                    AppLogger.persistence_debug(
                      "Found existing character",
                      character_id: character_id,
                      character_name: existing.character_name
                    )

                    changes = %{}

                    # Update name if it's different and not nil
                    changes =
                      if character_name && character_name != existing.character_name do
                        AppLogger.persistence_debug(
                          "Updating character name",
                          character_id: character_id,
                          old_name: existing.character_name,
                          new_name: character_name
                        )

                        Map.put(changes, :character_name, character_name)
                      else
                        changes
                      end

                    # Apply updates if needed
                    if map_size(changes) > 0 do
                      AppLogger.persistence_info(
                        "Updating character",
                        character_id: character_id,
                        character_name: character_name,
                        changes: map_size(changes)
                      )

                      update_result =
                        Api.update(__MODULE__, existing.id, changes)

                      AppLogger.persistence_debug(
                        "Update result",
                        result: inspect(update_result)
                      )

                      case update_result do
                        {:ok, _updated} -> {:ok, :updated}
                        {:error, reason} -> {:error, reason}
                      end
                    else
                      AppLogger.persistence_debug(
                        "No changes needed for character",
                        character_id: character_id
                      )

                      {:ok, :unchanged}
                    end

                  {:ok, []} ->
                    # Character doesn't exist, create it
                    AppLogger.persistence_info(
                      "Creating new character",
                      character_id: character_id,
                      character_name: character_name || "Unknown"
                    )

                    create_attrs = %{
                      character_id: character_id,
                      character_name: character_name || "Unknown Character",
                      corporation_id: extract_corporation_id(char_data),
                      corporation_name: extract_corporation_name(char_data),
                      alliance_id: extract_alliance_id(char_data),
                      alliance_name: extract_alliance_name(char_data)
                    }

                    AppLogger.persistence_debug(
                      "Create attributes",
                      attributes: inspect(create_attrs)
                    )

                    create_result =
                      Api.create(__MODULE__, create_attrs)

                    AppLogger.persistence_debug(
                      "Create result",
                      result: inspect(create_result)
                    )

                    create_result

                  {:error, reason} ->
                    # Error querying
                    AppLogger.persistence_error(
                      "Error checking for existing character",
                      character_id: character_id,
                      error: inspect(reason)
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

            AppLogger.persistence_error("Character sync errors",
              error_sample: inspect(error_sample)
            )
          end

          AppLogger.persistence_info(
            "Sync complete",
            successful: successes,
            failed: failures
          )

          # After sync, verify the count in the database
          db_count_result =
            __MODULE__
            |> Api.read()

          db_count =
            case db_count_result do
              {:ok, chars} -> length(chars)
              _ -> 0
            end

          AppLogger.persistence_info("Database character count", count: db_count)

          {:ok, %{successes: successes, failures: failures, db_count: db_count}}
        else
          AppLogger.persistence_info(
            "[TrackedCharacter] Database operations disabled, skipping cache sync"
          )

          # Return a safe empty result
          {:ok, %{successes: 0, failures: 0, db_count: 0, skipped: true}}
        end
      end)
    end

    # Add a new action to sync directly from character structs
    # This enables immediate persistence without relying on cache
    action :sync_from_characters, :map do
      argument(:characters, :term)

      run(fn %{arguments: %{characters: characters}} = args, _ ->
        require Logger

        # Better debug logging for argument structure
        AppLogger.persistence_debug(
          "[TrackedCharacter] Received arguments for sync_from_characters:",
          arg_keys: Map.keys(args),
          characters_type: characters |> inspect() |> String.slice(0, 30)
        )

        # Early check if database operations are enabled before any database access
        # This prevents any attempt to access the database when disabled
        if database_enabled?() do
          # Add debug logging to inspect the incoming data
          AppLogger.persistence_debug(
            "[TrackedCharacter] Received characters for sync",
            count: if(is_list(characters), do: length(characters), else: 0),
            sample:
              if(is_list(characters) && length(characters) > 0,
                do: inspect(Enum.at(characters, 0), limit: 100),
                else: "nil"
              )
          )

          # Early return if characters is nil or empty
          if is_nil(characters) || (is_list(characters) && characters == []) do
            AppLogger.persistence_debug("[TrackedCharacter] No characters to sync to database")
            return_empty_stats()
          else
            # Continue with normal sync logic for non-empty characters
            try do
              # Ensure we have a list
              characters_list = ensure_list(characters)

              AppLogger.persistence_debug(
                "[TrackedCharacter] Syncing characters directly to database",
                character_count: length(characters_list)
              )

              # Initialize stats counters
              stats = %{
                total: length(characters_list),
                created: 0,
                updated: 0,
                unchanged: 0,
                errors: 0
              }

              # Process each character and track results
              results =
                Enum.reduce(characters_list, {stats, []}, fn character,
                                                             {current_stats, current_errors} ->
                  # Add character type info for debugging
                  AppLogger.persistence_debug(
                    "[TrackedCharacter] Processing character",
                    type: inspect(character.__struct__),
                    struct?: is_struct(character),
                    map?: is_map(character)
                  )

                  case sync_single_character(character) do
                    {:ok, :created} ->
                      {Map.update!(current_stats, :created, &(&1 + 1)), current_errors}

                    {:ok, :updated} ->
                      {Map.update!(current_stats, :updated, &(&1 + 1)), current_errors}

                    {:ok, :unchanged} ->
                      {Map.update!(current_stats, :unchanged, &(&1 + 1)), current_errors}

                    {:error, reason} ->
                      error_info = %{
                        character: inspect(character),
                        reason: reason
                      }

                      {Map.update!(current_stats, :errors, &(&1 + 1)),
                       [error_info | current_errors]}
                  end
                end)

              {final_stats, errors} = results

              if length(errors) > 0 do
                AppLogger.persistence_warning(
                  "[TrackedCharacter] Sync had errors",
                  error_count: length(errors),
                  errors: inspect(errors)
                )
              end

              # Return the results
              {:ok, %{stats: final_stats, errors: errors}}
            rescue
              e ->
                # Log the full error details for better debugging
                AppLogger.persistence_error(
                  "[TrackedCharacter] Exception in character sync: #{Exception.message(e)}"
                )

                AppLogger.persistence_error("[TrackedCharacter] #{Exception.format_stacktrace()}")
                {:error, Exception.message(e)}
            end
          end
        else
          # When database operations are disabled, return empty stats without any database access
          AppLogger.persistence_info(
            "[TrackedCharacter] Database operations disabled, skipping character sync to database"
          )

          # Return safe empty stats without touching the database
          return_empty_stats()
        end
      end)
    end

    # Helper functions for extracting character information
    defp extract_character_id_from_data(char_data) do
      # Try extracting in order of preference
      character_id =
        extract_from_struct(char_data) ||
          extract_from_map(char_data) ||
          extract_from_primitive(char_data)

      character_id
    end

    # Extract character ID from struct
    defp extract_from_struct(char_data) do
      if is_struct(char_data) && Map.has_key?(char_data, :character_id) do
        id = char_data.character_id
        # Only return valid numeric IDs
        if is_integer(id) || (is_binary(id) && numeric_string?(id)) do
          to_string(id)
        else
          AppLogger.persistence_warn("Invalid character_id in struct", id: id)
          nil
        end
      end
    end

    # Extract character ID from map
    defp extract_from_map(char_data) when not is_map(char_data), do: nil

    defp extract_from_map(char_data) do
      # Try multiple possible key formats for character_id, with consistent type handling
      char_id = char_data["character_id"] || char_data[:character_id]

      # Early return for nil values
      if is_nil(char_id) do
        nil
      else
        # Process character ID based on type
        process_character_id_from_map(char_id)
      end
    end

    # Process character ID from map based on its type
    defp process_character_id_from_map(id) when is_integer(id), do: to_string(id)

    defp process_character_id_from_map(id) when is_binary(id) do
      # Validate that it's a numeric string before accepting it
      if numeric_string?(id) do
        # Valid integer string
        id
      else
        AppLogger.persistence_warn("Invalid character ID format (non-numeric)",
          id: id
        )

        nil
      end
    end

    defp process_character_id_from_map(_), do: nil

    # Helper to check if a string is numeric (contains only digits)
    defp numeric_string?(str) when is_binary(str) do
      case Integer.parse(str) do
        {_, ""} -> true
        _ -> false
      end
    end

    defp numeric_string?(_), do: false

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

    # Extract character ID from primitive value
    defp extract_from_primitive(char_data) when is_integer(char_data), do: to_string(char_data)

    defp extract_from_primitive(char_data) when is_binary(char_data) do
      # Validate that it's a numeric string
      if numeric_string?(char_data) do
        # Valid integer string
        char_data
      else
        AppLogger.persistence_debug("Non-numeric string ID rejected", id: char_data)
        # Not a valid integer string
        nil
      end
    end

    defp extract_from_primitive(_), do: nil
  end

  code_interface do
    define(:get, action: :read)
    define(:create, action: :create)
    define(:update, action: :update)
    define(:destroy, action: :destroy)
    define(:sync_from_cache, action: :sync_from_cache)
    define(:sync_from_characters, action: :sync_from_characters)
  end

  @doc """
  Verifies database permissions by attempting a simple write/read operation.
  Returns :ok if successful or {:error, reason} if there's an issue.
  """
  def verify_database_permissions do
    require Logger

    AppLogger.persistence_info(
      "[TrackedCharacter] Verifying database permissions and table existence..."
    )

    # First check if the table exists by querying the database directly
    try do
      query = "SELECT EXISTS (
                 SELECT FROM pg_tables
                 WHERE schemaname = 'public'
                 AND tablename = 'tracked_characters'
               )"

      case SQL.query(Repo, query) do
        {:ok, %{rows: [[true]]}} ->
          AppLogger.persistence_info("[TrackedCharacter] tracked_characters table exists")

          # Continue with permission check
          check_read_write_permissions()

        {:ok, %{rows: [[false]]}} ->
          AppLogger.persistence_error(
            "[TrackedCharacter] tracked_characters table does not exist! Run migrations."
          )

          {:error, :table_not_exists}

        {:error, error} ->
          AppLogger.persistence_error(
            "[TrackedCharacter] Failed to check table existence: #{inspect(error)}"
          )

          {:error, {:table_check_failed, error}}
      end
    rescue
      e ->
        AppLogger.persistence_error(
          "[TrackedCharacter] Exception while checking table: #{Exception.message(e)}"
        )

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
           {:create, Api.create(__MODULE__, test_attrs)},
         _ <- AppLogger.persistence_info("[TrackedCharacter] Successfully created test record"),
         {:read, {:ok, [_fetched_record | _]}} <- {:read, read_test_record(test_id)},
         _ <- AppLogger.persistence_info("[TrackedCharacter] Successfully read test record"),
         {:delete, delete_result} <- {:delete, Api.destroy(__MODULE__, record.id)},
         _ <-
           AppLogger.persistence_info(
             "[TrackedCharacter] Delete result: #{inspect(delete_result)}"
           ),
         {:ok, _} <- handle_delete_result(delete_result),
         _ <- AppLogger.persistence_info("[TrackedCharacter] Successfully deleted test record") do
      # All operations successful
      :ok
    else
      # Handle create failures
      {:create, {:error, create_error}} ->
        AppLogger.persistence_error(
          "[TrackedCharacter] Failed to create test record: #{inspect(create_error)}"
        )

        {:error, {:create_failed, create_error}}

      # Handle read failures
      {:read, {:ok, []}} ->
        AppLogger.persistence_error("[TrackedCharacter] Created test record but couldn't find it")
        {:error, :record_not_found}

      {:read, {:error, read_error}} ->
        AppLogger.persistence_error(
          "[TrackedCharacter] Failed to read test record: #{inspect(read_error)}"
        )

        {:error, {:read_failed, read_error}}

      # Handle delete failures
      {:delete, {:error, delete_error}} ->
        AppLogger.persistence_error(
          "[TrackedCharacter] Failed to delete test record: #{inspect(delete_error)}"
        )

        {:error, {:delete_failed, delete_error}}

      {:error, reason} ->
        AppLogger.persistence_error(
          "[TrackedCharacter] Delete operation failed: #{inspect(reason)}"
        )

        {:error, {:delete_failed, reason}}
    end
  end

  # Helper to handle delete results
  defp handle_delete_result({:ok, _} = result), do: result
  defp handle_delete_result({:delete, :ok}), do: {:ok, :deleted}

  defp handle_delete_result(other) do
    AppLogger.persistence_error("[TrackedCharacter] Unexpected delete result: #{inspect(other)}")
    {:error, :invalid_delete_result}
  end

  # Helper to read a test record by character_id
  defp read_test_record(test_id) do
    query = Ash.Query.filter(__MODULE__, character_id: test_id)
    Api.read(query)
  end

  @doc """
  Force syncs characters by clearing all tracked characters from the database and repopulating from cache.
  This is a destructive operation that will delete all existing tracked characters first.
  """
  def force_sync_from_cache do
    require Logger

    AppLogger.persistence_warn(
      "[TrackedCharacter] Starting forced sync from cache (destructive operation)"
    )

    # Get current tracked characters from database
    with {:ok, existing_chars} <- Api.read(__MODULE__),
         _ <-
           AppLogger.persistence_info(
             "[TrackedCharacter] Found #{length(existing_chars)} existing characters in database"
           ),
         {:ok, _} <- delete_existing_characters(existing_chars),
         {:ok, stats} <- sync_characters_from_cache() do
      {:ok, stats}
    else
      {:error, reason} = error ->
        log_sync_error(reason)
        error
    end
  end

  # Handle database permission failures
  defp log_sync_error({:db_permissions, reason}) do
    AppLogger.persistence_error(
      "[TrackedCharacter] Cannot proceed with sync - database permission check failed: #{inspect(reason)}"
    )
  end

  defp log_sync_error(reason) do
    AppLogger.persistence_error("[TrackedCharacter] Force sync failed: #{inspect(reason)}")
  end

  # Process a batch of character deletions
  defp process_deletion_batch(batch) do
    Enum.map(batch, fn char ->
      case Api.destroy(__MODULE__, char.id) do
        {:ok, _} ->
          {:ok, char.id}

        {:error, reason} ->
          AppLogger.persistence_error(
            "[TrackedCharacter] Failed to delete character: #{inspect(reason)}",
            character_id: char.character_id
          )

          {:error, reason}
      end
    end)
  end

  # Count successful deletions and log failures
  defp process_deletion_results(deletion_results, total_count) do
    successes = Enum.count(deletion_results, &match?({:ok, _}, &1))

    failures = Enum.reject(deletion_results, &match?({:ok, _}, &1))

    if length(failures) > 0 do
      AppLogger.persistence_error(
        "[TrackedCharacter] Some characters failed to delete",
        failures: inspect(failures)
      )
    end

    AppLogger.persistence_info(
      "[TrackedCharacter] Deleted #{successes}/#{total_count} characters from database"
    )

    {successes, total_count}
  end

  # Delete existing characters in batches
  defp delete_existing_characters(existing_chars) do
    deletion_results =
      existing_chars
      |> Enum.chunk_every(50)
      |> Enum.map(&process_deletion_batch/1)
      |> List.flatten()

    {successes, total} = process_deletion_results(deletion_results, length(existing_chars))

    if successes == total do
      {:ok, successes}
    else
      {:error, "Failed to delete all characters"}
    end
  end

  # Process characters and collect stats
  defp process_characters(cached_characters) do
    Enum.reduce(cached_characters, {0, 0, []}, fn char_data, {succ, fail, errs} ->
      case process_single_character(char_data) do
        {:ok, _} -> {succ + 1, fail, errs}
        {:error, reason} -> {succ, fail + 1, [reason | errs]}
      end
    end)
  end

  # Format sync results into stats map
  defp format_sync_stats(successes, failures, errors, total) do
    {:ok,
     %{
       stats: %{
         total: total,
         created: successes,
         updated: 0,
         unchanged: 0,
         errors: failures
       },
       errors: errors
     }}
  end

  # Sync characters from cache to database
  defp sync_characters_from_cache do
    require Logger

    # Get characters from cache
    cached_characters = CacheRepo.get("map:characters") || []

    AppLogger.persistence_info("Syncing characters from tracking system",
      character_count: length(cached_characters)
    )

    if Enum.empty?(cached_characters) do
      AppLogger.persistence_warn("No characters found in cache, nothing to sync")
      return_empty_stats()
    else
      # For debugging, log a sample of characters
      log_character_sample(cached_characters)

      # Process characters and collect stats
      {successes, failures, errors} = process_characters(cached_characters)
      format_sync_stats(successes, failures, errors, length(cached_characters))
    end
  rescue
    e ->
      AppLogger.persistence_error("Error syncing characters",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      return_empty_stats()
  end

  # Log a sample of characters for debugging
  defp log_character_sample(cached_characters) do
    sample = Enum.take(cached_characters, min(3, length(cached_characters)))

    AppLogger.persistence_debug("Sample characters from cache",
      sample: inspect(sample)
    )
  end

  # Process a single character record
  defp process_single_character(char_data) do
    # Extract character ID and validate it
    raw_id = extract_character_id_from_data(char_data)

    if is_nil(raw_id) do
      AppLogger.persistence_warn("Unable to extract character ID",
        character_data: inspect(char_data)
      )

      {:error, "Invalid character ID"}
    else
      # Try to convert to integer
      character_id = parse_character_id_strict(raw_id)

      if is_nil(character_id) do
        # Invalid ID format (non-numeric)
        AppLogger.persistence_error(
          "[TrackedCharacter] Invalid character ID format: #{inspect(raw_id)}"
        )

        {:error, "Invalid character ID format - expected numeric ID"}
      else
        # Valid numeric ID
        # Extract character information
        character_info = extract_character_info(char_data, character_id)
        upsert_character(character_id, character_info)
      end
    end
  end

  # Parse and validate character ID
  defp parse_character_id_strict(nil), do: nil
  defp parse_character_id_strict(id) when is_integer(id), do: id

  defp parse_character_id_strict(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} ->
        int_id

      _ ->
        AppLogger.persistence_error(
          "[TrackedCharacter] Invalid character ID format - expected numeric ID, got: #{inspect(id)}"
        )

        nil
    end
  end

  defp parse_character_id_strict(_), do: nil

  # Extract all character information from the data
  defp extract_character_info(char_data, character_id) do
    %{
      character_id: character_id,
      character_name: extract_character_name(char_data),
      corporation_id: extract_corporation_id(char_data),
      corporation_name: extract_corporation_name(char_data),
      alliance_id: extract_alliance_id(char_data),
      alliance_name: extract_alliance_name(char_data)
    }
  end

  # Upsert (create or update) a character record
  defp upsert_character(character_id, character_info) do
    # Log character details
    AppLogger.persistence_debug("Processing character",
      character_id: character_id,
      character_name: character_info.character_name
    )

    # Look for existing character
    AppLogger.persistence_debug("Looking for existing character in database",
      character_id: character_id
    )

    read_result =
      __MODULE__
      |> Ash.Query.filter(character_id == ^character_id)
      |> Api.read()

    AppLogger.persistence_debug("Read result", result: inspect(read_result))

    # Process based on whether character exists
    case read_result do
      {:ok, [existing | _]} ->
        update_existing_character(existing, character_info)

      {:ok, []} ->
        # First, standardize the character data and extract ID
        standardized_data = standardize_character_data(character_info)
        character_id = standardized_data[:character_id]

        if is_nil(character_id) do
          {:error, "Invalid character ID"}
        else
          create_new_character(character_id, standardized_data)
        end

      {:error, error} ->
        AppLogger.persistence_error("Error reading character",
          character_id: character_id,
          error: inspect(error)
        )

        {:error, "Database read error: #{inspect(error)}"}
    end
  end

  # Helper function to sync a single character to the database
  defp sync_single_character(character) do
    # First, ensure we have a standardized format to work with
    character_data = standardize_character_data(character)

    # Extract ID in a way that works for various formats
    character_id = character_data[:character_id]

    # Validate character ID
    if is_nil(character_id) do
      AppLogger.persistence_error(
        "[TrackedCharacter] Invalid or missing character ID: #{inspect(character)}"
      )

      return_error(:invalid_character_id)
    else
      process_character_with_valid_id(character_id, character_data)
    end
  end

  # Standardize character data to a consistent map format with atom keys
  defp standardize_character_data(character) do
    character_format = determine_character_format(character)
    process_character_by_format(character_format, character)
  end

  # Determine what format the character data is in
  defp determine_character_format(character) do
    cond do
      is_struct(character, Character) -> :character_struct
      match?({:ok, _}, character) -> :ok_tuple
      is_map(character) && has_string_keys?(character) -> :string_map
      is_map(character) && map_size(character) > 0 -> :atom_map
      true -> :unknown
    end
  end

  # Check if a map has string keys for character data
  defp has_string_keys?(map) do
    map_size(map) > 0 && (Map.has_key?(map, "character_id") || Map.has_key?(map, "name"))
  end

  # Process character data based on its format
  defp process_character_by_format(:character_struct, character) do
    standardize_character_struct(character)
  end

  defp process_character_by_format(:ok_tuple, {:ok, char}) do
    standardize_character_data(char)
  end

  defp process_character_by_format(:string_map, character) do
    standardize_map_with_string_keys(character)
  end

  defp process_character_by_format(:atom_map, character) do
    standardize_map_with_atom_keys(character)
  end

  defp process_character_by_format(:unknown, character) do
    AppLogger.persistence_error(
      "[TrackedCharacter] Unexpected character data format: #{inspect(character)}"
    )

    %{}
  end

  # Handle Character struct specifically
  defp standardize_character_struct(character) do
    # Try to convert character_id to integer or fail
    character_id = parse_character_id_strict(character.character_id)

    %{
      character_id: character_id,
      name: character.name,
      corporation_id: character.corporation_id,
      # Map ticker to name for database compatibility
      corporation_name: character.corporation_ticker,
      alliance_id: character.alliance_id,
      # Map ticker to name for database compatibility
      alliance_name: character.alliance_ticker
    }
  end

  # Handle maps with string keys
  defp standardize_map_with_string_keys(character) do
    character_id = parse_character_id_strict(extract_value(character, ["character_id"]))

    %{
      character_id: character_id,
      name: extract_value(character, ["name", "character_name"]),
      corporation_id: extract_value(character, ["corporation_id"]),
      # Map ticker to name for database compatibility
      corporation_name: extract_value(character, ["corporation_ticker", "corporation_name"]),
      alliance_id: extract_value(character, ["alliance_id"]),
      # Map ticker to name for database compatibility
      alliance_name: extract_value(character, ["alliance_ticker", "alliance_name"])
    }
  end

  # Handle maps with atom keys
  defp standardize_map_with_atom_keys(character) do
    character_id =
      parse_character_id_strict(extract_value(character, [:character_id, "character_id"]))

    %{
      character_id: character_id,
      name: extract_value(character, [:name, :character_name, "name", "character_name"]),
      corporation_id: extract_value(character, [:corporation_id, "corporation_id"]),
      # Map ticker to name for database compatibility
      corporation_name:
        extract_value(character, [
          :corporation_name,
          :corporation_ticker,
          "corporation_name",
          "corporation_ticker"
        ]),
      alliance_id: extract_value(character, [:alliance_id, "alliance_id"]),
      # Map ticker to name for database compatibility
      alliance_name:
        extract_value(character, [
          :alliance_name,
          :alliance_ticker,
          "alliance_name",
          "alliance_ticker"
        ])
    }
  end

  # Extract a value from a map trying multiple keys
  defp extract_value(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key)
    end)
  end

  # Process a character that has a valid ID
  defp process_character_with_valid_id(character_id, character_data) do
    # Get character name from standardized data
    character_name = character_data[:name]

    # Skip if we don't have a valid name
    if is_nil(character_name) or character_name == "" do
      AppLogger.persistence_warning(
        "[TrackedCharacter] Missing character name for ID #{character_id}, skipping"
      )

      return_error(:missing_character_name)
    else
      # Check if character already exists in database
      find_and_process_character(character_id, character_data)
    end
  end

  # Find and process the character in the database
  defp find_and_process_character(character_id, character_data) do
    case find_by_character_id(character_id) do
      {:ok, []} ->
        # Character doesn't exist, create new record
        create_new_character(character_id, character_data)

      {:ok, [existing | _]} ->
        # Character exists, update if needed
        update_existing_character(existing, character_data)

      {:error, reason} ->
        # Error checking database
        AppLogger.persistence_error(
          "[TrackedCharacter] Error checking for existing character: #{inspect(reason)}"
        )

        return_error(reason)
    end
  end

  # Helper for standardized error returns
  defp return_error(reason) do
    {:error, reason}
  end

  # Helper function to find a character by ID
  defp find_by_character_id(character_id) do
    if database_enabled?() do
      query = Ash.Query.filter(__MODULE__, character_id == ^character_id)
      Api.read(query)
    else
      # Database operations are disabled, return empty result
      AppLogger.persistence_debug(
        "[TrackedCharacter] Database operations disabled, skipping character lookup",
        character_id: character_id
      )

      {:ok, []}
    end
  end

  # Helper function to create a new character record
  defp create_new_character(character_id, character_data) do
    if database_enabled?() do
      character_name = character_data[:name] || "Unknown Character"

      AppLogger.persistence_info(
        "[TrackedCharacter] Creating new character record: #{character_name} (#{character_id})"
      )

      # Prepare attributes for creation
      attributes = %{
        character_id: character_id,
        character_name: character_name,
        corporation_id: character_data[:corporation_id],
        corporation_name: character_data[:corporation_name],
        alliance_id: character_data[:alliance_id],
        alliance_name: character_data[:alliance_name]
      }

      AppLogger.persistence_debug(
        "Create attributes",
        attributes: inspect(attributes)
      )

      # Create the character record
      case Api.create(__MODULE__, attributes) do
        {:ok, record} ->
          # Update cache for this character
          update_character_cache(record)

          # Update the tracked characters list
          update_tracked_characters_cache()

          {:ok, :created}

        {:error, reason} ->
          AppLogger.persistence_error(
            "[TrackedCharacter] Failed to create character #{character_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      AppLogger.persistence_info(
        "[TrackedCharacter] Database operations disabled, skipping character creation",
        character_id: character_id
      )

      # Return as if created successfully
      {:ok, :created}
    end
  end

  # Update an existing character record
  defp update_existing_character(existing, character_data) do
    if database_enabled?() do
      # Character exists, update if needed

      # Build changes map by comparing fields and adding only what's different
      changes = build_character_changes(existing, character_data)

      # Apply updates if needed
      if map_size(changes) > 0 do
        apply_character_updates(existing, changes, character_data[:character_id])
      else
        {:ok, :unchanged}
      end
    else
      AppLogger.persistence_info(
        "[TrackedCharacter] Database operations disabled, skipping character update",
        character_id: character_data[:character_id]
      )

      # Return as if updated successfully
      {:ok, :unchanged}
    end
  end

  # Helper to build a map of changes by comparing fields
  defp build_character_changes(existing, character_data) do
    changes = %{}

    # Update name if provided and different
    changes =
      maybe_add_change(changes, :character_name, character_data[:name], existing.character_name)

    # Update corp ID if provided and different
    changes =
      maybe_add_change(
        changes,
        :corporation_id,
        character_data[:corporation_id],
        existing.corporation_id
      )

    # Update corp name
    changes =
      maybe_add_change(
        changes,
        :corporation_name,
        character_data[:corporation_name],
        existing.corporation_name
      )

    # Update alliance ID
    changes =
      maybe_add_change(changes, :alliance_id, character_data[:alliance_id], existing.alliance_id)

    # Update alliance name
    changes =
      maybe_add_change(
        changes,
        :alliance_name,
        character_data[:alliance_name],
        existing.alliance_name
      )

    changes
  end

  # Helper to add a field to changes map if it's different
  defp maybe_add_change(changes, field, new_value, existing_value) do
    if new_value && new_value != existing_value do
      Map.put(changes, field, new_value)
    else
      changes
    end
  end

  # Helper to apply updates and handle the result
  defp apply_character_updates(existing, changes, character_id) do
    if database_enabled?() do
      AppLogger.persistence_info("Updating character",
        character_id: character_id,
        changes: map_size(changes),
        change_fields: Map.keys(changes)
      )

      update_result =
        Api.update(__MODULE__, existing.id, changes)

      case update_result do
        {:ok, _updated} -> {:ok, :updated}
        {:error, reason} -> {:error, reason}
      end
    else
      AppLogger.persistence_info(
        "[TrackedCharacter] Database operations disabled, skipping character update",
        character_id: character_id
      )

      {:ok, :unchanged}
    end
  end

  # Helper functions to update cache after database operations

  # Update the cache for a specific character
  defp update_character_cache(character) do
    character_id = to_string(character.character_id)
    cache_key = CacheKeys.character(character_id)

    # Convert to format expected by the cache
    cache_character = %{
      "character_id" => character_id,
      "name" => character.character_name,
      "corporation_id" => character.corporation_id,
      "corporation_ticker" => character.corporation_name,
      "alliance_id" => character.alliance_id,
      "alliance_ticker" => character.alliance_name,
      "tracked" => true
    }

    # Update the cache
    CacheRepo.update_after_db_write(
      cache_key,
      cache_character,
      Timings.characters_cache_ttl()
    )

    # Also ensure this character is marked as tracked
    CacheRepo.update_after_db_write(
      "tracked:character:#{character_id}",
      true,
      Timings.characters_cache_ttl()
    )
  end

  # Update the global tracked characters list
  defp update_tracked_characters_cache do
    if database_enabled?() do
      # Function to read all tracked characters from the database
      db_read_fun = fn -> fetch_and_format_characters() end

      # Sync the cache with database
      CacheRepo.sync_with_db(
        "map:characters",
        db_read_fun,
        Timings.characters_cache_ttl()
      )
    else
      AppLogger.persistence_debug(
        "[TrackedCharacter] Database operations disabled, skipping cache update"
      )

      {:ok, []}
    end
  end

  # Fetch characters from database and format them for cache storage
  defp fetch_and_format_characters do
    if database_enabled?() do
      case list_all() do
        {:ok, characters} ->
          # Convert to format expected by the cache
          cache_characters = Enum.map(characters, &format_character_for_cache/1)
          {:ok, cache_characters}

        error ->
          error
      end
    else
      AppLogger.persistence_debug(
        "[TrackedCharacter] Database operations disabled, returning empty character list"
      )

      {:ok, []}
    end
  end

  # Format a database character record for cache storage
  defp format_character_for_cache(char) do
    %{
      "character_id" => to_string(char.character_id),
      "name" => char.character_name,
      "corporation_id" => char.corporation_id,
      "corporation_ticker" => char.corporation_name,
      "alliance_id" => char.alliance_id,
      "alliance_ticker" => char.alliance_name,
      "tracked" => true
    }
  end

  @doc """
  Lists all tracked characters from the database, with safety checks for database availability.
  Returns {:ok, characters} if successful or {:error, reason} if failed.
  When database is disabled, returns {:ok, []} for safe consumption.
  """
  def list_all do
    read_safely()
  end

  # Helper function to return empty stats object
  defp return_empty_stats do
    {:ok, %{stats: %{total: 0, created: 0, updated: 0, unchanged: 0, errors: 0}, errors: []}}
  end

  # Helper function to ensure input is a list
  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list({:error, _}), do: []
  defp ensure_list(_other), do: []

  @doc """
  Checks if database operations are enabled based on feature flags.
  Returns true if either map_charts or kill_charts is enabled.
  """
  def database_enabled? do
    # Use the Config module functions to determine if features are enabled
    map_charts_enabled = Config.map_charts_enabled?()
    kill_charts_enabled = Config.kill_charts_enabled?()

    # Combined result (either feature enables database)
    map_charts_enabled || kill_charts_enabled
  end

  @doc """
  Safely reads characters from the database, with a fallback when database is disabled.
  """
  def read_safely(query \\ nil) do
    if database_enabled?() do
      # Database is enabled, proceed with normal read
      case query do
        nil -> Api.read(__MODULE__)
        query -> Api.read(query)
      end
    else
      # Database is disabled, return empty list
      AppLogger.persistence_debug("Database operations disabled, skipping character read")
      {:ok, []}
    end
  end

  @doc """
  Called when a file is changed and code is reloaded in development.
  This replaces the functionality in DevCallbacks.
  """
  def reload(modules) when is_list(modules) do
    AppLogger.startup_info("Reloaded modules: #{inspect(modules)}")
    :ok
  end

  def reload({_module, :reload}) do
    AppLogger.startup_info("Module reloaded")
    :ok
  end
end
