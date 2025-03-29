defmodule WandererNotifier.Domain do
  @moduledoc """
  Domain module for WandererNotifier.
  """

  use Ash.Domain

  resources do
    resource(WandererNotifier.Resources.KillmailPersistence)
  end
end
