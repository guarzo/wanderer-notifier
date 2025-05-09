defmodule WandererNotifier.Notifications.Types.Notification do
  @moduledoc """
  Defines the structure for notifications in the system.
  """

  @type t :: %__MODULE__{
          type: String.t(),
          data: map()
        }

  defstruct [
    :type,
    :data
  ]
end
