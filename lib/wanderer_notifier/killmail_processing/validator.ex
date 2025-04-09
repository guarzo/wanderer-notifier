defmodule WandererNotifier.KillmailProcessing.Validator do
  @moduledoc """
  Validation functions for killmail data.

  This module provides functions to validate killmail data before processing.
  It ensures that killmails have all required fields and data integrity checks
  are passed before further processing.

  The validator works with all killmail formats (KillmailData, KillmailResource,
  or raw maps) by using the Extractor module for consistent data access.

  ## Usage

  ```elixir
  # Validate a killmail has all required fields
  case Validator.validate_complete_data(killmail) do
    :ok -> # Process the killmail
    {:error, reason} -> # Handle the validation error
  end
  ```
  """

  alias WandererNotifier.KillmailProcessing.Extractor

  @doc """
  Validates that a killmail has complete data for processing.

  Checks for the presence of:
  - Killmail ID
  - Solar system ID
  - Solar system name
  - Victim data

  ## Parameters

  - `killmail`: Any killmail format (KillmailData, KillmailResource, or map)

  ## Returns

  - `:ok` if all required data is present
  - `{:error, reason}` with a string reason if validation fails

  ## Examples

      iex> Validator.validate_complete_data(valid_killmail)
      :ok

      iex> Validator.validate_complete_data(invalid_killmail)
      {:error, "Killmail ID missing"}
  """
  @spec validate_complete_data(Extractor.killmail_source()) :: :ok | {:error, String.t()}
  def validate_complete_data(killmail) do
    debug_data = Extractor.debug_data(killmail)

    field_checks = [
      {:killmail_id, debug_data.killmail_id, "Killmail ID missing"},
      {:system_id, debug_data.system_id, "Solar system ID missing"},
      {:system_name, debug_data.system_name, "Solar system name missing"},
      {:victim, debug_data.has_victim_data, "Victim data missing"}
    ]

    # Find first failure
    case Enum.find(field_checks, fn {_field, value, _msg} ->
      is_nil(value) or value == false
    end) do
      nil -> :ok
      {_field, _value, msg} -> {:error, msg}
    end
  end
end
