defmodule WandererNotifier.License.Client do
  @moduledoc """
  Client for interacting with the License Manager API.
  Provides functions for validating licenses and bots.
  """
  require Logger
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger

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

    # Set up request parameters
    headers = build_auth_headers(notifier_api_token)
    body = %{"license_key" => license_key}

    AppLogger.api_debug("Sending HTTP request for bot validation", endpoint: "validate_bot")

    # Make the API request and process the response
    make_validation_request(url, body, headers)
  end

  # Build authorization headers for API requests
  defp build_auth_headers(api_token) do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{api_token}"}
    ]
  end

  # Make the actual API request for validation
  defp make_validation_request(url, body, headers) do
    case HttpClient.post_json(url, body, headers,
           label: "LicenseManager.validate_bot",
           debug: true,
           timeout: 5000
         ) do
      {:ok, %{status_code: _status, body: decoded}} ->
        process_successful_validation(decoded)

      {:error, :connect_timeout} ->
        AppLogger.api_error("License Manager API request timed out")
        {:error, :request_failed}

      {:error, :rate_limited} ->
        AppLogger.api_error("License Manager API rate limit exceeded")
        {:error, :rate_limited}

      {:error, reason} ->
        AppLogger.api_error("License Manager API request failed", error: inspect(reason))
        {:error, :request_failed}
    end
  end

  # Process a successful validation response
  defp process_successful_validation(decoded) when is_map(decoded) do
    # Additional logging for easier debugging without exposing sensitive data
    license_valid = decoded["license_valid"] || false

    log_validation_result(license_valid, decoded["message"])

    # Ensure the response contains both formats for compatibility
    enhanced_response = Map.merge(decoded, %{"valid" => license_valid})
    {:ok, enhanced_response}
  end

  # Handle case when response is not a map
  defp process_successful_validation(decoded) do
    AppLogger.api_error("Invalid license validation response format", response: inspect(decoded))

    # Return a standardized error response
    {:ok,
     %{
       "license_valid" => false,
       "valid" => false,
       "message" => "Invalid response format: #{inspect(decoded)}"
     }}
  end

  # Log the validation result based on validity
  defp log_validation_result(true, _message) do
    AppLogger.api_debug("License and bot validation successful", license_valid: true)
  end

  defp log_validation_result(false, message) do
    error_msg = message || "License is not valid"

    AppLogger.api_warn("License and bot validation failed",
      reason: error_msg,
      license_valid: false
    )
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
    AppLogger.api_info("Making license validation request to License Manager API")

    # Prepare request parameters
    headers = build_auth_headers(notifier_api_token)
    body = %{"license_key" => license_key}

    AppLogger.api_debug("Sending HTTP request for license validation",
      endpoint: "validate_license"
    )

    # Make the request with error handling
    safely_make_license_request(url, body, headers)
  end

  # Make the license validation request with error handling
  defp safely_make_license_request(url, body, headers) do
    make_license_validation_request(url, body, headers)
  rescue
    e ->
      AppLogger.api_error("Exception during license validation",
        exception: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Exception: #{inspect(e)}"}
  end

  # Make the actual HTTP request for license validation
  defp make_license_validation_request(url, body, headers) do
    request_options = [
      label: "LicenseManager.validate_license",
      timeout: 2500,
      max_retries: 1,
      debug: true
    ]

    case HttpClient.post_json(url, body, headers, request_options) do
      {:ok, %{status_code: _status, body: decoded}} ->
        process_decoded_license_data(decoded)

      {:error, :timeout} ->
        AppLogger.api_error("License Manager API request timed out")
        {:error, "Request timed out"}

      {:error, :rate_limited} ->
        AppLogger.api_error("License Manager API rate limit exceeded")
        {:error, "Rate limit exceeded"}

      {:error, reason} ->
        AppLogger.api_error("License Manager API request failed", error: inspect(reason))
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  # Process decoded license data based on its format using pattern matching
  defp process_decoded_license_data(%{"license_valid" => _} = decoded) do
    process_license_valid_format(decoded)
  end

  defp process_decoded_license_data(%{"valid" => _} = decoded) do
    process_valid_format(decoded)
  end

  defp process_decoded_license_data(decoded) do
    process_unknown_format(decoded)
  end

  # Handle the license_valid format (from validate_bot endpoint)
  defp process_license_valid_format(decoded) do
    license_valid = decoded["license_valid"]
    log_license_valid_result(license_valid, decoded["message"])

    # Map to expected format for backward compatibility
    {:ok, Map.merge(decoded, %{"valid" => license_valid})}
  end

  # Handle the valid format (from validate_license endpoint)
  defp process_valid_format(decoded) do
    valid = decoded["valid"]
    bot_assigned = decoded["bot_assigned"] || false

    log_valid_format_result(valid, bot_assigned, decoded["message"])
    {:ok, decoded}
  end

  # Handle unknown response format
  defp process_unknown_format(decoded) do
    AppLogger.api_warn("Unrecognized license validation response format",
      response: inspect(decoded)
    )

    {:ok,
     Map.merge(decoded, %{
       "valid" => false,
       "message" => "Unrecognized response format"
     })}
  end

  # Log license_valid format results
  defp log_license_valid_result(true, _) do
    AppLogger.api_debug("License validation successful", license_valid: true)
  end

  defp log_license_valid_result(false, message) do
    error_msg = message || "License not valid"
    AppLogger.api_warn("License validation failed", reason: error_msg, license_valid: false)
  end

  # Log valid format results
  defp log_valid_format_result(true, true, _) do
    AppLogger.api_debug("License validation successful", license_valid: true, bot_assigned: true)
  end

  defp log_valid_format_result(true, false, _) do
    AppLogger.api_warn("License validation partial",
      license_valid: true,
      bot_assigned: false,
      reason: "License is valid but bot is not assigned"
    )
  end

  defp log_valid_format_result(false, _, message) do
    error_msg = message || "License not valid"
    AppLogger.api_warn("License validation failed", reason: error_msg, license_valid: false)
  end
end
