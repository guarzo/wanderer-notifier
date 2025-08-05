defmodule WandererNotifier.Domains.License.License do
  @moduledoc """
  Simple license validation without GenServer overhead.

  Provides stateless license validation functionality with direct HTTP calls
  and simple caching for performance.
  """

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Infrastructure.Cache
  require Logger

  @validation_url "https://lm.wanderer.ltd/validate_bot"
  @cache_key "license_validation_result"
  # 20 minutes cache
  @cache_ttl :timer.minutes(20)

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Validates the license and returns validation result.
  """
  def validate(opts \\ []) do
    force_refresh = Keyword.get(opts, :force_refresh, false)

    if force_refresh do
      perform_validation()
    else
      case get_cached_result() do
        {:ok, cached_result} ->
          Logger.debug("Using cached license validation result")
          {:ok, cached_result}

        {:error, :not_found} ->
          Logger.debug("No cached license result, performing validation")
          perform_validation()
      end
    end
  end

  @doc """
  Gets the current license status.
  """
  def status do
    case validate() do
      {:ok, result} ->
        result

      {:error, reason} ->
        %{
          valid: false,
          bot_assigned: false,
          error: reason,
          error_message: format_error_message(reason),
          last_validated: System.system_time(:second)
        }
    end
  end

  @doc """
  Checks if the license is currently valid.
  """
  def valid? do
    case validate() do
      {:ok, %{valid: true}} -> true
      _ -> false
    end
  end

  @doc """
  Checks if a bot is assigned to this license.
  """
  def bot_assigned? do
    case validate() do
      {:ok, %{bot_assigned: true}} -> true
      _ -> false
    end
  end

  @doc """
  Clears the cached license validation result.
  """
  def clear_cache do
    Cache.delete(@cache_key)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  defp perform_validation do
    with {:ok, config} <- get_license_config(),
         {:ok, response} <- make_validation_request(config),
         {:ok, result} <- parse_validation_response(response) do
      # Cache the successful result
      Cache.put(@cache_key, result, @cache_ttl)

      Logger.info("License validation successful",
        valid: result.valid,
        bot_assigned: result.bot_assigned
      )

      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("License validation failed", error: reason)
        error
    end
  end

  defp get_license_config do
    try do
      license_key = Config.license_key()
      api_token = Config.license_manager_api_key()

      cond do
        is_nil(license_key) or license_key == "" ->
          {:error, :missing_license_key}

        is_nil(api_token) or api_token == "" ->
          {:error, :missing_api_token}

        true ->
          {:ok,
           %{
             license_key: license_key,
             api_token: api_token,
             validation_url: Config.license_manager_api_url() || @validation_url
           }}
      end
    rescue
      e ->
        Logger.error("Error getting license configuration", error: Exception.message(e))
        {:error, :config_error}
    end
  end

  defp make_validation_request(config) do
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{config.api_token}"}
    ]

    body =
      Jason.encode!(%{
        "license_key" => config.license_key,
        "product" => "wanderer_notifier"
      })

    url = "#{config.validation_url}/validate_bot"

    case Http.request(:post, url, body, headers, service: :license) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status_code: status_code, body: error_body}} ->
        Logger.error("License validation HTTP error",
          status_code: status_code,
          response: error_body
        )

        {:error, {:http_error, status_code, error_body}}

      {:error, reason} ->
        Logger.error("License validation request failed", error: reason)
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_validation_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"valid" => valid} = response} ->
        result = %{
          valid: valid,
          bot_assigned: Map.get(response, "bot_assigned", false),
          details: Map.get(response, "details", %{}),
          last_validated: System.system_time(:second),
          error: nil,
          error_message: nil
        }

        {:ok, result}

      {:ok, response} ->
        Logger.error("Invalid license validation response format", response: response)
        {:error, :invalid_response_format}

      {:error, reason} ->
        Logger.error("Failed to parse license validation response", error: reason)
        {:error, :json_decode_error}
    end
  end

  defp get_cached_result do
    Cache.get(@cache_key)
  end

  defp format_error_message(reason) do
    case reason do
      :missing_license_key -> "License key not configured"
      :missing_api_token -> "API token not configured"
      :config_error -> "Configuration error"
      {:http_error, status_code, _body} -> "HTTP error: #{status_code}"
      {:request_failed, reason} -> "Request failed: #{inspect(reason)}"
      :invalid_response_format -> "Invalid response format from license server"
      :json_decode_error -> "Failed to decode license server response"
    end
  end
end
