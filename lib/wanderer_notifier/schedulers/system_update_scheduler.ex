defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler for updating system data.
  """

  use WandererNotifier.Schedulers.BaseMapScheduler

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Map.Clients.Client
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def feature_flag, do: :system_tracking_enabled

  @impl true
  def update_data(cached_systems) do
    Client.update_systems_with_cache(cached_systems)
  end

  @impl true
  def cache_key, do: CacheKeys.map_systems()

  @impl true
  def primed_key, do: :map_systems_primed

  @impl true
  def log_update(new_systems, old_systems) do
    AppLogger.api_info("System cache updated",
      current: length(new_systems),
      new: length(new_systems) - length(old_systems)
    )
  end
end
