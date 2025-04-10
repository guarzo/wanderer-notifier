defmodule WandererNotifier.ProcessCharacterKills do
  @moduledoc """
  Helper module that provides a simplified interface for processing character kills.
  This module is responsible for ensuring proper data conversion between different formats.
  """

  alias WandererNotifier.Api.Character.KillsService
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Process historical kills for a character.

  This function ensures proper conversion of killmail data to the KillmailData struct
  before passing it to the persistence layer.

  ## Parameters
    - character_id: The character ID to process kills for
    - options: Additional options to pass to the underlying function

  ## Returns
    - {:ok, stats} on success
    - {:error, reason} on failure
  """
  def process_historical_kills(character_id, options \\ []) do
    character_id_int = parse_character_id(character_id)

    AppLogger.kill_info("Starting historical kills processing with proper data conversion", %{
      character_id: character_id_int
    })

    # Get character name for better logs
    character_name = get_character_name(character_id_int)

    # Create default date range
    date_range = Map.get(options, :date_range, %{start: nil, end: nil})

    # Process the kills
    KillsService.process_historical_kills(
      character_id_int,
      character_name,
      date_range,
      Keyword.drop(options, [:date_range])
    )
  end

  @doc """
  Process kills for a character.
  """
  def process_character_kills(character_id, options \\ []) do
    character_id_int = parse_character_id(character_id)

    AppLogger.kill_info("Processing kills for character with proper data conversion", %{
      character_id: character_id_int,
      options: inspect(options)
    })

    KillsService.process_character_kills(character_id_int, options)
  end

  # Helper function to parse character ID to integer
  defp parse_character_id(character_id) when is_integer(character_id), do: character_id
  defp parse_character_id(character_id) when is_binary(character_id) do
    case Integer.parse(character_id) do
      {id, ""} -> id
      _ ->
        AppLogger.kill_warn("Invalid character ID format", %{character_id: character_id})
        nil
    end
  end
  defp parse_character_id(character_id) do
    AppLogger.kill_warn("Invalid character ID type", %{
      character_id: character_id,
      type: typeof(character_id)
    })
    nil
  end

  # Helper to get character name for logs
  defp get_character_name(character_id) do
    case WandererNotifier.Data.Repository.get_character_name(character_id) do
      {:ok, name} when is_binary(name) and name != "" -> name
      _ -> "Unknown"
    end
  end

  # Helper to get the type of a value
  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_atom(value), do: "atom"
  defp typeof(_), do: "unknown"
end
