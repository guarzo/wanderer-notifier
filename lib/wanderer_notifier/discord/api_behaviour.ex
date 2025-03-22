defmodule WandererNotifier.Discord.ApiBehaviour do
  @moduledoc """
  Behaviour specification for the Discord API.
  """

  @type channel_id :: String.t() | integer()
  @type message :: String.t()
  @type embed :: map()
  @type response :: {:ok, map()} | {:error, any()}

  @callback create_message(channel_id, message) :: response
  @callback create_message(channel_id, message, opts :: keyword()) :: response
  @callback create_message!(channel_id, message) :: response
  @callback create_message!(channel_id, message, opts :: keyword()) :: response
end
