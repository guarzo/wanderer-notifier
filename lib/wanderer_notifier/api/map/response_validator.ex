defmodule WandererNotifier.Api.Map.ResponseValidator do
  @moduledoc """
  Validates Map API responses against expected schemas.

  This module ensures that API responses match the expected structure before
  processing, to prevent errors from unexpected data formats.
  """
  require Logger
  alias WandererNotifier.Core.Logger, as: AppLogger

  @doc """
  Validates a systems response.

  ## Parameters
    - response: Raw HTTP response body (parsed JSON)

  ## Returns
    - {:ok, data} if valid
    - {:error, reason} if invalid
  """
  def validate_systems_response(response) do
    case response do
      %{"data" => data} when is_list(data) ->
        # Check that each system has the required fields
        if Enum.all?(data, &valid_system?/1) do
          {:ok, data}
        else
          invalid_systems = Enum.reject(data, &valid_system?/1)

          Logger.warning(
            "[ResponseValidator] #{length(invalid_systems)} systems have invalid format"
          )

          # Log one example of an invalid system for debugging
          log_invalid_system_example(invalid_systems)

          {:error, "Some systems have invalid data format"}
        end

      %{"systems" => systems} when is_list(systems) ->
        # Legacy format support
        Logger.warning(
          "[ResponseValidator] Legacy systems response format detected with 'systems' key"
        )

        # Check that each system has the required fields
        if Enum.all?(systems, &valid_system?/1) do
          {:ok, systems}
        else
          invalid_systems = Enum.reject(systems, &valid_system?/1)

          Logger.warning(
            "[ResponseValidator] #{length(invalid_systems)} systems have invalid format"
          )

          {:error, "Some systems have invalid data format"}
        end

      _ ->
        AppLogger.api_error(
          "[ResponseValidator] Unexpected response format: #{inspect(response)}"
        )

        {:error, "Expected 'data' or 'systems' array in response"}
    end
  end

  @doc """
  Validates a characters response.

  ## Parameters
    - response: Raw HTTP response body (parsed JSON)

  ## Returns
    - {:ok, data} if valid
    - {:error, reason} if invalid
  """
  def validate_characters_response(response) do
    case response do
      %{"data" => data} when is_list(data) ->
        # Check that each character has the required fields
        if Enum.all?(data, &valid_character?/1) do
          {:ok, data}
        else
          invalid_characters = Enum.reject(data, &valid_character?/1)

          Logger.warning(
            "[ResponseValidator] #{length(invalid_characters)} characters have invalid format"
          )

          # Log one example of an invalid character for debugging
          log_invalid_character_example(invalid_characters)

          {:error, "Some characters have invalid data format"}
        end

      %{"characters" => characters} when is_list(characters) ->
        # Legacy format support
        Logger.warning(
          "[ResponseValidator] Legacy characters response format detected with 'characters' key"
        )

        # Check that each character has the required fields
        if Enum.all?(characters, &valid_legacy_character?/1) do
          {:ok, characters}
        else
          invalid_characters = Enum.reject(characters, &valid_legacy_character?/1)

          Logger.warning(
            "[ResponseValidator] #{length(invalid_characters)} characters have invalid format"
          )

          {:error, "Some characters have invalid data format"}
        end

      _ ->
        AppLogger.api_error(
          "[ResponseValidator] Unexpected response format: #{inspect(response)}"
        )

        {:error, "Expected 'data' or 'characters' array in response"}
    end
  end

  @doc """
  Validates a character activity response.

  ## Parameters
    - response: Raw HTTP response body (parsed JSON)

  ## Returns
    - {:ok, data} if valid
    - {:error, reason} if invalid
  """
  def validate_character_activity_response(response) do
    case response do
      %{"data" => data} when is_list(data) ->
        # Check that each activity entry has the required fields
        if Enum.all?(data, &valid_activity?/1) do
          {:ok, data}
        else
          invalid_entries = Enum.reject(data, &valid_activity?/1)

          Logger.warning(
            "[ResponseValidator] #{length(invalid_entries)} activity entries have invalid format"
          )

          # Log one example of an invalid entry for debugging
          log_invalid_activity_example(invalid_entries)

          {:error, "Some activity entries have invalid data format"}
        end

      %{"activity" => activity} when is_list(activity) ->
        # Legacy format support
        Logger.warning(
          "[ResponseValidator] Legacy activity response format detected with 'activity' key"
        )

        # Check that each activity entry has the required fields
        if Enum.all?(activity, &valid_legacy_activity?/1) do
          {:ok, activity}
        else
          invalid_entries = Enum.reject(activity, &valid_legacy_activity?/1)

          Logger.warning(
            "[ResponseValidator] #{length(invalid_entries)} activity entries have invalid format"
          )

          {:error, "Some activity entries have invalid data format"}
        end

      _ ->
        Logger.error(
          "[ResponseValidator] Expected 'data' or 'activity' array in activity response"
        )

        {:error, "Expected 'data' or 'activity' array in response"}
    end
  end

  @doc """
  Validates a system static info response.

  ## Parameters
    - response: Raw HTTP response body (parsed JSON)

  ## Returns
    - {:ok, data} if valid
    - {:error, reason} if invalid
  """
  def validate_system_static_info_response(response) do
    # First ensure we have a map data structure
    response_data = normalize_response_data(response)
    validate_static_info_format(response_data)
  end

  defp normalize_response_data(response) do
    cond do
      is_binary(response) ->
        # Sometimes the response might still be a string, try to decode it
        case Jason.decode(response) do
          {:ok, decoded} -> decoded
          {:error, _} -> %{}
        end

      is_map(response) ->
        response

      true ->
        %{}
    end
  end

  defp validate_static_info_format(response_data) do
    case response_data do
      %{"data" => data} when is_map(data) ->
        validate_static_info_data(data)

      # If we just have the expected fields at the top level (sometimes API returns this format)
      %{"statics" => _} = direct_data ->
        AppLogger.api_warn("[ResponseValidator] Top-level static info format detected")
        validate_static_info_data(direct_data)

      _ ->
        Logger.error(
          "[ResponseValidator] Unexpected static info response format: #{inspect(response_data)}"
        )

        {:error, "Expected 'data' field in system static info response"}
    end
  end

  defp validate_static_info_data(data) do
    if valid_static_info?(data) do
      {:ok, data}
    else
      Logger.warning(
        "[ResponseValidator] System static info has invalid format: #{inspect(data)}"
      )

      {:error, "System static info has invalid format"}
    end
  end

  # Private helper functions for validation

  defp valid_system?(system) do
    (is_map(system) and
       is_binary(Map.get(system, "id", "")) and
       (is_integer(Map.get(system, "solar_system_id")) or
          is_binary(Map.get(system, "solar_system_id", ""))) and
       is_binary(Map.get(system, "name", ""))) || is_binary(Map.get(system, "original_name", ""))
  end

  defp valid_character?(character) do
    is_map(character) and
      is_map(Map.get(character, "character", %{})) and
      is_binary(get_in(character, ["character", "name"], "")) and
      (is_binary(get_in(character, ["character", "character_id"], "")) or
         is_integer(get_in(character, ["character", "character_id"], 0)))
  end

  # Support legacy character format
  defp valid_legacy_character?(character) do
    is_map(character) and
      is_binary(Map.get(character, "name", "")) and
      (is_binary(Map.get(character, "id", "")) or is_integer(Map.get(character, "id", 0)))
  end

  defp valid_activity?(activity) do
    is_map(activity) and
      is_map(Map.get(activity, "character", %{})) and
      is_binary(get_in(activity, ["character", "name"], "")) and
      (is_binary(get_in(activity, ["character", "character_id"], "")) or
         is_integer(get_in(activity, ["character", "character_id"], 0))) and
      is_integer(Map.get(activity, "signatures", 0)) and
      is_integer(Map.get(activity, "connections", 0)) and
      is_integer(Map.get(activity, "passages", 0))
  end

  # Support legacy activity format
  defp valid_legacy_activity?(activity) do
    is_map(activity) and
      is_binary(Map.get(activity, "character_name", "")) and
      is_integer(Map.get(activity, "signatures", 0)) and
      is_integer(Map.get(activity, "connections", 0))
  end

  defp valid_static_info?(info) do
    # Check for required minimal fields per documentation
    is_map(info) and
      is_list(Map.get(info, "statics", nil)) and
      (Map.has_key?(info, "solar_system_id") or Map.has_key?(info, "class_title"))
  end

  # Helper to safely get a nested value with a default
  defp get_in(map, keys, default) do
    case Kernel.get_in(map, keys) do
      nil -> default
      val -> val
    end
  end

  # Helper functions for logging invalid examples
  defp log_invalid_system_example([]), do: :ok

  defp log_invalid_system_example(invalid_systems) do
    Logger.debug(
      "[ResponseValidator] Example invalid system: #{inspect(List.first(invalid_systems))}"
    )
  end

  defp log_invalid_character_example([]), do: :ok

  defp log_invalid_character_example(invalid_characters) do
    Logger.debug(
      "[ResponseValidator] Example invalid character: #{inspect(List.first(invalid_characters))}"
    )
  end

  defp log_invalid_activity_example([]), do: :ok

  defp log_invalid_activity_example(invalid_entries) do
    Logger.debug(
      "[ResponseValidator] Example invalid activity entry: #{inspect(List.first(invalid_entries))}"
    )
  end
end
