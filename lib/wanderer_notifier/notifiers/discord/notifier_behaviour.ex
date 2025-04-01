defmodule WandererNotifier.Notifiers.Discord.NotifierBehaviour do
  @moduledoc """
  Behaviour module for Discord notifications.
  """

  @callback send_discord_embed(map()) :: :ok | {:error, any()}
end
