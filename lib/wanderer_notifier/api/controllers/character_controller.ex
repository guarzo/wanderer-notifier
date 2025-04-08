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

  # Get character kill stats using the normalized model
  get "/stats" do
    AppLogger.api_info("Received request for character kill statistics")

    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    alias WandererNotifier.Resources.Api
    alias WandererNotifier.Resources.Killmail
    alias WandererNotifier.Resources.KillmailCharacterInvolvement
    import Ash.Query

    # Get tracked characters from cache
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Log what we got for debugging
    AppLogger.api_info("Retrieved characters from cache",
      count: length(characters),
      sample: Enum.take(characters, 2)
    )

    # Count total killmails using Ash aggregate
    total_kills =
      case Killmail
           |> Ash.Query.new()
           |> Ash.Query.aggregate(:count, :id, :total)
           |> Api.read() do
        {:ok, [%{total: count}]} -> count
        _ -> 0
      end

    # Get character stats using the normalized model
    character_stats =
      Enum.map(characters, fn character ->
        # Extract character_id safely
        character_id = extract_character_id(character)
        character_name = extract_character_name(character)

        # Skip if no valid ID
        if is_nil(character_id) do
          nil
        else
          # Get character involvements from normalized model
          involvement_query =
            KillmailCharacterInvolvement
            |> filter(character_id == ^character_id)
            |> select([:id, :killmail_id, :character_role, :inserted_at, :updated_at])

          character_involvements =
            case Api.read(involvement_query) do
              {:ok, involvements} -> involvements
              _ -> []
            end

          # Calculate kill count from involvements
          kill_count = length(character_involvements)

          # Get last updated timestamp
          last_updated =
            if Enum.empty?(character_involvements) do
              nil
            else
              character_involvements
              |> Enum.map(&Map.get(&1, :updated_at))
              |> Enum.reject(&is_nil/1)
              |> Enum.sort(DateTime)
              |> List.last()
            end

          AppLogger.api_debug("Character involvement stats",
            character_id: character_id,
            character_name: character_name,
            involvement_count: kill_count
          )

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
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    alias WandererNotifier.Resources.Api
    alias WandererNotifier.Resources.Killmail
    alias WandererNotifier.Resources.KillmailCharacterInvolvement
    import Ash.Query

    # Get tracked characters directly from cache
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Get first 10 killmails using Ash
    sample_killmails =
      case Api.read(
             Killmail
             |> limit(10)
             |> select([:id, :killmail_id, :processed_at, :victim_name, :solar_system_name])
           ) do
        {:ok, killmails} -> killmails
        _ -> []
      end

    # Format the result
    formatted_killmails =
      Enum.map(sample_killmails, fn killmail ->
        %{
          id: killmail.id,
          killmail_id: killmail.killmail_id,
          victim_name: killmail.victim_name,
          solar_system_name: killmail.solar_system_name,
          processed_at: killmail.processed_at
        }
      end)

    # Count total killmails using Ash
    total_killmails =
      case Api.read(Killmail |> aggregate(:count, :id, :total)) do
        {:ok, [%{total: count}]} -> count
        _ -> 0
      end

    # Count total involvements using Ash
    total_involvements =
      case Api.read(KillmailCharacterInvolvement |> aggregate(:count, :id, :total)) do
        {:ok, [%{total: count}]} -> count
        _ -> 0
      end

    # Get model statistics
    model_stats = %{
      killmail_count: total_killmails,
      involvement_count: total_involvements,
      tracked_character_count: length(characters)
    }

    # Send the debug data
    send_success_response(conn, %{
      tracked_character_count: length(characters),
      first_few_characters: Enum.take(characters, 3),
      sample_killmails: formatted_killmails,
      model_stats: model_stats
    })
  end

  # Debug endpoint to get kill count for a specific character using the normalized model
  get "/kill-count/:character_id" do
    alias WandererNotifier.Resources.Api
    alias WandererNotifier.Resources.Killmail
    alias WandererNotifier.Resources.KillmailCharacterInvolvement
    import Ash.Query

    # Parse character_id to integer
    parsed_id = parse_int(character_id)

    if is_nil(parsed_id) do
      send_error_response(conn, 400, "Invalid character ID format")
    else
      # Get all involvements for this character
      involvement_query =
        KillmailCharacterInvolvement
        |> filter(character_id == ^parsed_id)
        |> select([:id, :killmail_id, :character_role, :ship_type_name])

      involvements =
        case Api.read(involvement_query) do
          {:ok, records} -> records
          _ -> []
        end

      # Get a sample killmail for this character
      sample_involvements =
        involvements |> Enum.take(1) |> Enum.map(fn inv -> inv.killmail_id end)

      sample_killmail =
        if Enum.empty?(sample_involvements) do
          nil
        else
          sample_id = List.first(sample_involvements)

          case Api.read(Killmail |> filter(id == ^sample_id) |> load(:character_involvements)) do
            {:ok, [killmail]} ->
              %{
                id: killmail.id,
                killmail_id: killmail.killmail_id,
                kill_time: killmail.kill_time,
                solar_system_name: killmail.solar_system_name,
                victim_name: killmail.victim_name,
                victim_ship_name: killmail.victim_ship_name,
                total_value: killmail.total_value,
                involvements_count: length(killmail.character_involvements || [])
              }

            _ ->
              nil
          end
        end

      # Get role breakdown
      roles_breakdown =
        Enum.group_by(involvements, & &1.character_role)
        |> Enum.map(fn {role, invs} -> {role, length(invs)} end)
        |> Enum.into(%{})

      # Send back all the results
      send_success_response(conn, %{
        character_id: parsed_id,
        total_involvements: length(involvements),
        as_attacker: Map.get(roles_breakdown, :attacker, 0),
        as_victim: Map.get(roles_breakdown, :victim, 0),
        sample_killmail: sample_killmail
      })
    end
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end
end
