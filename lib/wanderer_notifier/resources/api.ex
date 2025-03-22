defmodule WandererNotifier.Resources.Api do
  @moduledoc """
  Ash API for WandererNotifier resources.
  Defines the interface for interacting with the application's resources.
  """

  use Ash.Api

  resources do
    resource(WandererNotifier.Resources.TrackedCharacter)
    resource(WandererNotifier.Resources.Killmail)
    resource(WandererNotifier.Resources.KillmailStatistic)
  end
end
