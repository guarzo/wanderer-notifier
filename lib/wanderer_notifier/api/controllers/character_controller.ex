defmodule WandererNotifier.Api.Controllers.CharacterController do
  @moduledoc """
  Controller for character-related endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController

  alias WandererNotifier.Api.Character.KillsService
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Get character kills
  get "/kills/:character_id" do
    case KillsService.get_kills_for_character(character_id) do
      {:ok, kills} -> send_success_response(conn, kills)
      {:error, reason} -> send_error_response(conn, 400, reason)
    end
  end

  # Get character kill stats - direct implementation
  get "/stats" do
    AppLogger.api_info("Received request for character kill statistics")

    # Access the data repo directly to ensure we get accurate data
    alias Ecto.Adapters.SQL
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    alias WandererNotifier.Data.Repo

    # Get tracked characters directly from cache
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Log what we got for debugging
    AppLogger.api_info("Retrieved characters from cache",
      count: length(characters),
      sample: Enum.take(characters, 2)
    )

    # Count total killmails with direct SQL
    total_kills =
      case SQL.query(Repo, "SELECT COUNT(*) FROM killmails") do
        {:ok, %{rows: [[count]]}} -> count
        _ -> 0
      end

    # Debug: Inspect database structure
    _sample_query_result =
      case SQL.query(Repo, "SELECT id, esi_data FROM killmails LIMIT 1") do
        {:ok, %{rows: [[id, esi_data]]}} ->
          AppLogger.api_info("Sample killmail structure",
            id: id,
            esi_data_type: inspect(esi_data.__struct__),
            esi_data_sample: inspect(String.slice(esi_data, 0, 200))
          )

          # Also debug attackers structure
          case SQL.query(
                 Repo,
                 "SELECT jsonb_typeof(esi_data->'attackers') as attackers_type FROM killmails LIMIT 1"
               ) do
            {:ok, %{rows: [[type]]}} ->
              AppLogger.api_info("Attackers field type", type: type)

            _ ->
              AppLogger.api_info("Could not determine attackers field type")
          end

        _ ->
          AppLogger.api_info("No killmails found")
      end

    # Get character stats directly from DB for better performance
    character_stats =
      Enum.map(characters, fn character ->
        # Extract character_id safely
        character_id = extract_character_id(character)
        character_name = extract_character_name(character)

        # Skip if no valid ID
        if is_nil(character_id) do
          nil
        else
          # Debug: Try to find if this character exists in any killmail
          character_id_str = to_string(character_id)

          # Check for existence first
          _character_exists_in_killmail =
            case SQL.query(
                   Repo,
                   "SELECT EXISTS (
                     SELECT 1 FROM killmails
                     WHERE esi_data @> '{\"character_id\": \"#{character_id_str}\"}'
                     OR EXISTS (
                       SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
                       WHERE att @> '{\"character_id\": \"#{character_id_str}\"}'
                     )
                   )",
                   []
                 ) do
              {:ok, %{rows: [[exists]]}} -> exists
              _ -> false
            end

          if character_id == 640_170_087 do
            # For debugging, get a specific sample killmail for this character
            case SQL.query(
                   Repo,
                   "SELECT id, esi_data FROM killmails
                    WHERE EXISTS (
                      SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
                      WHERE att->>'character_id' = $1
                    ) LIMIT 1",
                   [character_id_str]
                 ) do
              {:ok, %{rows: [[id, esi_data]]}} ->
                AppLogger.api_info("Found sample killmail with character",
                  id: id,
                  character_id: character_id,
                  esi_data_sample: inspect(String.slice("#{esi_data}", 0, 200))
                )

              _ ->
                AppLogger.api_info("No killmails found with character",
                  character_id: character_id
                )
            end
          end

          # Try different approaches to find characters in JSON
          kill_count_approaches = [
            # Approach 1: Standard JSON path with comparison
            "SELECT COUNT(*) FROM killmails
             WHERE esi_data->>'character_id' = $1
             OR EXISTS (
               SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
               WHERE att->>'character_id' = $1
             )",

            # Approach 2: Using contains operator
            "SELECT COUNT(*) FROM killmails
             WHERE esi_data @> jsonb_build_object('character_id', $1)
             OR EXISTS (
               SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
               WHERE att @> jsonb_build_object('character_id', $1)
             )",

            # Approach 3: Use LIKE for text search as fallback
            "SELECT COUNT(*) FROM killmails
             WHERE esi_data::text LIKE '%\"character_id\":\"' || $1 || '\"%'"
          ]

          # Try each approach in order until we get a non-zero result
          kill_count =
            Enum.reduce_while(kill_count_approaches, 0, fn query, _acc ->
              case SQL.query(Repo, query, [character_id_str]) do
                {:ok, %{rows: [[count]]}} when count > 0 ->
                  # Stop if we get a non-zero count
                  {:halt, count}

                {:ok, %{rows: [[count]]}} ->
                  # Continue to next approach
                  {:cont, count}

                _ ->
                  # Continue to next approach on error
                  {:cont, 0}
              end
            end)

          # Use the same approach for last_updated
          last_updated =
            case SQL.query(
                   Repo,
                   "SELECT MAX(updated_at) FROM killmails
                    WHERE esi_data->>'character_id' = $1
                    OR EXISTS (
                      SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
                      WHERE att->>'character_id' = $1
                    )",
                   [character_id_str]
                 ) do
              {:ok, %{rows: [[timestamp]]}} -> timestamp
              _ -> nil
            end

          # Add a full data dump for debugging
          _esi_data_sample =
            if character_id == 640_170_087 do
              case SQL.query(
                     Repo,
                     "SELECT esi_data::text FROM killmails LIMIT 1",
                     []
                   ) do
                {:ok, %{rows: [[data]]}} -> data
                _ -> nil
              end
            else
              nil
            end

          %{
            character_id: character_id,
            character_name: character_name,
            kill_count: kill_count,
            last_updated: last_updated
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Log the results for debugging
    AppLogger.api_info("Character stats results", %{
      character_count: length(character_stats),
      total_kills: total_kills,
      first_few: Enum.take(character_stats, 3)
    })

    # Return the statistics
    send_success_response(conn, %{
      tracked_characters: length(character_stats),
      total_kills: total_kills,
      character_stats: character_stats,
      last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  # Helper function to extract character_id safely from different data structures
  defp extract_character_id(data) when is_map(data) do
    cond do
      # Try struct or map with atom keys
      is_map_key(data, :character_id) -> parse_int(data.character_id)
      # Try map with string keys
      is_map_key(data, "character_id") -> parse_int(data["character_id"])
      # No matching key found
      true -> nil
    end
  end

  defp extract_character_id(_), do: nil

  # Helper function to extract character name safely from different data structures
  defp extract_character_name(data) when is_map(data) do
    cond do
      # Try struct or map with atom keys (preferred name field)
      is_map_key(data, :name) -> data.name
      # Try map with string keys (preferred name field)
      is_map_key(data, "name") -> data["name"]
      # Try struct or map with atom keys (alternate name field)
      is_map_key(data, :character_name) -> data.character_name
      # Try map with string keys (alternate name field)
      is_map_key(data, "character_name") -> data["character_name"]
      # No matching key found
      true -> "Unknown Character"
    end
  end

  defp extract_character_name(_), do: "Unknown Character"

  # Get kills for all tracked characters
  get "/" do
    AppLogger.api_info("Received request to fetch kills for all tracked characters")
    all = Map.get(conn.params, "all", "false") == "true"

    if all do
      # Start the kill fetching process asynchronously
      Task.start(fn ->
        case KillsService.fetch_and_persist_all_tracked_character_kills() do
          {:ok, summary} ->
            AppLogger.api_info("Successfully fetched kills for all characters", summary: summary)

          {:error, reason} ->
            AppLogger.api_error("Failed to fetch kills for all characters",
              error: inspect(reason)
            )
        end
      end)

      # Respond immediately with a success status
      send_success_response(conn, %{
        success: true,
        message: "Kill fetching process started",
        details: %{
          status: "processing"
        }
      })
    else
      send_error_response(
        conn,
        400,
        "Missing required parameter: all=true - This parameter is needed to confirm fetching kills for all tracked characters."
      )
    end
  end

  # Helper function to parse an integer safely
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  # Debug endpoint to dump character data
  get "/dump-character-data" do
    alias Ecto.Adapters.SQL
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    alias WandererNotifier.Data.Repo

    # Get tracked characters directly from cache
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Get first 10 killmails
    sample_killmails =
      case SQL.query(Repo, "SELECT id, killmail_id, esi_data::text FROM killmails LIMIT 10") do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    # Format the result
    formatted_killmails =
      Enum.map(sample_killmails, fn [id, killmail_id, esi_data] ->
        %{
          id: id,
          killmail_id: killmail_id,
          esi_data_preview: String.slice(esi_data, 0, 200) <> "..."
        }
      end)

    # Get information about the structure of esi_data
    esi_data_structure =
      case SQL.query(
             Repo,
             "SELECT jsonb_typeof(esi_data) as type, jsonb_typeof(esi_data->'attackers') as attackers_type FROM killmails LIMIT 1"
           ) do
        {:ok, %{rows: [[type, attackers_type]]}} -> %{type: type, attackers_type: attackers_type}
        _ -> %{type: "unknown", attackers_type: "unknown"}
      end

    # Total number of killmails in the database
    total_killmails =
      case SQL.query(Repo, "SELECT COUNT(*) FROM killmails") do
        {:ok, %{rows: [[count]]}} -> count
        _ -> 0
      end

    # Send the debug data
    send_success_response(conn, %{
      tracked_character_count: length(characters),
      first_few_characters: Enum.take(characters, 3),
      sample_killmails: formatted_killmails,
      esi_data_structure: esi_data_structure,
      total_killmails: total_killmails
    })
  end

  # Debug endpoint to get kill count for a specific character
  get "/kill-count/:character_id" do
    alias Ecto.Adapters.SQL
    alias WandererNotifier.Data.Repo

    character_id_str = character_id

    # Try all approaches for finding kills
    kill_count_approaches = [
      # Approach 1: Standard JSON path with comparison
      "SELECT COUNT(*) FROM killmails
       WHERE esi_data->>'character_id' = $1
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
         WHERE att->>'character_id' = $1
       )",

      # Approach 2: Using contains operator
      "SELECT COUNT(*) FROM killmails
       WHERE esi_data @> jsonb_build_object('character_id', $1)
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(esi_data->'attackers') att
         WHERE att @> jsonb_build_object('character_id', $1)
       )",

      # Approach 3: Use LIKE for text search as fallback
      "SELECT COUNT(*) FROM killmails
       WHERE esi_data::text LIKE '%\"character_id\":\"' || $1 || '\"%'"
    ]

    # Run all approaches and collect results
    all_results =
      Enum.map(kill_count_approaches, fn query ->
        case SQL.query(Repo, query, [character_id_str]) do
          {:ok, %{rows: [[count]]}} -> count
          _ -> 0
        end
      end)

    # Find a real kill to analyze
    sample_killmail =
      case SQL.query(
             Repo,
             "SELECT id, esi_data::text FROM killmails
              WHERE esi_data::text LIKE '%\"character_id\":\"' || $1 || '\"%' LIMIT 1",
             [character_id_str]
           ) do
        {:ok, %{rows: [[id, esi_data]]}} ->
          %{id: id, esi_data_preview: String.slice(esi_data, 0, 500)}

        _ ->
          nil
      end

    # Send back all the results for comparison
    send_success_response(conn, %{
      character_id: character_id_str,
      approach_results: all_results,
      best_count: Enum.max(all_results),
      sample_killmail: sample_killmail
    })
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end
end
