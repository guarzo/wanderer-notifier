defmodule WandererNotifier.Notifiers.Discord.Behaviour do
  @moduledoc """
  Defines the behaviour for Discord notification implementations.
  """

  @doc "Sends a notification"
  @callback notify(notification :: map()) :: :ok | {:error, term()}

  @doc "Sends a message to Discord"
  @callback send_message(message :: String.t(), channel :: atom()) :: :ok | {:error, term()}

  @doc "Sends an embed to Discord"
  @callback send_embed(
              title :: String.t(),
              description :: String.t(),
              color :: integer(),
              fields :: list(),
              channel :: atom()
            ) :: :ok | {:error, term()}

  @doc "Sends a file to Discord"
  @callback send_file(
              filename :: String.t(),
              file_data :: binary(),
              title :: String.t(),
              description :: String.t(),
              channel :: atom()
            ) :: :ok | {:error, term()}

  @doc "Sends an image embed to Discord"
  @callback send_image_embed(
              title :: String.t(),
              description :: String.t(),
              image_url :: String.t(),
              color :: integer(),
              channel :: atom()
            ) :: :ok | {:error, term()}

  @doc "Sends an enriched kill embed"
  @callback send_enriched_kill_embed(killmail :: struct(), kill_id :: integer()) ::
              :ok | {:error, term()}

  @doc "Sends a new system notification"
  @callback send_new_system_notification(system :: struct()) :: :ok | {:error, term()}

  @doc "Sends a new tracked character notification"
  @callback send_new_tracked_character_notification(character :: struct()) ::
              :ok | {:error, term()}

  @doc "Sends a kill notification"
  @callback send_kill_notification(kill_data :: map()) :: :ok | {:error, term()}

  @doc "Sends a kill notification with type and options"
  @callback send_kill_notification(killmail :: map(), type :: atom(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc "Sends a Discord embed (test support)"
  @callback send_discord_embed(embed :: map()) :: {:ok, map()} | {:error, term()}

  @doc "Sends a generic notification (test support)"
  @callback send_notification(type :: atom(), data :: any()) :: {:ok, map()} | {:error, term()}
end
