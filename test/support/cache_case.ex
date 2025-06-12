defmodule WandererNotifier.CacheCase do
  @moduledoc """
  This module defines the setup for tests requiring cache functionality.

  You may define functions here to be used as helpers in your tests.

  Usage:

      use WandererNotifier.CacheCase
      
  This will:
  - Import cache helpers
  - Set up a clean cache before each test
  - Provide the cache_name in the test context
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import WandererNotifier.Test.Support.CacheHelpers

      setup :setup_cache
    end
  end
end
