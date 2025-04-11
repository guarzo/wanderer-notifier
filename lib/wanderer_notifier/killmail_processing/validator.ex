defmodule WandererNotifier.KillmailProcessing.Validator do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Core.Validator instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Core.Validator.
  """

  alias WandererNotifier.Killmail.Core.{Data, Validator}
  alias WandererNotifier.KillmailProcessing.KillmailData

  @doc """
  Validates that a killmail has complete data for processing.
  @deprecated Please use WandererNotifier.Killmail.Core.Validator.validate/1 instead
  """
  @spec validate(KillmailData.t()) :: :ok | {:error, list({atom(), String.t()})}
  def validate(%KillmailData{} = killmail) do
    # Convert to new Data struct if needed - but in reality they're the same struct
    # since KillmailData now delegates to Data
    Validator.validate(killmail)
  end

  def validate(other), do: Validator.validate(other)

  @doc """
  Checks if a killmail has the minimum required data to be processed.
  @deprecated Please use WandererNotifier.Killmail.Core.Validator.has_minimum_required_data?/1 instead
  """
  @spec has_minimum_required_data?(KillmailData.t()) :: boolean()
  def has_minimum_required_data?(killmail), do: Validator.has_minimum_required_data?(killmail)

  @doc """
  Logs validation errors with helpful context.
  @deprecated Please use WandererNotifier.Killmail.Core.Validator.log_validation_errors/2 instead
  """
  @spec log_validation_errors(KillmailData.t(), list({atom(), String.t()})) :: :ok
  def log_validation_errors(killmail, errors),
    do: Validator.log_validation_errors(killmail, errors)
end
