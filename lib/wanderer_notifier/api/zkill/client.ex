defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  require Logger

  @doc """
  Gets a single killmail by its ID.
  """
  def get_single_killmail(kill_id) do
    client_module().get_single_killmail(kill_id)
  end

  @doc """
  Gets recent kills with an optional limit.
  """
  def get_recent_kills(limit \\ 10) do
    client_module().get_recent_kills(limit)
  end

  @doc """
  Gets kills for a specific system with an optional limit.
  """
  def get_system_kills(system_id, limit \\ 5) do
    client_module().get_system_kills(system_id, limit)
  end

  @doc """
  Gets kills for a specific character with optional limit and page.
  """
  def get_character_kills(character_id, limit \\ 25, page \\ 1) do
    client_module().get_character_kills(character_id, limit, page)
  end

  defp client_module do
    Application.get_env(:wanderer_notifier, :zkill_client, __MODULE__.HTTP)
  end
end

defmodule WandererNotifier.Api.ZKill.Client.HTTP do
  @moduledoc """
  HTTP implementation of the ZKill client.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Update user agent to a more proper and identifiable value for ZKill
  @user_agent "WandererNotifier/1.0 (github.com/your-username/wanderer-notifier)"

  # Rate limiting settings
  # Slightly over 1 second to respect ZKill's rate limit
  @rate_limit_ms 1100

  # Maximum retries for transient errors
  @max_retries 3
  @retry_backoff_ms 2000

  @base_url "https://zkillboard.com/api"

  def get_single_killmail(kill_id) do
    Logger.info("ZKill single_killmail HTTP request for kill_id: #{kill_id}")
    url = "#{@base_url}/killID/#{kill_id}/"
    label = "ZKill.killmail-#{kill_id}"

    headers = [{"User-Agent", @user_agent}]

    AppLogger.api_debug("[ZKill] Fetching killmail #{kill_id}")

    case HttpClient.get(url, headers, label: label) do
      {:ok, %{status_code: 200, body: body}} = response ->
        # zKill sometimes returns just "true" or "false" as bare JSON
        case Jason.decode(body) do
          {:ok, true} ->
            AppLogger.api_warn("[ZKill] Warning: got `true` from zKill for killmail #{kill_id}")
            {:error, {:domain_error, :zkill, {:unexpected_format, :boolean_true}}}

          _ ->
            ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.killmail")
        end

      response ->
        ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.killmail")
    end
  end

  def get_recent_kills(limit) do
    Logger.info("ZKill recent_kills HTTP request with limit: #{limit}")
    url = "#{@base_url}/kills/"
    label = "ZKill.recent_kills"

    headers = [{"User-Agent", @user_agent}]

    AppLogger.api_debug("[ZKill] Fetching recent kills (limit: #{limit})")

    case HttpClient.get(url, headers, label: label) do
      {:ok, _} = response ->
        case ErrorHandler.handle_http_response(response,
               domain: :zkill,
               tag: "ZKill.recent_kills"
             ) do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)
            {:ok, result}

          {:ok, _} ->
            AppLogger.api_warn("[ZKill] Unexpected response format for recent kills")
            {:error, {:domain_error, :zkill, {:unexpected_format, :not_a_list}}}

          error ->
            error
        end

      error ->
        ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.recent_kills")
    end
  end

  def get_system_kills(system_id, limit) do
    Logger.debug("🌐 ZKill request: system_id=#{system_id}, limit=#{limit}")
    # According to zKillboard API docs, the correct format is:
    # https://zkillboard.com/api/systemID/ID/
    url = "#{@base_url}/systemID/#{system_id}/"
    label = "ZKill.system_kills-#{system_id}"

    headers = [{"User-Agent", @user_agent}]

    AppLogger.api_debug("🌐 Requesting system kills",
      system_id: system_id,
      limit: limit
    )

    case HttpClient.get(url, headers, label: label) do
      {:ok, _} = response ->
        case ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.system") do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)
            {:ok, result}

          {:ok, []} ->
            AppLogger.api_debug("🌐 No kills found for system #{system_id}")
            {:ok, []}

          {:ok, %{"error" => error_msg}} ->
            AppLogger.api_warn("⚠️ ZKill API error for system #{system_id}: #{error_msg}")
            {:error, {:domain_error, :zkill, {:api_error, error_msg}}}

          {:ok, other} ->
            AppLogger.api_warn("⚠️ Unexpected ZKill response format for system #{system_id}")
            AppLogger.api_debug("Response keys: #{inspect(other |> Map.keys())}")
            {:error, {:domain_error, :zkill, {:unexpected_format, :not_a_list}}}

          error ->
            error
        end

      error ->
        ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.system")
    end
  end

  def get_character_kills(character_id, limit, page) do
    Logger.info(
      "ZKill character_kills HTTP request for character_id: #{character_id}, limit: #{limit}, page: #{page}"
    )

    # Validate character_id is a valid integer
    character_id_str = to_string(character_id)

    case validate_character_id(character_id, character_id_str) do
      {:ok, validated_id} ->
        # Add rate limiting delay
        :timer.sleep(@rate_limit_ms)

        # According to zKillboard API docs, the correct format is:
        # https://zkillboard.com/api/characterID/ID/
        url = "#{@base_url}/characterID/#{validated_id}/page/#{page}/"
        label = "ZKill.character_kills-#{validated_id}-page-#{page}"

        headers = [
          {"User-Agent", @user_agent},
          {"Accept", "application/json"}
        ]

        Logger.info(
          "[ZKill] Requesting character kills for #{validated_id} (limit: #{limit}, page: #{page})"
        )

        # Attempt request with retries for transient errors
        get_character_kills_with_retry(url, headers, label, validated_id, limit, 0)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Validates character ID format
  defp validate_character_id(character_id, character_id_str) do
    cond do
      character_id == nil or character_id_str == "" ->
        AppLogger.api_error("[ZKill] Invalid character ID: #{inspect(character_id)}")
        {:error, {:domain_error, :zkill, {:invalid_parameter, :character_id_missing}}}

      !is_integer(character_id) && !Regex.match?(~r/^\d+$/, character_id_str) ->
        AppLogger.api_error(
          "[ZKill] Character ID is not a valid integer: #{inspect(character_id)}"
        )

        {:error, {:domain_error, :zkill, {:invalid_parameter, :character_id_format}}}

      true ->
        # Convert to integer if it's a string of digits
        validated_id =
          if is_binary(character_id_str),
            do: String.to_integer(character_id_str),
            else: character_id

        {:ok, validated_id}
    end
  end

  # Private helper function to handle retries for transient errors
  defp get_character_kills_with_retry(url, headers, label, character_id, limit, retry_count) do
    case make_http_request(url, headers, label) do
      {:ok, result} ->
        {:ok, Enum.take(result, limit)}

      {:error, error} ->
        handle_retry_logic(error, url, headers, label, character_id, limit, retry_count)
    end
  end

  # Makes the HTTP request and processes the response
  defp make_http_request(url, headers, label) do
    case HttpClient.get(url, headers, label: label) do
      {:ok, _} = response ->
        process_http_response(response)

      {:error, error} ->
        {:error, ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.character")}
    end
  end

  # Processes the HTTP response
  defp process_http_response(response) do
    case ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.character") do
      {:ok, parsed} when is_list(parsed) ->
        {:ok, parsed}

      {:ok, []} ->
        {:ok, []}

      {:ok, other} ->
        process_unexpected_response(other)

      {:error, error} ->
        {:error, ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.character")}
    end
  end

  # Processes unexpected response formats
  defp process_unexpected_response(response) do
    AppLogger.api_warn("[ZKill] Unexpected response format from zKill")
    AppLogger.api_warn("[ZKill] Response data: #{inspect(response)}")

    if Map.has_key?(response, "error") do
      error_msg = Map.get(response, "error")
      AppLogger.api_error("[ZKill] API returned error: #{error_msg}")
      {:error, {:domain_error, :zkill, {:api_error, error_msg}}}
    else
      AppLogger.api_warn("[ZKill] Response keys: #{inspect(Map.keys(response))}")
      {:error, {:domain_error, :zkill, {:unexpected_format, :not_a_list}}}
    end
  end

  # Handles retry logic for failed requests
  defp handle_retry_logic(error, url, headers, label, character_id, limit, retry_count) do
    if ErrorHandler.retryable?(error) && retry_count < @max_retries do
      AppLogger.api_warn("[ZKill] Transient error, retrying (#{retry_count + 1}/#{@max_retries})")
      :timer.sleep(@retry_backoff_ms)

      get_character_kills_with_retry(
        url,
        headers,
        label,
        character_id,
        limit,
        retry_count + 1
      )
    else
      {:error, error}
    end
  end
end
