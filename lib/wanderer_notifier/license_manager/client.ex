defmodule WandererNotifier.LicenseManager.Client do
  @moduledoc """
  Client for interacting with the License Manager API.
  Provides functions for validating licenses.
  """
  require Logger
  alias WandererNotifier.Config

  # Define the behaviour callbacks
  @callback validate_license(String.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Validates a license key with the License Manager API.

  ## Parameters

  - `license_key`: The license key to validate (UUID format).

  ## Returns

  - `{:ok, response}`: If the license is valid.
  - `{:error, reason}`: If the license is invalid or an error occurred.
  """
  def validate_license(license_key) do
    url = "#{Config.license_manager_api_url()}/api/license/validate"
    Logger.info("License Manager API URL: #{url}")

    # Set the license key as a Bearer token in the Authorization header
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{license_key}"}
    ]

    Logger.debug("Sending HTTP request to License Manager API...")

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Logger.info("Received 200 OK response from License Manager API")

        case Jason.decode(response_body) do
          {:ok, decoded} ->
            Logger.debug("Successfully decoded JSON response")
            {:ok, decoded}

          {:error, error} ->
            Logger.error("Failed to decode JSON response: #{inspect(error)}")
            Logger.debug("Raw response: #{inspect(response_body)}")
            {:error, :invalid_response}
        end

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("License Manager API: Invalid license key (401)")
        {:error, :invalid_license}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.error("License Manager API: License not found (404)")
        {:error, :license_not_found}

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