defmodule WandererNotifier.Helpers.NotificationHelpers do
  @moduledoc """
  Helper functions for notification formatting and data extraction.
  """
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  @doc """
  Extracts a character ID from a Character struct.
  No fallbacks to maps supported.

  Returns the ID as a string.
  """
  @spec extract_character_id(Character.t()) :: String.t()
  def extract_character_id(%Character{} = character) do
    character.character_id
  end

  @doc """
  Extracts a character name from a Character struct.
  No fallbacks to maps supported.

  Returns the name as a string.
  """
  @spec extract_character_name(Character.t()) :: String.t()
  def extract_character_name(%Character{} = character) do
    character.name
  end

  @doc """
  Extracts a corporation name from a Character struct.
  No fallbacks to maps supported.

  Returns the corporation ticker as a string.
  """
  @spec extract_corporation_name(Character.t()) :: String.t()
  def extract_corporation_name(%Character{} = character) do
    character.corporation_ticker
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
  Sends a test system notification using a real tracked system.
  Returns an error if no systems are being tracked.
  """
  @spec send_test_system_notification() ::
          {:ok, String.t(), String.t()} | {:error, :no_tracked_systems}
  def send_test_system_notification do
    alias WandererNotifier.Api.Map.SystemsClient

    # Use the new helper method that mimics the character approach
    case SystemsClient.get_system_for_notification() do
      {:ok, system} ->
        # Log clear details about the selected system
        AppLogger.processor_info("Selected system for test notification",
          system_id: system.solar_system_id,
          name: system.name,
          type: system.system_type
        )

        # Send the notification
        notifier = NotifierFactory.get_notifier()
        result = notifier.send_new_system_notification(system)

        # Log the result and return
        AppLogger.processor_info("System notification sent",
          result: inspect(result)
        )

        {:ok, system.solar_system_id, system.name}

      {:error, _reason} ->
        # No systems available
        AppLogger.processor_warn("No systems found for notification")
        {:error, :no_tracked_systems}
    end
  end

  @doc """
  Sends a test kill notification using a real recent kill.
  Returns an error if no kills are available.
  """
  @spec send_test_kill_notification() :: {:ok, String.t()} | {:error, :no_recent_kills}
  def send_test_kill_notification do
    case CacheRepo.get("kills:recent") do
      nil ->
        AppLogger.processor_warn("No recent kills available in cache")
        {:error, :no_recent_kills}

      [] ->
        AppLogger.processor_warn("Recent kills cache is empty")
        {:error, :no_recent_kills}

      kills when is_list(kills) ->
        # Use most recent kill
        kill = List.first(kills)
        notifier = NotifierFactory.get_notifier()
        notifier.send_enriched_kill_embed(kill, kill.killmail_id)
        {:ok, kill.killmail_id}
    end
  end

  @doc """
  Sends a test character notification using a real tracked character.
  Returns an error if no characters are being tracked.
  """
  @spec send_test_character_notification() ::
          {:ok, String.t(), String.t()} | {:error, :no_tracked_characters}
  def send_test_character_notification do
    case CacheRepo.get("map:characters") do
      nil ->
        AppLogger.processor_warn("No characters are currently being tracked")
        {:error, :no_tracked_characters}

      [] ->
        AppLogger.processor_warn("No characters are currently being tracked")
        {:error, :no_tracked_characters}

      characters when is_list(characters) ->
        # Select a random character from cache
        character = Enum.random(characters)

        # Check that we have a Character struct - no conversion needed
        if is_struct(character, Character) do
          AppLogger.processor_info("Using Character struct from cache",
            character_id: character.character_id,
            name: character.name
          )

          # Send notification using the struct directly from cache
          notifier = NotifierFactory.get_notifier()
          notifier.send_new_tracked_character_notification(character)
          {:ok, character.character_id, character.name}
        else
          # This should never happen if the cache is properly maintained
          AppLogger.processor_error("Expected Character struct in cache but got something else",
            found_type: typeof(character),
            data: inspect(character, limit: 200)
          )

          {:error, :invalid_character_in_cache}
        end
    end
  end

  # Helper function to get type of a value for logging
  defp typeof(nil), do: "nil"
  defp typeof(x) when is_binary(x), do: "binary"
  defp typeof(x) when is_boolean(x), do: "boolean"
  defp typeof(x) when is_integer(x), do: "integer"
  defp typeof(x) when is_float(x), do: "float"
  defp typeof(x) when is_list(x), do: "list"
  defp typeof(x) when is_map(x) and not is_struct(x), do: "map"
  defp typeof(x) when is_atom(x), do: "atom"
  defp typeof(x) when is_function(x), do: "function"
  defp typeof(x) when is_port(x), do: "port"
  defp typeof(x) when is_pid(x), do: "pid"
  defp typeof(x) when is_reference(x), do: "reference"
  defp typeof(x) when is_tuple(x), do: "tuple"
  defp typeof(x) when is_struct(x), do: "struct:#{inspect(x.__struct__)}"
  defp typeof(_), do: "unknown"
end
