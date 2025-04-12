defmodule WandererNotifier.Killmail.Processing.NotificationBehaviour do
  @moduledoc """
  Behaviour definition for killmail notification implementations.
  """

  alias WandererNotifier.Killmail.Core.Data

  @doc """
  Sends notifications for a killmail.
  """
  @callback notify(Data.t()) :: :ok | {:error, any()}
end
