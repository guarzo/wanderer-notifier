defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the zKillboard API.
  Handles making HTTP requests to the zKillboard API endpoints.
  """

  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.Http.ErrorHandler

  # Update user agent to a more proper and identifiable value for ZKill
  @user_agent "WandererNotifier/1.0 (github.com/your-username/wanderer-notifier)"

  # Rate limiting settings
  # Slightly over 1 second to respect ZKill's rate limit
  @rate_limit_ms 1100

  # Maximum retries for transient errors
  @max_retries 3
  @retry_backoff_ms 2000

  @doc """
  Retrieves a single killmail from zKillboard by ID.

  ## Parameters
  - `kill_id`: The ID of the killmail to retrieve

  ## Returns
  - `{:ok, killmail}`: The killmail data
  - `{:error, reason}`: If an error occurred
  """
  def get_single_killmail(kill_id) do
    url = "https://zkillboard.com/api/killID/#{kill_id}/"
    label = "ZKill.killmail-#{kill_id}"

    headers = [{"User-Agent", @user_agent}]

    Logger.debug("[ZKill] Fetching killmail #{kill_id}")

    case HttpClient.get(url, headers, label: label) do
      {:ok, %{status_code: 200, body: body}} = response ->
        # zKill sometimes returns just "true" or "false" as bare JSON
        case Jason.decode(body) do
          {:ok, true} ->
            Logger.warning("[ZKill] Warning: got `true` from zKill for killmail #{kill_id}")
            {:error, {:domain_error, :zkill, {:unexpected_format, :boolean_true}}}

          _ ->
            ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.killmail")
        end

      response ->
        ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.killmail")
    end
  end

  @doc """
  Retrieves recent kills from zKillboard.

  ## Parameters
  - `limit`: The maximum number of kills to retrieve (default: 10)

  ## Returns
  - `{:ok, kills}`: A list of recent kills
  - `{:error, reason}`: If an error occurred
  """
  def get_recent_kills(limit \\ 10) do
    url = "https://zkillboard.com/api/kills/"
    label = "ZKill.recent_kills"

    headers = [{"User-Agent", @user_agent}]

    Logger.debug("[ZKill] Fetching recent kills (limit: #{limit})")

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
            Logger.warning("[ZKill] Unexpected response format for recent kills")
            {:error, {:domain_error, :zkill, {:unexpected_format, :not_a_list}}}

          error ->
            error
        end

      error ->
        ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.recent_kills")
    end
  end

  @doc """
  Retrieves kills for a specific system from zKillboard.

  ## Parameters
  - `system_id`: The ID of the system to get kills for
  - `limit`: The maximum number of kills to retrieve (default: 5)

  ## Returns
  - `{:ok, kills}`: A list of kills for the system
  - `{:error, reason}`: If an error occurred
  """
  def get_system_kills(system_id, limit \\ 5) do
    # According to zKillboard API docs, the correct format is:
    # https://zkillboard.com/api/systemID/ID/
    url = "https://zkillboard.com/api/systemID/#{system_id}/"
    label = "ZKill.system_kills-#{system_id}"

    headers = [{"User-Agent", @user_agent}]

    Logger.info("[ZKill] Requesting system kills for #{system_id} (limit: #{limit})")

    case HttpClient.get(url, headers, label: label) do
      {:ok, _} = response ->
        case ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.system") do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)

            Logger.info(
              "[ZKill] Successfully parsed #{length(result)} kills for system #{system_id}"
            )

            {:ok, result}

          {:ok, []} ->
            Logger.info("[ZKill] No kills found for system #{system_id}")
            {:ok, []}

          {:ok, other} ->
            Logger.warning(
              "[ZKill] Unexpected response format from zKill for system #{system_id} kills"
            )

            Logger.warning("[ZKill] Response keys: #{inspect(other |> Map.keys())}")
            {:error, {:domain_error, :zkill, {:unexpected_format, :not_a_list}}}

          error ->
            error
        end

      error ->
        ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.system")
    end
  end

  @doc """
  Gets recent kill information for a specific character from zKillboard.

  ## Parameters
  - `character_id`: The character ID to find kills for
  - `limit`: Maximum number of kills to retrieve (defaults to 25)
  - `page`: Page number for pagination (defaults to 1)

  ## Returns
  - `{:ok, kills}`: List of kills for the character
  - `{:error, reason}`: If an error occurred

  ## Example
      iex> WandererNotifier.Api.ZKill.Client.get_character_kills(12345)
      {:ok, [%{...}, %{...}]}
  """
  def get_character_kills(character_id, limit \\ 25, page \\ 1) do
    # Validate character_id is a valid integer
    character_id_str = to_string(character_id)

    if character_id == nil or character_id_str == "" do
      Logger.error("[ZKill] Invalid character ID: #{inspect(character_id)}")
      {:error, {:domain_error, :zkill, {:invalid_parameter, :character_id_missing}}}
    else
      # Ensure character_id is a valid integer to prevent API errors
      if !is_integer(character_id) && !Regex.match?(~r/^\d+$/, character_id_str) do
        Logger.error("[ZKill] Character ID is not a valid integer: #{inspect(character_id)}")
        {:error, {:domain_error, :zkill, {:invalid_parameter, :character_id_format}}}
      else
        # Convert to integer if it's a string of digits
        character_id =
          if is_binary(character_id_str),
            do: String.to_integer(character_id_str),
            else: character_id

        # Add rate limiting delay
        :timer.sleep(@rate_limit_ms)

        # According to zKillboard API docs, the correct format is:
        # https://zkillboard.com/api/characterID/ID/
        url = "https://zkillboard.com/api/characterID/#{character_id}/page/#{page}/"
        label = "ZKill.character_kills-#{character_id}-page-#{page}"

        headers = [
          {"User-Agent", @user_agent},
          {"Accept", "application/json"}
        ]

        Logger.info(
          "[ZKill] Requesting character kills for #{character_id} (limit: #{limit}, page: #{page})"
        )

        # Attempt request with retries for transient errors
        get_character_kills_with_retry(url, headers, label, character_id, limit, 0)
      end
    end
  end

  # Private helper function to handle retries for transient errors
  defp get_character_kills_with_retry(url, headers, label, character_id, limit, retry_count) do
    case HttpClient.get(url, headers, label: label) do
      {:ok, _} = response ->
        case ErrorHandler.handle_http_response(response, domain: :zkill, tag: "ZKill.character") do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)

            Logger.info(
              "[ZKill] Successfully parsed #{length(result)} kills for character #{character_id}"
            )

            {:ok, result}

          {:ok, []} ->
            Logger.info("[ZKill] No kills found for character #{character_id}")
            {:ok, []}

          {:ok, other} ->
            # Log the actual response to help debugging
            Logger.warning(
              "[ZKill] Unexpected response format from zKill for character #{character_id} kills"
            )

            Logger.warning("[ZKill] Response data: #{inspect(other)}")

            if Map.has_key?(other, "error") do
              error_msg = Map.get(other, "error")
              Logger.error("[ZKill] API returned error: #{error_msg}")
              {:error, {:domain_error, :zkill, {:api_error, error_msg}}}
            else
              Logger.warning("[ZKill] Response keys: #{inspect(Map.keys(other))}")
              {:error, {:domain_error, :zkill, {:unexpected_format, :not_a_list}}}
            end

          {:error, error} ->
            error_result =
              ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.character")

            # Check if this is a transient error that we should retry
            if ErrorHandler.retryable?(error) && retry_count < @max_retries do
              Logger.warning(
                "[ZKill] Transient error, retrying (#{retry_count + 1}/#{@max_retries})"
              )

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
              error_result
            end
        end

      {:error, error} ->
        error_result =
          ErrorHandler.handle_http_error(error, domain: :zkill, tag: "ZKill.character")

        # Check if this is a transient error that we should retry
        if ErrorHandler.retryable?(error) && retry_count < @max_retries do
          Logger.warning("[ZKill] Transient error, retrying (#{retry_count + 1}/#{@max_retries})")
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
          error_result
        end
    end
  end
end
