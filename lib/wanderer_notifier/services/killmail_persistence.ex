defmodule WandererNotifier.Services.KillmailPersistence do
  @moduledoc """
  Service for persisting killmail data.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Resources.KillmailService instead.
  """

  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillmailService

  @spec maybe_persist_killmail(map()) :: {:ok, :persisted | :not_persisted} | {:error, String.t()}
  def maybe_persist_killmail(kill) do
    AppLogger.persistence_debug(
      "WandererNotifier.Services.KillmailPersistence.maybe_persist_killmail is deprecated, please use WandererNotifier.Resources.KillmailService.maybe_persist_killmail/1 instead"
    )

    KillmailService.maybe_persist_killmail(kill)
  end
end
