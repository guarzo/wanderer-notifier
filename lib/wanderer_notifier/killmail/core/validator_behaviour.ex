defmodule WandererNotifier.Killmail.Core.ValidatorBehaviour do
  @moduledoc """
  Behaviour definition for killmail validator implementations.
  """

  alias WandererNotifier.Killmail.Core.Data

  @doc """
  Validates a killmail Data struct to ensure it has all required fields.
  """
  @callback validate(Data.t()) :: :ok | {:error, list({atom(), String.t()})}

  @doc """
  Checks if a killmail has the minimum required data to be processed.
  """
  @callback has_minimum_required_data?(Data.t()) :: boolean()

  @doc """
  Logs validation errors with helpful context.
  """
  @callback log_validation_errors(Data.t(), list({atom(), String.t()})) :: :ok
end
