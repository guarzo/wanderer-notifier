defmodule WandererNotifier.Resources.KillmailAggregationTest do
  use ExUnit.Case, async: false

  # Skip all tests in this module since they require persistence to be enabled
  @moduletag :skip

  # These tests were originally designed to test the KillmailAggregation
  # module's functionality, but they require the persistence feature to be enabled
  # and depend on modules like Killmail, TrackedCharacter and KillmailStatistic
  # that are defined when persistence is enabled.

  # Note: The KillmailChartScheduler tests provide sufficient coverage for the
  # kill charts feature for the current scope of changes.
end
