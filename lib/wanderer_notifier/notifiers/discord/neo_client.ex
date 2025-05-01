defmodule WandererNotifier.Notifiers.Discord.NeoClient do
  @moduledoc """
  Neo client for Discord integration.
  Handles direct communication with Discord's API.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config.Config

  @doc """
  Sends a message to Discord.
  """
  def send_message(message) do
    webhook_url = Config.discord_webhook_url()
    payload = %{content: message}

    case post_to_discord(webhook_url, payload) do
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
  Sends an embed to Discord.
  """
  def send_embed(embed) do
    webhook_url = Config.discord_webhook_url()
    payload = %{embeds: [embed]}

    case post_to_discord(webhook_url, payload) do
      {:ok, _response} ->
        AppLogger.notification_info("Discord embed sent", %{
          title: embed["title"]
        })

        :ok

      {:error, reason} ->
        AppLogger.notification_error("Discord embed failed", %{
          title: embed["title"],
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends a file to Discord.
  """
  def send_file(filename, file_data, title \\ nil, description \\ nil) do
    webhook_url = Config.discord_webhook_url()

    payload = %{
      file: %{
        name: filename,
        content: file_data
      },
      title: title,
      description: description
    }

    case post_to_discord(webhook_url, payload) do
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

  # Private helper functions

  defp post_to_discord(webhook_url, payload) do
    headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", "WandererNotifier/1.0"}
    ]

    case WandererNotifier.HttpClient.Httpoison.post_json(webhook_url, payload, headers, []) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end
end
