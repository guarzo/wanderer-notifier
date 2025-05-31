defmodule WandererNotifier.Schedulers.CharacterUpdateScheduler do
  @moduledoc """
  Scheduler for updating character data.
  """

  use WandererNotifier.Schedulers.BaseMapScheduler

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Map.Clients.Client

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
  def log_emoji, do: "👤"

  @impl true
  def log_label, do: "Character cache"

  @impl true
  def interval_key, do: :character_update_scheduler_interval

  @impl true
  def stats_type, do: :characters
end
