defmodule WandererNotifier.Notifiers.StructuredFormatterBehaviour do
  @moduledoc """
  Behaviour module for structured notification formatting.
  """

  @callback format_system_status_message(
              String.t(),
              String.t(),
              map(),
              String.t(),
              map(),
              map(),
              integer(),
              integer()
            ) :: map()

  @callback to_discord_format(map()) :: map()
end
