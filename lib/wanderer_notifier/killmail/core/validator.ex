defmodule WandererNotifier.Killmail.Core.Validator do
  @moduledoc """
  Validation functions for killmail data.

  This module provides functions to validate killmail data before processing.
  It ensures that killmails have all required fields and data integrity checks
  are passed before further processing.

  The validator is designed to validate Data structs directly, checking
  for the presence and validity of required fields without modifying the data.
  """

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Validates that a killmail has complete data for processing.

  Checks for the presence and validity of required fields.

  ## Parameters
  - `killmail`: A Data struct to validate

  ## Returns
  - `:ok` if all required data is present
  - `{:error, errors}` with a list of validation error tuples
  """
  @spec validate(Data.t()) :: :ok | {:error, list({atom(), String.t()})}
  def validate(%Data{} = killmail) do
    errors = []

    # Validate core identification fields
    errors = validate_identification(killmail, errors)

    # Validate system information
    errors = validate_system_information(killmail, errors)

    # Validate kill time
    errors = validate_kill_time(killmail, errors)

    # Validate victim data
    errors = validate_victim_data(killmail, errors)

    # Check if we have any errors
    if Enum.empty?(errors) do
      :ok
    else
      # Return all validation errors at once
      {:error, errors}
    end
  end

  # For non-Data values, return immediate error
  def validate(other) do
    {:error, [{:invalid_type, "Expected Data struct, got: #{inspect(other)}"}]}
  end

  @doc """
  Checks if a killmail has the minimum required data to be processed.

  Unlike the full validate/1 function, this only checks for the absolute minimum
  required fields to process the killmail.

  ## Parameters
  - `killmail`: A Data struct to validate

  ## Returns
  - `true` if the killmail has the minimum required data
  - `false` otherwise
  """
  @spec has_minimum_required_data?(Data.t()) :: boolean()
  def has_minimum_required_data?(%Data{} = killmail) do
    # Check for the absolute minimum required fields
    killmail.killmail_id != nil &&
      killmail.solar_system_id != nil
  end

  def has_minimum_required_data?(_), do: false

  # Validation helper functions

  # Validate core identification fields
  defp validate_identification(killmail, errors) do
    errors =
      if is_nil(killmail.killmail_id) do
        [{:killmail_id, "Missing killmail ID"} | errors]
      else
        errors
      end

    errors =
      if is_nil(killmail.zkb_hash) do
        [{:zkb_hash, "Missing zKillboard hash"} | errors]
      else
        errors
      end

    errors
  end

  # Validate system information
  defp validate_system_information(killmail, errors) do
    errors =
      if is_nil(killmail.solar_system_id) do
        [{:solar_system_id, "Missing solar system ID"} | errors]
      else
        errors
      end

    errors =
      if is_nil(killmail.solar_system_name) || killmail.solar_system_name == "" do
        [{:solar_system_name, "Missing solar system name"} | errors]
      else
        errors
      end

    errors
  end

  # Validate kill time
  defp validate_kill_time(killmail, errors) do
    if is_nil(killmail.kill_time) || !is_struct(killmail.kill_time, DateTime) do
      [{:kill_time, "Missing or invalid kill time"} | errors]
    else
      errors
    end
  end

  # Validate victim data (basic check - ship and character)
  defp validate_victim_data(killmail, errors) do
    # First check if victim ID exists
    errors =
      if is_nil(killmail.victim_id) do
        [{:victim_id, "Missing victim character ID"} | errors]
      else
        errors
      end

    # Then check for victim name
    errors =
      if is_nil(killmail.victim_name) || killmail.victim_name == "" do
        [{:victim_name, "Missing victim character name"} | errors]
      else
        errors
      end

    # Check for ship ID
    errors =
      if is_nil(killmail.victim_ship_id) do
        [{:victim_ship_id, "Missing victim ship ID"} | errors]
      else
        errors
      end

    # Check for ship name
    errors =
      if is_nil(killmail.victim_ship_name) || killmail.victim_ship_name == "" do
        [{:victim_ship_name, "Missing victim ship name"} | errors]
      else
        errors
      end

    errors
  end

  @doc """
  Logs validation errors with helpful context.

  ## Parameters
  - `killmail`: The killmail that failed validation
  - `errors`: The list of validation errors
  """
  @spec log_validation_errors(Data.t(), list({atom(), String.t()})) :: :ok
  def log_validation_errors(%Data{} = killmail, errors) do
    # Format errors for logging
    formatted_errors = format_validation_errors(errors)

    # Extract basic killmail info for context
    kill_id = killmail.killmail_id || "unknown"
    system_id = killmail.solar_system_id
    system_name = killmail.solar_system_name || "unknown"
    victim_name = killmail.victim_name || "unknown"
    victim_ship = killmail.victim_ship_name || "unknown"

    # Log at error level
    AppLogger.kill_error("Validation failed for killmail ##{kill_id}", %{
      kill_id: kill_id,
      system_id: system_id,
      system_name: system_name,
      victim_name: victim_name,
      victim_ship: victim_ship,
      errors: formatted_errors
    })

    :ok
  end

  # Format validation errors for logging
  defp format_validation_errors(errors) do
    errors
    |> Enum.map(fn {field, message} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
