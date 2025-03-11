defmodule WandererNotifier.Cache.Repository do
  @moduledoc """
  Cachex repository for WandererNotifier.
  """
  use GenServer
  require Logger

  @cache_name :wanderer_notifier_cache

  # ... existing code ... 