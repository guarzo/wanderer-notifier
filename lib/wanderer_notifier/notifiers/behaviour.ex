defmodule WandererNotifier.Notifiers.Behaviour do
  @moduledoc """
  Behaviour for notification services.
  Defines the common interface that all notifiers must implement.
  """

  @doc """
  Sends a simple text message.
  """
  @callback send_message(message :: String.t(), feature :: atom() | nil) :: :ok | {:error, any()}

  @doc """
  Sends a message with an embed.
  """
  @callback send_embed(
              title :: String.t(),
              description :: String.t(),
              url :: String.t() | nil,
              color :: integer(),
              feature :: atom() | nil
            ) :: :ok | {:error, any()}

  @doc """
  Sends a file with an optional title and description.
  """
  @callback send_file(
              filename :: String.t(),
              file_data :: binary(),
              title :: String.t() | nil,
              description :: String.t() | nil,
              feature :: atom() | nil
            ) :: :ok | {:error, any()}

  @doc """
  Sends a notification about a new tracked character.
  """
  @callback send_new_tracked_character_notification(character :: map()) :: :ok | {:error, any()}

  @doc """
  Sends a notification about a new system found.
  """
  @callback send_new_system_notification(system :: map()) :: :ok | {:error, any()}

  @doc """
  Sends a notification about a killmail.
  """
  @callback send_kill_notification(kill_data :: map()) :: :ok | {:error, any()}

  @doc """
  Sends a rich embed message for an enriched killmail.
  """
  @callback send_enriched_kill_embed(enriched_kill :: map(), kill_id :: integer()) ::
              :ok | {:error, any()}

  @doc """
  Sends an embed with an image.
  """
  @callback send_image_embed(
              title :: String.t(),
              description :: String.t(),
              image_url :: String.t(),
              color :: integer(),
              feature :: atom() | nil
            ) :: :ok | {:error, any()}
end
