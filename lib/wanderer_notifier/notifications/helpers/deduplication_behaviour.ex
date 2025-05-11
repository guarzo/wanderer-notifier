defmodule WandererNotifier.Notifications.Helpers.DeduplicationBehaviour do
  @moduledoc """
  Behaviour for deduplication helpers for notifications.
  Defines the interface for checking if notifications are duplicates.
  """

  @type dedup_type :: :system | :character | :kill

  @callback check(type :: dedup_type, id :: String.t() | integer()) ::
              {:ok, :new | :duplicate} | {:error, term()}

  @callback clear_key(type :: dedup_type, id :: String.t() | integer()) ::
              {:ok, term()} | {:error, term()}
end
