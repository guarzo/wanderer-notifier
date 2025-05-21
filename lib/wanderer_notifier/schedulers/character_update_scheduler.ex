defmodule WandererNotifier.Schedulers.CharacterUpdateScheduler do
  @moduledoc """
  Scheduler for updating character data.
  """

  use WandererNotifier.Schedulers.BaseMapScheduler

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Map.Clients.Client
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def feature_flag, do: :character_tracking_enabled

  @impl true
  def update_data(cached_characters) do
    Client.update_tracked_characters(cached_characters)
  end

  @impl true
  def cache_key, do: CacheKeys.character_list()

  @impl true
  def primed_key, do: :character_list_primed

  @impl true
  def log_update(new_characters, old_characters) do
    AppLogger.api_info("Character cache updated",
      current: length(new_characters),
      new: length(new_characters) - length(old_characters)
    )
  end
end
