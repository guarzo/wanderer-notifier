defmodule WandererNotifier.Debug.CharacterTools do
  @moduledoc """
  Debugging tools for analyzing and displaying character data.
  """

  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Required fields for killmail persistence
  @required_killmail_fields [
    :killmail_id,
    :kill_time,
    :solar_system_id,
    :solar_system_name,
    :total_value,
    :character_role,
    :related_character_id,
    :related_character_name,
    :ship_type_id,
    :ship_type_name
  ]

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

  @doc """
  Validates the most recent killmail record for completeness.

  This function checks the most recent killmail from the database to ensure
  all required fields are present and properly enriched.

  ## Examples

      iex> WandererNotifier.Debug.CharacterTools.validate_recent_killmail()
      # => Displays validation results for the most recent killmail
  """
  def validate_recent_killmail do
    IO.puts("\n==== VALIDATING RECENT KILLMAIL STRUCTURE ====\n")

    # Get the most recent killmail from the database
    case get_most_recent_killmail() do
      nil ->
        IO.puts("🚫 No killmail records found in database.\n")
        :no_records

      killmail ->
        IO.puts("Validating killmail #{killmail.killmail_id} from #{killmail.kill_time}:\n")

        # First check the character data
        validate_character_info(killmail)

        # Then check for required fields
        missing_fields = validate_required_fields(killmail)

        # Check for data quality in existing fields
        quality_issues = validate_field_quality(killmail)

        # Check for data consistency
        consistency_issues = validate_data_consistency(killmail)

        # Print summary
        total_issues =
          length(missing_fields) + length(quality_issues) + length(consistency_issues)

        if total_issues > 0 do
          IO.puts("\n⚠️  Found #{total_issues} issues with killmail structure")
        else
          IO.puts("\n✅ Killmail structure is complete and well-formed")
        end

        {:ok, total_issues}
    end
  end

  # Helper to get the most recent killmail
  defp get_most_recent_killmail do
    require Ash.Query
    alias WandererNotifier.Resources.Api
    alias WandererNotifier.Resources.Killmail

    case Killmail
         |> Ash.Query.sort(kill_time: :desc)
         |> Ash.Query.limit(1)
         |> Api.read() do
      {:ok, [killmail]} -> killmail
      _ -> nil
    end
  end

  # Validate character information
  defp validate_character_info(killmail) do
    character_id = killmail.related_character_id
    character_name = killmail.related_character_name
    character_role = killmail.character_role

    IO.puts("Character Information:")
    IO.puts("  ID: #{character_id}")
    IO.puts("  Name: #{character_name}")
    IO.puts("  Role: #{character_role}")

    # Check if character is tracked
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    is_tracked =
      Enum.any?(characters, fn char ->
        tracked_id = Map.get(char, "character_id") || Map.get(char, :character_id)
        tracked_id && to_string(tracked_id) == to_string(character_id)
      end)

    if is_tracked do
      IO.puts("  ✅ Character is properly tracked")
    else
      IO.puts("  ⚠️  Character is NOT in the tracked characters list")
    end

    # Check for placeholder names
    invalid_names = ["Unknown Character", "Unknown", "Unknown pilot", "Unknown Pilot"]

    cond do
      character_name in invalid_names ->
        IO.puts("  ⚠️  Character has invalid name: #{character_name}")

      is_binary(character_name) && String.starts_with?(character_name, "Unknown") ->
        IO.puts("  ⚠️  Character has suspicious name: #{character_name}")

      is_nil(character_name) || character_name == "" ->
        IO.puts("  ⚠️  Character has missing name")

      true ->
        IO.puts("  ✅ Character name is valid")
    end
  end

  # Validate required fields
  defp validate_required_fields(killmail) do
    IO.puts("\nChecking Required Fields:")

    missing_fields =
      Enum.filter(@required_killmail_fields, fn field ->
        value = Map.get(killmail, field)
        is_nil(value) || value == "" || value == 0
      end)

    if Enum.empty?(missing_fields) do
      IO.puts("  ✅ All required fields are present")
      []
    else
      Enum.each(missing_fields, fn field ->
        IO.puts("  ⚠️  Missing or empty field: #{field}")
      end)

      missing_fields
    end
  end

  # Validate quality of existing fields
  defp validate_field_quality(killmail) do
    IO.puts("\nChecking Field Quality:")

    issues = []

    # Check solar_system_name
    issues =
      if killmail.solar_system_name == "Unknown System" || is_nil(killmail.solar_system_name) do
        IO.puts("  ⚠️  solar_system_name is not properly enriched: #{killmail.solar_system_name}")
        [:solar_system_name | issues]
      else
        issues
      end

    # Check ship_type_name
    issues =
      if killmail.ship_type_name == "Unknown Ship" || is_nil(killmail.ship_type_name) do
        IO.puts("  ⚠️  ship_type_name is not properly enriched: #{killmail.ship_type_name}")
        [:ship_type_name | issues]
      else
        issues
      end

    # Check if zkb_data exists
    issues =
      if is_nil(killmail.zkb_data) || killmail.zkb_data == %{} do
        IO.puts("  ⚠️  zkb_data is missing or empty")
        [:zkb_data | issues]
      else
        issues
      end

    # Check if victim_data exists when role is attacker
    issues =
      if killmail.character_role == "attacker" &&
           (is_nil(killmail.victim_data) || killmail.victim_data == %{}) do
        IO.puts("  ⚠️  victim_data is missing or empty for attacker role")
        [:victim_data | issues]
      else
        issues
      end

    # Check if attacker_data exists when role is victim
    issues =
      if killmail.character_role == "victim" &&
           !is_nil(killmail.attacker_data) && killmail.attacker_data != %{} do
        IO.puts("  ⚠️  attacker_data should be nil for victim role")
        [:attacker_data | issues]
      else
        issues
      end

    if Enum.empty?(issues) do
      IO.puts("  ✅ All fields have good quality data")
    end

    issues
  end

  # Validate data consistency
  defp validate_data_consistency(killmail) do
    IO.puts("\nChecking Data Consistency:")

    issues = []

    # Check if kill_time is reasonable (not future date)
    issues =
      if DateTime.compare(killmail.kill_time, DateTime.utc_now()) == :gt do
        IO.puts("  ⚠️  kill_time is in the future: #{killmail.kill_time}")
        [:future_kill_time | issues]
      else
        issues
      end

    # Check if killmail_id matches any related data
    victim_killmail_id =
      if is_map(killmail.victim_data), do: Map.get(killmail.victim_data, "killmail_id"), else: nil

    issues =
      if !is_nil(victim_killmail_id) &&
           to_string(victim_killmail_id) != to_string(killmail.killmail_id) do
        IO.puts(
          "  ⚠️  killmail_id mismatch: #{killmail.killmail_id} vs #{victim_killmail_id} in victim_data"
        )

        [:killmail_id_mismatch | issues]
      else
        issues
      end

    # Check if total_value is reasonable
    issues =
      cond do
        is_nil(killmail.total_value) ->
          IO.puts("  ⚠️  total_value is nil")
          [:nil_total_value | issues]

        # Use Decimal comparison for proper numeric checking
        Decimal.compare(killmail.total_value, Decimal.new(0)) == :eq ->
          IO.puts("  ⚠️  total_value is zero")
          [:zero_total_value | issues]

        Decimal.compare(killmail.total_value, Decimal.new(1_000_000_000_000)) == :gt ->
          IO.puts("  ⚠️  total_value is unreasonably high: #{killmail.total_value}")
          [:extreme_total_value | issues]

        true ->
          issues
      end

    if Enum.empty?(issues) do
      IO.puts("  ✅ Data is internally consistent")
    end

    issues
  end
end
