defmodule WandererNotifier.Slack.Notifier do
  @moduledoc """
  Sends notifications to Slack using a webhook URL.
  Supports simple text messages and messages with attachments.

  To use this notifier, configure your Slack webhook URL in your config:

      config :wanderer_notifier, :slack_webhook_url, "https://hooks.slack.com/services/your/webhook/url"
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient

  @type attachment :: %{
          title: String.t(),
          text: String.t(),
          color: String.t(),
          ts: integer()
        }

  # Get the webhook URL at runtime instead of compile time
  defp webhook_url do
    Application.get_env(:wanderer_notifier, :slack_webhook_url)
  end

  @doc """
  Sends a simple text message to Slack.
  """
  @spec send_message(String.t()) :: :ok | {:error, any()}
  def send_message(message) when is_binary(message) do
    payload = %{text: message}
    send_payload(payload)
  end

  @doc """
  Sends a message with an attachment to Slack.

  The attachment supports a title, text, and an optional color (defaults to green).
  """
  @spec send_attachment(String.t(), String.t(), String.t()) :: :ok | {:error, any()}
  def send_attachment(title, text, color \\ "#36a64f") do
    attachment = %{
      title: title,
      text: text,
      color: color,
      ts: DateTime.utc_now() |> DateTime.to_unix()
    }

    payload = %{attachments: [attachment]}
    send_payload(payload)
  end

  @doc """
  Sends a notification about a new tracked character to Slack.
  """
  def send_character_notification(character) when is_map(character) do
    character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
    character_name = Map.get(character, "character_name") || "Character #{character_id}"
    corp_name = Map.get(character, "corporation_name") || "Unknown Corporation"

    attachment = %{
      color: "#36a64f",
      title: "New Character Tracked",
      text: "#{character_name} from #{corp_name} has been added to tracking.",
      footer: "Character ID: #{character_id}"
    }

    payload = %{attachments: [attachment]}
    send_payload(payload)
  end

  @spec send_payload(map()) :: :ok | {:error, any()}
  defp send_payload(payload) do
    url = webhook_url()
    if is_nil(url) || url == "" do
      Logger.error(
        "Slack webhook URL not configured. Please set :slack_webhook_url in your configuration."
      )
      {:error, :webhook_not_configured}
    else
      case Jason.encode(payload) do
        {:ok, json} ->
          headers = [{"Content-Type", "application/json"}]
          case HttpClient.request("POST", url, headers, json) do
            {:ok, %{status_code: status}} when status in 200..299 ->
              :ok
            {:ok, response} ->
              Logger.error("Failed to send Slack notification: #{inspect(response)}")
              {:error, response}
            {:error, reason} ->
              Logger.error("Error sending Slack notification: #{inspect(reason)}")
              {:error, reason}
          end
        {:error, reason} ->
          Logger.error("Failed to encode Slack payload: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
