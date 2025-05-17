defmodule WandererNotifier.Notifications.MockDeduplication do
  @moduledoc """
  Mock implementation of the deduplication service for testing.
  """
  @behaviour WandererNotifier.Notifications.Deduplication

  @impl true
  def check(type, id) do
    Mox.defmock(WandererNotifier.Notifications.MockDeduplication,
      for: WandererNotifier.Notifications.Deduplication
    )

    WandererNotifier.Notifications.MockDeduplication.check(type, id)
  end
end

defmodule WandererNotifier.Test.Support.Mocks do
  @moduledoc """
  Defines all mocks used in tests.
  """

  # Define the mock for Deduplication
  Mox.defmock(WandererNotifier.Notifications.MockDeduplication,
    for: WandererNotifier.Notifications.Deduplication
  )
end
