defmodule WandererNotifier.Domains.Notifications.DiscordNotifierBehaviour do
  @moduledoc """
  Behaviour for Discord notification functionality.
  """

  @callback send_kill_notification(killmail :: map(), type :: String.t(), options :: map()) ::
              :ok | {:error, term()}

  @callback send_test_notification() :: :ok | {:error, term()}

  @callback send_discord_embed(embed :: map()) :: :ok | {:error, term()}
end
