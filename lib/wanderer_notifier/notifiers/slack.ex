defmodule WandererNotifier.Notifiers.Slack do
  @moduledoc """
  Slack notification service.
  Handles sending notifications to Slack using webhooks.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Helpers.NotificationHelpers

  @behaviour WandererNotifier.Notifiers.Behaviour

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
  @impl WandererNotifier.Notifiers.Behaviour
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
    # Extract character ID using the helper
    character_id = NotificationHelpers.extract_character_id(character)

    # If we don't have a valid EVE ID, log an error and return
    if is_nil(character_id) do
      Logger.error(
        "No valid EVE character ID found for character: #{inspect(character, pretty: true, limit: 500)}"
      )

      Logger.error("This is a critical error - character tracking requires numeric EVE IDs")
      {:error, :invalid_character_id}
    else
      # Extract character name using the helper
      character_name = NotificationHelpers.extract_character_name(character)

      # Extract corporation name using the helper
      corporation_name = NotificationHelpers.extract_corporation_name(character)

      attachment = %{
        color: "#36a64f",
        title: "New Character Tracked",
        text: "#{character_name} from #{corporation_name} has been added to tracking.",
        footer: "Character ID: #{character_id}"
      }

      payload = %{attachments: [attachment]}
      send_payload(payload)
    end
  end

  @doc """
  Sends a message with an embed.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_embed(title, description, _url \\ nil, _color \\ 0x00FF00) do
    attachment = %{
      title: title,
      text: description,
      color: "#36a64f",
      ts: DateTime.utc_now() |> DateTime.to_unix()
    }

    payload = %{attachments: [attachment]}
    send_payload(payload)
  end

  @doc """
  Sends a notification about a new tracked character.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_tracked_character_notification(character) when is_map(character) do
    send_character_notification(character)
  end

  @doc """
  Sends a notification about a new system found.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_system_notification(system) when is_map(system) do
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id)

    system_name =
      Map.get(system, "system_name") || Map.get(system, :system_name) || "Unknown System"

    attachment = %{
      color: "#36a64f",
      title: "New System Tracked",
      text: "#{system_name} has been added to tracking.",
      footer: "System ID: #{system_id}"
    }

    payload = %{attachments: [attachment]}
    send_payload(payload)
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    # Extract victim information
    victim_name = get_in(enriched_kill, ["victim", "character_name"]) || "Unknown"
    victim_ship = get_in(enriched_kill, ["victim", "ship_type_name"]) || "Unknown Ship"
    system_name = get_in(enriched_kill, ["solar_system_name"]) || "Unknown System"

    # Extract kill value
    kill_value = get_in(enriched_kill, ["zkb", "totalValue"]) || 0
    formatted_value = :erlang.float_to_binary(kill_value, decimals: 2)

    # Create the base attachment
    attachment = %{
      color: "#FF0000",
      title: "Kill Notification",
      title_link: "https://zkillboard.com/kill/#{kill_id}/",
      text:
        "#{victim_name} lost a #{victim_ship} in #{system_name}\nValue: #{formatted_value} ISK",
      footer: "Kill ID: #{kill_id}"
    }

    # Add security status if available
    security_status = get_in(enriched_kill, ["solar_system", "security_status"])

    attachment =
      if security_status do
        formatted_security = NotificationHelpers.format_security_status(security_status)

        Map.update(attachment, :text, "", fn text ->
          "#{text}\nSecurity: #{formatted_security}"
        end)
      else
        attachment
      end

    payload = %{attachments: [attachment]}
    send_payload(payload)
  end

  @doc """
  Sends a file with an optional title and description.
  Not fully implemented for Slack as we don't have a proper Slack API client.
  Falls back to sending as a text message with a link.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_file(filename, _file_data, title \\ nil, description \\ nil) do
    # Since we only have webhook access and not full Slack API access,
    # we can't directly upload files. Instead, we'll send a message
    # saying a file would be uploaded.
    message_parts =
      [
        if title do
          "*#{title}*"
        else
          nil
        end,
        if description do
          description
        else
          nil
        end,
        "File: #{filename} (Slack webhook can't directly upload files)"
      ]
      |> Enum.filter(&(&1 != nil))
      |> Enum.join("\n")

    # Send as a normal message
    send_message(message_parts)
  end

  @doc """
  Sends an embed with an image to Slack.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_image_embed(title, description, image_url, _color \\ nil) do
    blocks = [
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "*#{title}*\n#{description}"
        }
      },
      %{
        "type" => "image",
        "image_url" => image_url,
        "alt_text" => title
      }
    ]

    payload = %{
      "blocks" => blocks
    }

    case send_payload(payload) do
      :ok -> :ok
      error -> error
    end
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
