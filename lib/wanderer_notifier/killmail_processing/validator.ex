defmodule WandererNotifier.KillmailProcessing.Validator do
  @moduledoc """
  DEPRECATED: This module is a compatibility layer for the Killmail Validator.
  Please use WandererNotifier.Killmail.Core.Validator instead.
  """

  alias WandererNotifier.Killmail.Core.Validator, as: NewValidator

  @doc """
  Validates a killmail Data struct to ensure it has all required fields.
  Delegates to the new validator implementation.
  """
  def validate(killmail) do
    NewValidator.validate(killmail)
  end

  @doc """
  Checks if a killmail has the minimum required data to be processed.
  Delegates to the new validator implementation.
  """
  def has_minimum_required_data?(killmail) do
    NewValidator.has_minimum_required_data?(killmail)
  end

  @doc """
  Logs validation errors with helpful context.
  Delegates to the new validator implementation.
  """
  def log_validation_errors(killmail, errors) do
    NewValidator.log_validation_errors(killmail, errors)
  end

  # For backward compatibility with code using normalize_killmail
  @doc """
  DEPRECATED: This function is deprecated and may not behave as expected.
  Please use the new validator interface instead.
  """
  def normalize_killmail(killmail) do
    # In the new model, validation doesn't modify the data
    # This is a compatibility function that returns the original data
    case validate(killmail) do
      :ok -> killmail
      {:error, _} -> killmail
    end
  end

  # For backward compatibility with code using validate_complete_data
  @doc """
  DEPRECATED: This function is deprecated, use validate/1 instead.
  """
  def validate_complete_data(killmail) do
    validate(killmail)
  end
end
