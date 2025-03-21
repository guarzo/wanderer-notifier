defmodule WandererNotifier.LicenseManager.Client do
  @moduledoc """
  Client for interacting with the License Manager API.
  Provides functions for validating licenses and bots.
  """
  require Logger
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Api.Http.Client, as: HttpClient

  # Define the behaviour callbacks
  @callback validate_bot(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Validates a bot by calling the license manager API.

  ## Parameters
  - `notifier_api_token`: The API token for the notifier.
  - `license_key`: The license key to validate.

  ## Returns
  - `{:ok, data}` if the bot was validated successfully.
  - `{:error, reason}` if the validation failed.
  """
  def validate_bot(notifier_api_token, license_key) do
    url = "#{Config.license_manager_api_url()}/api/validate_bot"

    # Log complete request information for debugging
    Logger.info("LICENSE VALIDATION DEBUG: Full request details:")
    Logger.info("  URL: #{url}")
    Logger.info("  API Token (first 8 chars): #{String.slice(notifier_api_token || "", 0, 8)}")
    Logger.info("  License Key: #{license_key}")

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{notifier_api_token}"}
    ]

    # Create the request body with the license key
    body = %{
      "license_key" => license_key
    }

    # Log the full body
    Logger.info("  Request Body: #{inspect(body)}")
    Logger.info("  Request Headers: #{inspect(headers)}")

    Logger.debug("Sending HTTP request to License Manager API for bot validation...")

    # Use our improved HTTP client
    case HttpClient.post_json(url, body, headers,
           label: "LicenseManager.validate_bot",
           debug: true,
           timeout: 5000
         ) do
      {:ok, response} = result ->
        # Log full response for debugging
        Logger.info("LICENSE VALIDATION DEBUG: Full response: #{inspect(response)}")

        case HttpClient.handle_response(result) do
          {:ok, decoded} ->
            # Additional logging for easier debugging
            Logger.debug("Bot validation response: #{inspect(decoded)}")

            # Check if the license is valid from the response
            license_valid = decoded["license_valid"] || false
            message = decoded["message"]

            if license_valid do
              Logger.info("License and bot validation successful - License is valid")
            else
              error_msg = message || "License is not valid"
              Logger.warning("License and bot validation failed - #{error_msg}")
            end

            # Ensure the response contains both formats for compatibility
            enhanced_response = Map.merge(decoded, %{"valid" => license_valid})
            {:ok, enhanced_response}

          {:error, :unauthorized} ->
            Logger.error("License Manager API: Invalid notifier API token (401)")
            {:error, :invalid_notifier_token}

          {:error, :forbidden} ->
            Logger.error(
              "License Manager API: Notifier is inactive or not associated with license (403)"
            )

            {:error, :notifier_not_authorized}

          {:error, :not_found} ->
            Logger.error("License Manager API: Notifier or license not found (404)")
            {:error, :not_found}

          error ->
            Logger.error("License Manager API error: #{inspect(error)}")
            {:error, :api_error}
        end

      {:error, :connect_timeout} ->
        Logger.error("License Manager API request timed out")
        {:error, :request_failed}

      {:error, reason} ->
        Logger.error("License Manager API request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end

  @doc """
  Validates a license key by calling the license manager API.

  ## Parameters
  - `license_key`: The license key to validate.
  - `notifier_api_token`: The API token for the notifier.

  ## Returns
  - `{:ok, data}` if the license was validated successfully.
  - `{:error, reason}` if the validation failed.
  """
  def validate_license(license_key, notifier_api_token) do
    url = "#{Config.license_manager_api_url()}/api/validate_license"
    Logger.info("License Manager API URL: #{url}")

    # Set the headers
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{notifier_api_token}"}
    ]

    # Create the request body with the license key
    body = %{
      "license_key" => license_key
    }

    Logger.debug("Sending HTTP request to License Manager API for license validation...")

    # Use a shorter timeout for the HTTP request
    try do
      case HttpClient.post_json(url, body, headers,
             label: "LicenseManager.validate_license",
             timeout: 2500,
             max_retries: 1,
             debug: true
           ) do
        {:ok, _} = response ->
          case HttpClient.handle_response(response) do
            {:ok, decoded} ->
              # Additional logging for easier debugging
              Logger.debug("License validation response: #{inspect(decoded)}")

              # Check response structure and adapt to either {"valid": true/false} or {"license_valid": true/false} format
              cond do
                # Check for license_valid field (validate_bot endpoint format)
                Map.has_key?(decoded, "license_valid") ->
                  license_valid = decoded["license_valid"]

                  if license_valid do
                    Logger.info("License validation successful - License is valid")
                  else
                    error_msg = decoded["message"] || "License not valid"
                    Logger.warning("License validation failed - #{error_msg}")
                  end

                  # Map to expected format for backward compatibility
                  {:ok, Map.merge(decoded, %{"valid" => license_valid})}

                # Check for valid field (validate_license endpoint format)
                Map.has_key?(decoded, "valid") ->
                  valid = decoded["valid"]
                  bot_assigned = decoded["bot_assigned"] || false

                  if valid do
                    if bot_assigned do
                      Logger.info(
                        "License validation successful - License is valid and bot is assigned"
                      )
                    else
                      Logger.warning(
                        "License validation partial - License is valid but bot is not assigned"
                      )
                    end
                  else
                    error_msg = decoded["message"] || "License not valid"
                    Logger.warning("License validation failed - #{error_msg}")
                  end

                  {:ok, decoded}

                # Unknown response format
                true ->
                  Logger.warning(
                    "Unrecognized license validation response format: #{inspect(decoded)}"
                  )

                  {:ok,
                   Map.merge(decoded, %{
                     "valid" => false,
                     "message" => "Unrecognized response format"
                   })}
              end

            {:error, :unauthorized} ->
              Logger.error("License Manager API: Invalid notifier API token (401)")
              {:error, "Invalid notifier API token"}

            {:error, :forbidden} ->
              Logger.error(
                "License Manager API: Notifier is inactive or not associated with license (403)"
              )

              {:error, "Notifier not authorized"}

            {:error, :not_found} ->
              Logger.error("License Manager API: License not found (404)")
              {:error, "License not found"}

            {:error, reason} ->
              Logger.error("License Manager API error: #{inspect(reason)}")
              {:error, "API error: #{inspect(reason)}"}
          end

        {:error, :timeout} ->
          Logger.error("License Manager API request timed out")
          {:error, "Request timed out"}

        {:error, reason} ->
          Logger.error("License Manager API request failed: #{inspect(reason)}")
          {:error, "Request failed: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Exception during license validation: #{inspect(e)}")
        {:error, "Exception: #{inspect(e)}"}
    end
  end
end
