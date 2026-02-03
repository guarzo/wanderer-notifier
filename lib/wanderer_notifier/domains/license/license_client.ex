defmodule WandererNotifier.Domains.License.LicenseClient do
  @moduledoc """
  HTTP client for license management API calls.

  This module handles all HTTP communication with the license management server.
  It provides functions for validating licenses and bots, abstracting the HTTP
  details from the LicenseService.
  """

  require Logger

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Utils.ErrorHandler
  alias WandererNotifier.Domains.License.LicenseValidator

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Validates a bot by calling the license manager API.

  ## Parameters
  - `notifier_api_token`: The API token for the notifier.
  - `license_key`: The license key to validate.

  ## Returns
  - `{:ok, data}` if the bot was validated successfully.
  - `{:error, reason}` if the validation failed.
  """
  @spec validate_bot(String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, atom() | tuple()}
  def validate_bot(notifier_api_token, license_key) do
    url = build_url("validate_bot")
    body = %{"license_key" => license_key}

    log_validation_request(url, notifier_api_token, license_key)

    case Http.license_post(url, body, notifier_api_token) do
      {:ok, %{status_code: status, body: response_body}} when status in [200, 201] ->
        LicenseValidator.process_successful_validation(response_body)

      {:ok, %{status_code: status, body: body}} ->
        handle_error_response(status, body)

      {:error, reason} ->
        handle_request_error(reason)
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
  @spec validate_license(String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, atom() | tuple()}
  def validate_license(license_key, notifier_api_token) do
    url = build_url("validate_license")
    body = %{"license_key" => license_key}

    Logger.debug("Sending HTTP request for license validation",
      endpoint: "validate_license",
      category: :api
    )

    case make_validation_request(url, body, notifier_api_token) do
      {:ok, response} ->
        LicenseValidator.process_successful_validation(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # URL Building
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Builds a URL for a license API endpoint.

  ## Parameters
  - `endpoint`: The endpoint name (e.g., "validate_bot", "validate_license").

  ## Returns
  - The full URL string.
  """
  @spec build_url(String.t()) :: String.t()
  def build_url(endpoint) do
    base_url = Config.license_manager_api_url()
    "#{base_url}/#{endpoint}"
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers
  # ══════════════════════════════════════════════════════════════════════════════

  defp make_validation_request(url, body, notifier_api_token) do
    case Http.license_post(url, body, notifier_api_token) do
      {:ok, %{status_code: status, body: response_body}} when status in [200, 201] ->
        {:ok, response_body}

      {:ok, %{status_code: status, body: body}} ->
        error = ErrorHandler.http_error_to_tuple(status)
        ErrorHandler.enrich_error(error, %{body: body})

      {:error, reason} ->
        normalized = ErrorHandler.normalize_error({:error, reason})
        ErrorHandler.log_error("License Manager API request failed", elem(normalized, 1))
        normalized
    end
  end

  defp log_validation_request(url, notifier_api_token, license_key) do
    Logger.debug("License validation HTTP request",
      url: url,
      has_token: notifier_api_token != nil && notifier_api_token != "",
      has_license_key: license_key != nil && license_key != "",
      token_prefix: format_token_prefix(notifier_api_token),
      category: :api
    )
  end

  defp format_token_prefix(notifier_api_token) do
    if is_binary(notifier_api_token) && String.length(notifier_api_token) > 8 do
      String.slice(notifier_api_token, 0, 8) <> "..."
    else
      "invalid"
    end
  end

  defp handle_error_response(status, body) do
    Logger.error("License validation HTTP error response",
      status_code: status,
      body: inspect(body),
      category: :api
    )

    error = ErrorHandler.http_error_to_tuple(status)
    ErrorHandler.enrich_error(error, %{body: body})
  end

  defp handle_request_error(reason) do
    Logger.error("License validation request error",
      reason: inspect(reason),
      category: :api
    )

    normalized = ErrorHandler.normalize_error({:error, reason})
    ErrorHandler.log_error("License Manager API request failed", elem(normalized, 1))
    normalized
  end
end
