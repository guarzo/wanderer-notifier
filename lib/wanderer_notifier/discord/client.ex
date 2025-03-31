defmodule WandererNotifier.Discord.Client do
  @moduledoc """
  Client for interacting with the Discord API.
  Provides a simplified interface for common Discord operations.
  """
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Discord.Constants
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @doc """
  Gets the configured Discord channel ID.
  """
  def channel_id do
    config = Notifications.get_discord_config()
    config.main_channel
  end

  @doc """
  Gets the configured Discord bot token.
  """
  def bot_token do
    config = Notifications.get_discord_config()
    config.token
  end

  defp build_url do
    Constants.messages_url(channel_id())
  end

  defp build_url(override_channel_id) when not is_nil(override_channel_id) do
    Constants.messages_url(override_channel_id)
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
      AppLogger.api_info("TEST MODE: Would send embed to Discord", embed: inspect(embed))
      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)
      payload = %{"embeds" => [embed]}

      case Jason.encode(payload) do
        {:ok, json} ->
          HttpClient.request("POST", url, headers(), json)
          |> handle_discord_response("send_embed")

        {:error, reason} ->
          AppLogger.api_error("Failed to encode Discord payload", error: inspect(reason))
          {:error, :json_error}
      end
    end
  end

  @doc """
  Sends a message with components to Discord.

  ## Parameters
    - embed: A map containing the embed data
    - components: A list of component rows (buttons, select menus, etc.)
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_message_with_components(embed, components, override_channel_id \\ nil) do
    if env() == :test do
      AppLogger.api_info("TEST MODE: Would send message with components to Discord",
        embed: inspect(embed),
        components: inspect(components)
      )

      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)

      payload = %{
        "embeds" => [embed],
        "components" => components
      }

      case Jason.encode(payload) do
        {:ok, json} ->
          HttpClient.request("POST", url, headers(), json)
          |> handle_discord_response("send_message_with_components")

        {:error, reason} ->
          AppLogger.api_error("Failed to encode Discord payload", error: inspect(reason))
          {:error, :json_error}
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
      AppLogger.api_info("TEST MODE: Would send message to Discord", message: message)
      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)
      payload = %{"content" => message}

      case Jason.encode(payload) do
        {:ok, json} ->
          HttpClient.request("POST", url, headers(), json)
          |> handle_discord_response("send_message")

        {:error, reason} ->
          AppLogger.api_error("Failed to encode Discord payload", error: inspect(reason))
          {:error, :json_error}
      end
    end
  end

  @doc """
  Sends a file to Discord with an optional title and description.

  ## Parameters
    - filename: The name of the file to send
    - file_data: The binary content of the file
    - title: The title for the Discord embed (optional)
    - description: The description for the Discord embed (optional)
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_file(filename, file_data, title \\ nil, description \\ nil, override_channel_id \\ nil) do
    AppLogger.api_info("Sending file to Discord", filename: filename)

    if env() == :test do
      AppLogger.api_info("TEST MODE: Would send file to Discord",
        filename: filename,
        title: title || "No title"
      )

      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)

      # Create form data with file and JSON payload
      boundary = "----------------------------#{:rand.uniform(999_999_999)}"

      # Create enhanced JSON payload with embed if title/description provided
      json_payload =
        if title || description do
          embed = %{
            "title" => title || filename,
            "description" => description || "",
            # Discord blue
            "color" => 3_447_003,
            "footer" => %{
              "text" => "Generated by WandererNotifier"
            },
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }

          Jason.encode!(%{"embeds" => [embed]})
        else
          "{}"
        end

      # Build multipart request body
      body = [
        "--#{boundary}\r\n",
        "Content-Disposition: form-data; name=\"payload_json\"\r\n\r\n",
        json_payload,
        "\r\n--#{boundary}\r\n",
        "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
        "Content-Type: application/octet-stream\r\n\r\n",
        file_data,
        "\r\n--#{boundary}--\r\n"
      ]

      # Custom headers for multipart request
      file_headers = [
        {"Content-Type", "multipart/form-data; boundary=#{boundary}"},
        {"Authorization", "Bot #{bot_token()}"}
      ]

      HttpClient.request("POST", url, file_headers, body)
      |> handle_discord_response("send_file")
    end
  end

  # Handle Discord API responses consistently
  defp handle_discord_response(response, operation) do
    case ErrorHandler.handle_http_response(response,
           domain: :discord,
           tag: "Discord.#{operation}",
           decode_json: false
         ) do
      {:ok, _} ->
        AppLogger.api_info("Successfully executed Discord operation", operation: operation)
        :ok

      {:error, %{status_code: 429, body: body}} ->
        # Parse retry_after from response for rate limiting
        retry_after =
          case Jason.decode(body) do
            {:ok, decoded} -> Map.get(decoded, "retry_after", 5) * 1000
            # Default retry after time
            _ -> 5000
          end

        AppLogger.api_warn("Discord rate limit hit",
          operation: operation,
          retry_after: retry_after
        )

        {:error, {:rate_limited, retry_after}}

      {:error, error} ->
        # Log the specific error details for debugging
        AppLogger.api_error("Discord operation failed",
          operation: operation,
          error: inspect(error)
        )

        # Check if it's retriable using ErrorHandler classification
        retriable = ErrorHandler.retryable?(error)

        if retriable do
          AppLogger.api_warn(
            "Discord error is retriable",
            suggestion: "Consider implementing automatic retry logic"
          )
        end

        {:error, error}
    end
  end
end
