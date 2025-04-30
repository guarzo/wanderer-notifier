defmodule WandererNotifier.Notifier.Discord.Notifier do
  @moduledoc """
  Discord notifier implementation.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config.Config

  @default_embed_color 0x00FF00

  @doc """
  Sends a notification to Discord.
  """
  def notify(notification) do
    config = get_discord_config()

    with {:ok, _response} <- HttpClient.post_json(config.webhook_url, notification, [], []) do
      AppLogger.notification_info("Discord notification sent", %{
        type: notification.type,
        feature: notification.feature
      })

      :ok
    else
      {:error, reason} ->
        AppLogger.notification_error("Discord notification failed", %{
          type: notification.type,
          feature: notification.feature,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends a simple text message to Discord.
  """
  def send_message(message, _feature \\ nil) do
    config = get_discord_config()

    payload = %{
      content: message
    }

    case HttpClient.post_json(config.webhook_url, payload, [], []) do
      {:ok, _response} ->
        AppLogger.notification_info("Discord message sent", %{
          message_length: String.length(message)
        })

        :ok

      {:error, reason} ->
        AppLogger.notification_error("Discord message failed", %{
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends an embed message to Discord.
  """
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color, _feature \\ nil) do
    config = get_discord_config()

    embed = %{
      title: title,
      description: description,
      url: url,
      color: color
    }

    payload = %{
      embeds: [embed]
    }

    case HttpClient.post_json(config.webhook_url, payload, [], []) do
      {:ok, _response} ->
        AppLogger.notification_info("Discord embed sent", %{
          title: title,
          description_length: String.length(description)
        })

        :ok

      {:error, reason} ->
        AppLogger.notification_error("Discord embed failed", %{
          title: title,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends a file to Discord.
  """
  def send_file(filename, file_data, title \\ nil, description \\ nil, _feature \\ nil) do
    config = get_discord_config()

    payload = %{
      file: %{
        name: filename,
        content: file_data
      },
      title: title,
      description: description
    }

    case HttpClient.post_json(config.webhook_url, payload, [], []) do
      {:ok, _response} ->
        AppLogger.notification_info("Discord file sent", %{
          filename: filename,
          file_size: byte_size(file_data)
        })

        :ok

      {:error, reason} ->
        AppLogger.notification_error("Discord file failed", %{
          filename: filename,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends an image embed to Discord.
  """
  def send_image_embed(
        title,
        description,
        image_url,
        color \\ @default_embed_color,
        _feature \\ nil
      ) do
    config = get_discord_config()

    embed = %{
      title: title,
      description: description,
      color: color,
      image: %{
        url: image_url
      }
    }

    payload = %{
      embeds: [embed]
    }

    case HttpClient.post_json(config.webhook_url, payload, [], []) do
      {:ok, _response} ->
        AppLogger.notification_info("Discord image embed sent", %{
          title: title,
          image_url: image_url
        })

        :ok

      {:error, reason} ->
        AppLogger.notification_error("Discord image embed failed", %{
          title: title,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private helper functions

  defp get_discord_config do
    %{
      webhook_url: Config.discord_webhook_url()
    }
  end
end
