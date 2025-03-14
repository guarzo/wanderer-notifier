defmodule WandererNotifier.LicenseManager.Client do
  @moduledoc """
  Client for interacting with the License Manager API.
  Provides functions for validating licenses and bots.
  """
  require Logger
  alias WandererNotifier.Config

  # Define the behaviour callbacks
  @callback validate_bot(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Validates a bot with a license key using the License Manager API.
  This endpoint handles both bot validation and license validation in a single call.

  ## Parameters

  - `bot_api_token`: The API token for the bot.
  - `license_key`: The license key to validate against.

  ## Returns

  - `{:ok, response}`: If the validation is successful.
  - `{:error, reason}`: If the validation fails or an error occurred.
  """
  def validate_bot(bot_api_token, license_key) do
    url = "#{Config.license_manager_api_url()}/api/validate_bot"
    Logger.info("License Manager API URL: #{url}")
    Logger.debug("Using bot_api_token: #{String.slice(bot_api_token, 0, 8)}... (first 8 chars)")
    Logger.debug("Using license_key: #{String.slice(license_key, 0, 8)}... (first 8 chars)")

    # Set the bot API token as a Bearer token in the Authorization header
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{bot_api_token}"}
    ]

    # Create the request body with the license key
    body = Jason.encode!(%{
      "license_key" => license_key
    })

    Logger.debug("Sending HTTP request to License Manager API for bot validation...")
    Logger.debug("Request headers: #{inspect(headers, pretty: true)}")
    Logger.debug("Request body: #{inspect(body, pretty: true)}")

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Logger.info("Received 200 OK response from License Manager API")

        case Jason.decode(response_body) do
          {:ok, decoded} ->
            Logger.debug("Successfully decoded JSON response")
            # Check if the license is valid from the response
            license_valid = decoded["license_valid"] || false
            if license_valid do
              Logger.info("License validation successful - License is valid")
            else
              Logger.warning("License validation failed - License is not valid")
            end
            {:ok, decoded}

          {:error, error} ->
            Logger.error("Failed to decode JSON response: #{inspect(error)}")
            Logger.debug("Raw response: #{inspect(response_body)}")
            {:error, :invalid_response}
        end

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("License Manager API: Invalid bot API token (401)")
        {:error, :invalid_bot_token}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        Logger.error("License Manager API: Bot is inactive or not associated with license (403)")
        {:error, :bot_not_authorized}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.error("License Manager API: Bot or license not found (404)")
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 400, body: body}} ->
        Logger.error("License Manager API: Bad request (400)")
        Logger.debug("Error response body: #{inspect(body)}")
        {:error, :bad_request}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("License Manager API error: #{status_code}")
        Logger.debug("Error response body: #{inspect(body)}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("License Manager API request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end
end
