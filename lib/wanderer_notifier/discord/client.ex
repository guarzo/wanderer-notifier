defmodule WandererNotifier.Discord.Client do
  @moduledoc """
  Client for interacting with the Discord API.
  Provides a simplified interface for common Discord operations.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env, do: Application.get_env(:wanderer_notifier, :env, :prod)

  defp get_config!(key, error_msg) do
    environment = env()

    case Application.get_env(:wanderer_notifier, key) do
      nil when environment != :test -> raise error_msg
      "" when environment != :test -> raise error_msg
      value -> value
    end
  end

  defp channel_id do
    get_config!(
      :discord_channel_id,
      "Discord channel ID not configured. Please set :discord_channel_id in your configuration."
    )
  end

  defp bot_token do
    get_config!(
      :discord_bot_token,
      "Discord bot token not configured. Please set :discord_bot_token in your configuration."
    )
  end

  defp build_url do
    "https://discord.com/api/channels/#{channel_id()}/messages"
  end

  defp build_url(override_channel_id) when not is_nil(override_channel_id) do
    "https://discord.com/api/channels/#{override_channel_id}/messages"
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{bot_token()}"}
    ]
  end

  # -- PUBLIC API --

  @doc """
  Sends an embed message to Discord.

  ## Parameters
    - embed: A map containing the embed data
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_embed(embed, override_channel_id \\ nil) do
    if env() == :test do
      Logger.info("TEST MODE: Would send embed to Discord: #{inspect(embed)}")
      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)
      payload = %{"embeds" => [embed]}

      case Jason.encode(payload) do
        {:ok, json} ->
          case HttpClient.request("POST", url, headers(), json) do
            {:ok, %{status_code: status}} when status in 200..299 ->
              Logger.info("Successfully sent Discord embed, status: #{status}")
              :ok

            {:ok, %{status_code: status, body: body}} ->
              Logger.error(
                "Failed to send Discord embed: status=#{status}, body=#{inspect(body)}"
              )

              {:error, "Discord API error: #{status}"}

            {:error, reason} ->
              Logger.error("Error sending Discord embed: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to encode Discord payload: #{inspect(reason)}")
          {:error, "JSON encoding error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Sends a simple text message to Discord.

  ## Parameters
    - message: The text message to send
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_message(message, override_channel_id \\ nil) do
    if env() == :test do
      Logger.info("TEST MODE: Would send message to Discord: #{message}")
      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)
      payload = %{"content" => message}

      case Jason.encode(payload) do
        {:ok, json} ->
          case HttpClient.request("POST", url, headers(), json) do
            {:ok, %{status_code: status}} when status in 200..299 ->
              Logger.info("Successfully sent Discord message, status: #{status}")
              :ok

            {:ok, %{status_code: status, body: body}} ->
              Logger.error(
                "Failed to send Discord message: status=#{status}, body=#{inspect(body)}"
              )

              {:error, "Discord API error: #{status}"}

            {:error, reason} ->
              Logger.error("Error sending Discord message: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to encode Discord payload: #{inspect(reason)}")
          {:error, "JSON encoding error: #{inspect(reason)}"}
      end
    end
  end
end
