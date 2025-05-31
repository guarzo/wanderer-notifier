defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler for updating system data.
  """

  use WandererNotifier.Schedulers.BaseMapScheduler

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Map.Clients.Client

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
  def log_emoji, do: "🗺️ "

  @impl true
  def log_label, do: "System cache"

  @impl true
  def interval_key, do: :system_update_scheduler_interval

  @impl true
  def stats_type, do: :systems
end
