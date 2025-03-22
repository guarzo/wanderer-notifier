defmodule WandererNotifier.Discord.Behaviour do
  @moduledoc """
  Defines the behaviour for Discord operations to enable mocking in tests.
  """

  @type webhook_payload :: map()

  @callback send_webhook(url :: String.t(), payload :: webhook_payload()) ::
              {:ok, map()} | {:error, term()}
  @callback send_embed(channel_id :: integer() | String.t(), embed :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback upload_file(
              channel_id :: integer() | String.t(),
              file_path :: String.t(),
              content :: String.t()
            ) :: {:ok, map()} | {:error, term()}
end
