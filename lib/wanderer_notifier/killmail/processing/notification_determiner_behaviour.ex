defmodule WandererNotifier.Killmail.Processing.NotificationDeterminerBehaviour do
  @moduledoc """
  Behaviour definition for killmail notification determination implementations.
  """

  alias WandererNotifier.Killmail.Core.Data

  @doc """
  Determines if a notification should be sent for a killmail.
  """
  @callback should_notify?(Data.t()) :: {:ok, {boolean(), String.t()}} | {:error, any()}
end
