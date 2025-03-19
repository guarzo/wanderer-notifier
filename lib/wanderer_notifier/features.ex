defmodule WandererNotifier.Features do
  @moduledoc """
  Proxy module for WandererNotifier.Core.Features.
  Delegates all calls to the Core.Features implementation.
  """
  require Logger

  @doc """
  Delegates to WandererNotifier.Core.Features.enabled?/1
  """
  def enabled?(feature) do
    WandererNotifier.Core.Features.enabled?(feature)
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.get_limit/1
  """
  def get_limit(resource) do
    WandererNotifier.Core.Features.get_limit(resource)
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.limit_reached?/2
  """
  def limit_reached?(resource, current_count) do
    WandererNotifier.Core.Features.limit_reached?(resource, current_count)
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.get_all_limits/0
  """
  def get_all_limits do
    WandererNotifier.Core.Features.get_all_limits()
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.tracked_systems_notifications_enabled?/0
  """
  def tracked_systems_notifications_enabled? do
    WandererNotifier.Core.Features.tracked_systems_notifications_enabled?()
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.tracked_characters_notifications_enabled?/0
  """
  def tracked_characters_notifications_enabled? do
    WandererNotifier.Core.Features.tracked_characters_notifications_enabled?()
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.kill_notifications_enabled?/0
  """
  def kill_notifications_enabled? do
    WandererNotifier.Core.Features.kill_notifications_enabled?()
  end

  @doc """
  Delegates to WandererNotifier.Core.Features.track_all_systems?/0
  """
  def track_all_systems? do
    WandererNotifier.Core.Features.track_all_systems?()
  end
end
