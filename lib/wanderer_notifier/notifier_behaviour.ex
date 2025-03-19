defmodule WandererNotifier.NotifierBehaviour do
  @moduledoc """
  Proxy module for WandererNotifier.Notifiers.Behaviour.
  Defines the common interface that all notifiers must implement.

  This module re-exports the callbacks defined in WandererNotifier.Notifiers.Behaviour
  to maintain backward compatibility during the migration to namespaced modules.
  """

  @doc """
  Sends a simple text message.
  """
  @callback send_message(message :: String.t()) :: :ok | {:error, any()}

  @doc """
  Sends a message with an embed.
  """
  @callback send_embed(
              title :: String.t(),
              description :: String.t(),
              url :: String.t() | nil,
              color :: integer()
            ) :: :ok | {:error, any()}

  @doc """
  Sends a file with an optional title and description.
  """
  @callback send_file(
              filename :: String.t(),
              file_data :: binary(),
              title :: String.t() | nil,
              description :: String.t() | nil
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
              color :: integer()
            ) :: :ok | {:error, any()}
end
