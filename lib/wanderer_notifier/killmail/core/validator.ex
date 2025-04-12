defmodule WandererNotifier.Killmail.Core.Validator do
  @moduledoc """
  Validator for killmail data.

  This module provides functions to validate killmail data, ensuring it has all
  required fields and that the data is in the correct format before processing.
  """

  # Force module recompilation to ensure functions are visible
  @compile {:inline, []}

  # Add behavior implementation
  @behaviour WandererNotifier.Killmail.Core.ValidatorBehaviour

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Validates a killmail Data struct to ensure it has all required fields.

  ## Parameters
    - killmail: The Data struct to validate

  ## Returns
    - :ok if the killmail is valid
    - {:error, errors} with a list of validation errors
  """
  @impl true
  @spec validate(Data.t()) :: :ok | {:error, list({atom(), String.t()})}
  def validate(%Data{} = killmail) do
    errors =
      []
      |> validate_killmail_id(killmail)
      |> validate_system_id(killmail)
      |> validate_kill_time(killmail)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  def validate(other) do
    {:error, [{:invalid_data_type, "Expected Data struct, got: #{inspect(other)}"}]}
  end

  @doc """
  Checks if a killmail has the minimum required data to be processed.

  ## Parameters
    - killmail: The Data struct to check

  ## Returns
    - true if the killmail has the minimum required data
    - false otherwise
  """
  @impl true
  @spec has_minimum_required_data?(Data.t()) :: boolean()
  def has_minimum_required_data?(%Data{} = killmail) do
    # Check for essential fields that are absolutely required
    not is_nil(killmail.killmail_id)
  end

  def has_minimum_required_data?(_), do: false

  @doc """
  Logs validation errors with helpful context.

  ## Parameters
    - killmail: The Data struct that failed validation
    - errors: List of validation errors

  ## Returns
    - :ok
  """
  @impl true
  @spec log_validation_errors(Data.t(), list({atom(), String.t()})) :: :ok
  def log_validation_errors(%Data{} = killmail, errors) do
    # Format the errors for better logging
    formatted_errors = format_errors(errors)

    # Log the validation errors with context
    AppLogger.kill_error(
      "Validation errors for killmail ##{killmail.killmail_id || "unknown"}: #{Enum.join(formatted_errors, ", ")}",
      %{
        errors: formatted_errors
      }
    )

    :ok
  end

  def log_validation_errors(other, errors) do
    # Format the errors for better logging
    formatted_errors = format_errors(errors)

    # Log the validation errors without killmail context
    AppLogger.kill_error(
      "Validation errors for non-Data input: #{Enum.join(formatted_errors, ", ")}",
      %{
        input: inspect(other),
        errors: formatted_errors
      }
    )

    :ok
  end

  # Private validation helper functions

  # Validates the killmail_id field
  defp validate_killmail_id(errors, %Data{killmail_id: nil}) do
    [{:missing_killmail_id, "Killmail ID is required"} | errors]
  end

  defp validate_killmail_id(errors, %Data{killmail_id: killmail_id})
       when not is_integer(killmail_id) do
    [{:invalid_killmail_id, "Killmail ID must be an integer"} | errors]
  end

  defp validate_killmail_id(errors, _), do: errors

  # Validates the solar_system_id field
  defp validate_system_id(errors, %Data{solar_system_id: nil}) do
    [{:missing_system_id, "Solar system ID is required"} | errors]
  end

  defp validate_system_id(errors, %Data{solar_system_id: system_id})
       when not is_integer(system_id) do
    [{:invalid_system_id, "Solar system ID must be an integer"} | errors]
  end

  defp validate_system_id(errors, _), do: errors

  # Validates the kill_time field
  defp validate_kill_time(errors, %Data{kill_time: nil}) do
    [{:missing_kill_time, "Kill time is required"} | errors]
  end

  defp validate_kill_time(errors, %Data{kill_time: kill_time})
       when not is_struct(kill_time, DateTime) do
    [{:invalid_kill_time, "Kill time must be a DateTime"} | errors]
  end

  defp validate_kill_time(errors, _), do: errors

  # Format errors for better logging
  defp format_errors(errors) do
    Enum.map(errors, fn {key, message} ->
      "#{key}: #{message}"
    end)
  end
end
