defmodule WandererNotifier.Discord.Client do
  @moduledoc """
  Client for interacting with the Discord API.
  Provides a simplified interface for common Discord operations.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.Http.ErrorHandler

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
          HttpClient.request("POST", url, headers(), json)
          |> handle_discord_response("send_embed")

        {:error, reason} ->
          Logger.error("Failed to encode Discord payload: #{inspect(reason)}")
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
      Logger.info("TEST MODE: Would send message to Discord: #{message}")
      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)
      payload = %{"content" => message}

      case Jason.encode(payload) do
        {:ok, json} ->
          HttpClient.request("POST", url, headers(), json)
          |> handle_discord_response("send_message")

        {:error, reason} ->
          Logger.error("Failed to encode Discord payload: #{inspect(reason)}")
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
    Logger.info("Sending file to Discord: #{filename}")

    if env() == :test do
      Logger.info("TEST MODE: Would send file to Discord: #{filename} - #{title || "No title"}")
      :ok
    else
      url = if is_nil(override_channel_id), do: build_url(), else: build_url(override_channel_id)

      # Create form data with file and JSON payload
      boundary = "----------------------------#{:rand.uniform(999_999_999)}"

      # Create JSON part with embed if title/description provided
      json_payload =
        if title || description do
          embed = %{
            "title" => title || filename,
            "description" => description || "",
            "color" => 3_447_003 # Discord blue
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
    case ErrorHandler.handle_http_response(response, domain: :discord, tag: "Discord.#{operation}", decode_json: false) do
      {:ok, _} -> 
        Logger.info("Successfully executed Discord operation: #{operation}")
        :ok
        
      {:error, error} ->
        # Log the specific error details for debugging
        Logger.error("Discord #{operation} failed: #{inspect(error)}")
        
        # Check if it's retriable using ErrorHandler classification
        retriable = ErrorHandler.retryable?(error)
        
        if retriable do
          Logger.warning("Discord error is retriable. Consider implementing automatic retry logic.")
        end
        
        {:error, error}
    end
  end
end