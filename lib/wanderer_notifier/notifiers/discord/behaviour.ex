defmodule WandererNotifier.Notifiers.Discord.Behaviour do
  @moduledoc """
  Behaviour for Discord notification implementations.
  """

  @doc """
  Sends a notification to Discord.
  """
  @callback notify(notification :: map()) :: :ok | {:error, term()}

  @doc """
  Sends a simple text message to Discord.
  """
  @callback send_message(message :: String.t(), feature :: atom() | nil) :: :ok | {:error, term()}

  @doc """
  Sends an embed message to Discord.
  """
  @callback send_embed(
              title :: String.t(),
              description :: String.t(),
              url :: String.t() | nil,
              color :: integer() | nil,
              feature :: atom() | nil
            ) :: :ok | {:error, term()}

  @doc """
  Sends a file to Discord.
  """
  @callback send_file(
              filename :: String.t(),
              file_data :: binary(),
              title :: String.t() | nil,
              description :: String.t() | nil,
              feature :: atom() | nil
            ) :: :ok | {:error, term()}

  @doc """
  Sends an image embed to Discord.
  """
  @callback send_image_embed(
              title :: String.t(),
              description :: String.t(),
              image_url :: String.t(),
              color :: integer() | nil,
              feature :: atom() | nil
            ) :: :ok | {:error, term()}
end
