defmodule WandererNotifier.Debug.CharacterTools do
  @moduledoc """
  Debugging tools for analyzing and displaying character data.
  """

  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  List all tracked characters from the cache.

  This function retrieves and displays all tracked characters from the cache,
  showing their character ID, name, corporation and alliance.

  ## Examples

      iex> WandererNotifier.Debug.CharacterTools.list_tracked_characters()
      # => Displays list of all tracked characters

  """
  def list_tracked_characters do
    characters = CacheRepo.get(CacheKeys.character_list()) || []
    character_count = length(characters)

    if character_count == 0 do
      IO.puts("\n🚫 No tracked characters found in cache.\n")
      :no_characters
    else
      IO.puts("\n==== TRACKED CHARACTERS (#{character_count}) ====\n")

      # Display characters in a tabular format
      characters
      |> Enum.sort_by(fn char ->
        Map.get(char, "name") || Map.get(char, :name) || "Unknown"
      end)
      |> Enum.with_index(1)
      |> Enum.each(fn {char, index} ->
        # Extract character information, handling both map and struct formats
        character_id =
          Map.get(char, "character_id") || Map.get(char, :character_id) || "Unknown ID"

        character_name = Map.get(char, "name") || Map.get(char, :name) || "Unknown Name"

        corp_name =
          Map.get(char, "corporation_ticker") || Map.get(char, :corporation_name) ||
            "Unknown Corp"

        alliance_name = Map.get(char, "alliance_ticker") || Map.get(char, :alliance_name) || "N/A"

        alliance_display = if alliance_name == "N/A", do: "N/A", else: alliance_name

        # Print character information
        IO.puts("#{index}. #{character_name} (ID: #{character_id})")
        IO.puts("   Corporation: #{corp_name}")
        IO.puts("   Alliance: #{alliance_display}")
        IO.puts("")
      end)

      AppLogger.persistence_info("Displayed #{character_count} tracked characters")
      {:ok, character_count}
    end
  end

  @doc """
  Validate character data quality in the cache.

  This function checks for potential data quality issues with tracked characters,
  such as missing names, placeholder names, or other issues.

  ## Examples

      iex> WandererNotifier.Debug.CharacterTools.validate_character_quality()
      # => Displays validation results for tracked characters

  """
  def validate_character_quality do
    characters = CacheRepo.get(CacheKeys.character_list()) || []
    character_count = length(characters)

    if character_count == 0 do
      IO.puts("\n🚫 No tracked characters found in cache to validate.\n")
      :no_characters
    else
      IO.puts("\n==== CHARACTER DATA QUALITY CHECK (#{character_count} characters) ====\n")

      # Define problematic patterns
      invalid_names = ["Unknown Character", "Unknown", "Unknown pilot", "Unknown Pilot"]

      # Use reduce to count issues
      issues_found =
        Enum.reduce(characters, 0, fn char, acc ->
          # Extract character information
          character_id =
            Map.get(char, "character_id") || Map.get(char, :character_id) || "Unknown ID"

          character_name = Map.get(char, "name") || Map.get(char, :name) || "Unknown Name"

          # Check for issues
          cond do
            character_name in invalid_names ->
              IO.puts("⚠️  Character #{character_id} has invalid name: #{character_name}")
              acc + 1

            is_binary(character_name) && String.starts_with?(character_name, "Unknown") ->
              IO.puts("⚠️  Character #{character_id} has suspicious name: #{character_name}")
              acc + 1

            is_nil(character_name) || character_name == "" ->
              IO.puts("⚠️  Character #{character_id} has missing name")
              acc + 1

            true ->
              acc
          end
        end)

      # Summary
      if issues_found > 0 do
        IO.puts("\n⚠️  Found #{issues_found} character data quality issues")
      else
        IO.puts("\n✅ No character data quality issues found")
      end

      {:ok, issues_found}
    end
  end
end
