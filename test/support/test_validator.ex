defmodule WandererNotifier.Test.TestValidator do
  @moduledoc """
  Test implementation of the Validator module.
  This is used to avoid conflicts with the mock behaviors in test_helper.exs
  """

  alias WandererNotifier.Killmail.Core.Data
  require Logger

  @doc """
  Validates a killmail Data struct to ensure it has all required fields.
  """
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
  """
  def has_minimum_required_data?(%Data{} = killmail) do
    # Check for essential fields that are absolutely required
    not is_nil(killmail.killmail_id)
  end

  def has_minimum_required_data?(_), do: false

  @doc """
  Logs validation errors with helpful context.
  """
  def log_validation_errors(%Data{} = killmail, errors) do
    # Format the errors for better logging
    formatted_errors = format_errors(errors)

    # Log the validation errors with context
    Logger.error("Validation errors for killmail ##{killmail.killmail_id || "unknown"}", %{
      errors: formatted_errors
    })

    :ok
  end

  def log_validation_errors(other, errors) do
    # Format the errors for better logging
    formatted_errors = format_errors(errors)

    # Log the validation errors without killmail context
    Logger.error("Validation errors for non-Data input", %{
      input: inspect(other),
      errors: formatted_errors
    })

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
