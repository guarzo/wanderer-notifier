defmodule WandererNotifier.Slack.Notifier do
  @moduledoc """
  Sends notifications to Slack using an incoming webhook.
  Supports simple text messages and messages with attachments.

  To use this notifier, configure your Slack webhook URL in your config:

      config :wanderer_notifier, :slack_webhook_url, "https://hooks.slack.com/services/your/webhook/url"
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient

  @slack_webhook_url Application.compile_env(:wanderer_notifier, :slack_webhook_url, nil)

  @type attachment :: %{
          title: String.t(),
          text: String.t(),
          color: String.t(),
          ts: integer()
        }

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

  @spec send_payload(map()) :: :ok | {:error, any()}
  defp send_payload(payload) do
    if is_nil(@slack_webhook_url) || @slack_webhook_url == "" do
      Logger.error(
        "Slack webhook URL not configured. Please set :slack_webhook_url in your configuration."
      )

      {:error, :no_webhook_url}
    else
      headers = [{"Content-Type", "application/json"}]
      body = Jason.encode!(payload)

      case HttpClient.request("POST", @slack_webhook_url, headers, body) do
        {:ok, %{status_code: code}} when code in 200..299 ->
          :ok

        {:ok, %{status_code: code, body: response_body}} ->
          Logger.error("Slack API request failed with status #{code}: #{response_body}")
          {:error, response_body}

        {:error, err} ->
          Logger.error("Slack API request error: #{inspect(err)}")
          {:error, err}
      end
    end
  end
end
