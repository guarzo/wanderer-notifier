defmodule WandererNotifier.Services.KillmailPersistence do
  @moduledoc """
  Service for persisting killmail data.
  """

  alias WandererNotifier.Resources.KillmailPersistence

  @spec maybe_persist_killmail(map()) :: {:ok, :persisted | :not_persisted} | {:error, String.t()}
  def maybe_persist_killmail(kill) do
    KillmailPersistence.maybe_persist_killmail(kill)
  end
end
