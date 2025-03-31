defmodule WandererNotifier.Resources.Domain do
  @moduledoc """
  Domain module for WandererNotifier resources.
  """

  use Ash.Domain

  resources do
    resource(WandererNotifier.Resources.KillmailPersistence)
  end
end
