defmodule WandererNotifier.Domains.License.ClientV2 do
  @moduledoc """
  Client for interacting with the License Manager API.
  Provides functions for validating licenses and bots.

  This is the refactored version using the unified HTTP client base.
  """

  use WandererNotifier.Infrastructure.Http.ClientBase,
    base_url:
      Application.compile_env(
        :wanderer_notifier,
        :license_manager_api_url,
        "https://license.example.com"
      ),
    timeout: 15_000,
    recv_timeout: 15_000,
    service_name: "license_manager"

  alias WandererNotifier.Domains.License.Validation
  alias WandererNotifier.Shared.Utils.ErrorHandler

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
    url = "#{base_url()}/api/validate_bot"

    # Set up request parameters
    headers = build_auth_headers(notifier_api_token)
    body = Jason.encode!(%{"license_key" => license_key})

    log_api_debug("Sending HTTP request for bot validation", %{endpoint: "validate_bot"})

    # Make the API request and process the response
    make_validation_request(url, body, headers)
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
    url = "#{base_url()}/api/validate_license"
    log_api_info("Making license validation request to License Manager API", %{})

    # Prepare request parameters
    headers = build_auth_headers(notifier_api_token)
    body = Jason.encode!(%{"license_key" => license_key})

    log_api_debug("Sending HTTP request for license validation", %{
      endpoint: "validate_license"
    })

    # Make the request with error handling
    safely_make_license_request(url, body, headers)
  end

  # Private functions

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
    # Disable rate limiting for license validation during startup
    request(:post, url,
      body: body,
      headers: headers,
      opts: build_validation_request_opts()
    )
    |> handle_response(resource_type: "bot_validation", success_codes: [200, 201])
    |> case do
      {:ok, decoded} ->
        process_successful_validation(decoded)

      {:error, reason} ->
        normalized = ErrorHandler.normalize_error({:error, reason})
        ErrorHandler.log_error("License Manager API request failed", elem(normalized, 1))
        normalized
    end
  end

  # Make the license validation request with error handling
  defp safely_make_license_request(url, body, headers) do
    ErrorHandler.with_error_handling(fn ->
      make_license_validation_request(url, body, headers)
    end)
  end

  # Make the actual HTTP request for license validation
  defp make_license_validation_request(url, body, headers) do
    # Use retry logic for transient errors
    ErrorHandler.with_retry(
      fn ->
        request(:post, url,
          body: body,
          headers: headers,
          opts: build_license_request_opts()
        )
        |> handle_response(resource_type: "license_validation")
        |> case do
          {:ok, decoded} ->
            process_decoded_license_data(decoded)

          {:error, reason} ->
            normalized = ErrorHandler.normalize_error({:error, reason})
            ErrorHandler.log_error("License Manager API request failed", elem(normalized, 1))
            normalized
        end
      end,
      max_attempts: 3,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: 1000
    )
  end

  defp build_validation_request_opts do
    config = %{
      timeout: default_timeout(),
      recv_timeout: default_recv_timeout(),
      # Disable middlewares for validation to avoid rate limiting during startup
      rate_limit_options: [],
      retry_options: [
        max_attempts: 2,
        base_backoff: 1000,
        retryable_errors: [:timeout, :connect_timeout],
        retryable_status_codes: [429, 500, 502, 503, 504],
        context: "License validation request"
      ],
      telemetry_options: [
        service_name: service_name()
      ]
    }

    build_default_opts([], config)
  end

  defp build_license_request_opts do
    config = %{
      timeout: default_timeout(),
      recv_timeout: default_recv_timeout(),
      # Add custom rate limiting for license endpoints - much lower rate to avoid hitting limits
      rate_limit_options: [
        requests_per_second: 1,
        burst_capacity: 2,
        per_host: true
      ],
      retry_options: [
        max_attempts: 3,
        base_backoff: 2000,
        retryable_errors: [:timeout, :connect_timeout],
        retryable_status_codes: [429, 500, 502, 503, 504],
        context: "License request"
      ],
      telemetry_options: [
        service_name: service_name()
      ]
    }

    build_default_opts([], config)
  end

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

    {:ok, error_response}
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
    ErrorHandler.log_error(
      "Unrecognized license validation response format",
      :invalid_data,
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
