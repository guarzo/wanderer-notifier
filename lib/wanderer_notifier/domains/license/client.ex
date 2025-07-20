defmodule WandererNotifier.Domains.License.Client do
  @moduledoc """
  Client for interacting with the License Manager API.
  Provides functions for validating licenses and bots.

  Migrated to use the unified HTTP client with service-specific configuration.
  """

  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Domains.License.Validation
  alias WandererNotifier.Shared.Utils.ErrorHandler
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  # Import logging functions for compatibility
  defp log_api_debug(message, metadata), do: AppLogger.api_debug(message, metadata)
  defp log_api_info(message, metadata), do: AppLogger.api_info(message, metadata)
  defp log_api_error(message, metadata), do: AppLogger.api_error(message, metadata)

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
    url = build_url("validate_bot")
    body = %{"license_key" => license_key}

    log_api_debug("Sending HTTP request for bot validation", %{endpoint: "validate_bot"})

    # Use unified HTTP client with license service configuration
    case Http.post(url, body, [],
           service: :license,
           auth: [type: :bearer, token: notifier_api_token]
         ) do
      {:ok, %{status_code: status, body: response_body}} when status in [200, 201] ->
        process_successful_validation(response_body)

      {:ok, %{status_code: status, body: body}} ->
        error = ErrorHandler.http_error_to_tuple(status)
        ErrorHandler.enrich_error(error, %{body: body})

      {:error, reason} ->
        normalized = ErrorHandler.normalize_error({:error, reason})
        ErrorHandler.log_error("License Manager API request failed", elem(normalized, 1))
        normalized
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
    url = build_url("validate_license")
    body = %{"license_key" => license_key}

    log_api_info("Making license validation request to License Manager API", %{})

    log_api_debug("Sending HTTP request for license validation", %{
      endpoint: "validate_license"
    })

    # Use unified HTTP client with enhanced error handling and retry
    ErrorHandler.with_error_handling(fn ->
      ErrorHandler.with_retry(
        fn -> make_validation_request(url, body, notifier_api_token) end,
        max_attempts: 3,
        retry_on: [:timeout, :network_error, :service_unavailable],
        base_delay: 1000
      )
    end)
  end

  # Private functions

  defp make_validation_request(url, body, notifier_api_token) do
    case Http.post(url, body, [],
           service: :license,
           auth: [type: :bearer, token: notifier_api_token]
         ) do
      {:ok, %{status_code: status, body: response_body}} when status in [200, 201] ->
        process_decoded_license_data(response_body)

      {:ok, %{status_code: status, body: body}} ->
        error = ErrorHandler.http_error_to_tuple(status)
        ErrorHandler.enrich_error(error, %{body: body})

      {:error, reason} ->
        normalized = ErrorHandler.normalize_error({:error, reason})
        ErrorHandler.log_error("License Manager API request failed", elem(normalized, 1))
        normalized
    end
  end

  defp build_url(endpoint) do
    base_url = Config.license_manager_api_url() || "https://license.example.com"
    "#{base_url}/api/#{endpoint}"
  end

  # Legacy function removed - functionality integrated into validate_bot
  # defp make_validation_request - removed

  # Legacy function removed - functionality integrated into validate_license
  # defp safely_make_license_request - removed

  # Legacy function removed - functionality integrated into validate_license
  # defp make_license_validation_request - removed

  # Legacy configuration functions removed - now handled by service configuration
  # Service configuration :license provides:
  # - timeout: 10_000
  # - retry_count: 1  
  # - rate_limit: [requests_per_second: 1, burst_capacity: 2]
  # - middlewares: [RateLimiter]
  # All configuration is centralized in WandererNotifier.Infrastructure.Http

  # Process a successful validation response
  defp process_successful_validation(decoded) when is_map(decoded) do
    Validation.process_validation_result({:ok, decoded})
  end

  # Handle case when response is not a map
  defp process_successful_validation(decoded) do
    error_msg = "Invalid response format: #{inspect(decoded)}"
    ErrorHandler.log_error("License validation failed", :invalid_data, %{response: decoded})

    error_response =
      Validation.create_error_response(
        :invalid_response,
        error_msg
      )

    {:error, error_response}
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
    log_api_error(
      "Unrecognized license validation response format",
      %{response: inspect(decoded)}
    )

    {:ok,
     Map.merge(decoded, %{
       "valid" => false,
       "message" => "Unrecognized response format"
     })}
  end

  # Log license_valid format results
  defp log_license_valid_result(true, _) do
    log_api_debug("License validation successful", %{license_valid: true})
  end

  defp log_license_valid_result(false, message) do
    error_msg = message || "License not valid"
    log_api_debug("License validation failed", %{reason: error_msg, license_valid: false})
  end

  # Log valid format results
  defp log_valid_format_result(true, true, _) do
    log_api_debug("License validation successful", %{license_valid: true, bot_assigned: true})
  end

  defp log_valid_format_result(true, false, _) do
    log_api_debug("License validation partial", %{
      license_valid: true,
      bot_assigned: false,
      reason: "License is valid but bot is not assigned"
    })
  end

  defp log_valid_format_result(false, _, message) do
    error_msg = message || "License not valid"
    log_api_debug("License validation failed", %{reason: error_msg, license_valid: false})
  end
end
