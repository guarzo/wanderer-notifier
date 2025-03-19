defmodule WandererNotifier.Helpers.NotificationHelpers do
  @moduledoc """
  Helper functions for notification formatting and data extraction.
  """
  require Logger

  @doc """
  Extracts a valid EVE character ID from a character map.
  Handles various possible key structures.

  Returns the ID as a string or nil if no valid ID is found.
  """
  @spec extract_character_id(map()) :: String.t() | nil
  def extract_character_id(character) when is_map(character) do
    # Extract character ID - only accept numeric IDs
    cond do
      # Check top level character_id
      is_binary(character["character_id"]) && is_valid_numeric_id?(character["character_id"]) ->
        character["character_id"]

      # Check top level eve_id
      is_binary(character["eve_id"]) && is_valid_numeric_id?(character["eve_id"]) ->
        character["eve_id"]

      # Check nested character object
      is_map(character["character"]) && is_binary(character["character"]["eve_id"]) &&
          is_valid_numeric_id?(character["character"]["eve_id"]) ->
        character["character"]["eve_id"]

      is_map(character["character"]) && is_binary(character["character"]["character_id"]) &&
          is_valid_numeric_id?(character["character"]["character_id"]) ->
        character["character"]["character_id"]

      is_map(character["character"]) && is_binary(character["character"]["id"]) &&
          is_valid_numeric_id?(character["character"]["id"]) ->
        character["character"]["id"]

      # No valid numeric ID found
      true ->
        Logger.error(
          "No valid numeric EVE ID found for character: #{inspect(character, pretty: true, limit: 500)}"
        )

        nil
    end
  end

  @doc """
  Extracts a character name from a character map.
  Handles various possible key structures.

  Returns the name as a string or a default value if no name is found.
  """
  @spec extract_character_name(map(), String.t()) :: String.t()
  def extract_character_name(character, default \\ "Unknown Character") when is_map(character) do
    cond do
      character["character_name"] != nil ->
        character["character_name"]

      character["name"] != nil ->
        character["name"]

      is_map(character["character"]) && character["character"]["name"] != nil ->
        character["character"]["name"]

      is_map(character["character"]) && character["character"]["character_name"] != nil ->
        character["character"]["character_name"]

      true ->
        character_id = extract_character_id(character)
        if character_id, do: "Character #{character_id}", else: default
    end
  end

  @doc """
  Extracts a corporation name from a character map.
  Handles various possible key structures.

  Returns the name as a string or a default value if no name is found.
  """
  @spec extract_corporation_name(map(), String.t()) :: String.t()
  def extract_corporation_name(character, default \\ "Unknown Corporation")
      when is_map(character) do
    cond do
      character["corporation_name"] != nil ->
        character["corporation_name"]

      is_map(character["character"]) && character["character"]["corporation_name"] != nil ->
        character["character"]["corporation_name"]

      true ->
        default
    end
  end

  @doc """
  Adds a field to an embed map if the value is available.

  ## Parameters
  - embed: The embed map to update
  - name: The name of the field
  - value: The value of the field (or nil)
  - inline: Whether the field should be displayed inline

  ## Returns
  The updated embed map with the field added if value is not nil
  """
  @spec add_field_if_available(map(), String.t(), any(), boolean()) :: map()
  def add_field_if_available(embed, name, value, inline \\ true)
  def add_field_if_available(embed, _name, nil, _inline), do: embed
  def add_field_if_available(embed, _name, "", _inline), do: embed

  def add_field_if_available(embed, name, value, inline) do
    # Ensure the fields key exists
    embed = Map.put_new(embed, :fields, [])

    # Add the new field
    Map.update!(embed, :fields, fn fields ->
      fields ++ [%{name: name, value: to_string(value), inline: inline}]
    end)
  end

  @doc """
  Adds a security status field to an embed if the security status is available.

  ## Parameters
  - embed: The embed map to update
  - security_status: The security status value (or nil)

  ## Returns
  The updated embed map with the security status field added if available
  """
  @spec add_security_field(map(), float() | nil) :: map()
  def add_security_field(embed, nil), do: embed

  def add_security_field(embed, security_status) when is_number(security_status) do
    # Format the security status
    formatted_security = format_security_status(security_status)

    # Add the field
    add_field_if_available(embed, "Security", formatted_security)
  end

  @doc """
  Formats a security status value with color coding.

  ## Parameters
  - security_status: The security status value

  ## Returns
  A formatted string with the security status
  """
  @spec format_security_status(float() | String.t()) :: String.t()
  def format_security_status(security_status) when is_number(security_status) do
    # Round to 1 decimal place
    rounded = Float.round(security_status, 1)

    # Format with color based on value
    cond do
      rounded >= 0.5 -> "#{rounded} (High)"
      rounded > 0.0 -> "#{rounded} (Low)"
      true -> "#{rounded} (Null)"
    end
  end

  def format_security_status(security_status) when is_binary(security_status) do
    # Convert string to float and then format
    case Float.parse(security_status) do
      {value, _} -> format_security_status(value)
      :error -> "Unknown"
    end
  end

  @doc """
  Checks if a string is a valid numeric ID.

  ## Parameters
  - id: The string to check

  ## Returns
  true if the string is a valid numeric ID, false otherwise
  """
  @spec is_valid_numeric_id?(String.t() | any()) :: boolean()
  def is_valid_numeric_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end

  def is_valid_numeric_id?(_), do: false
end
