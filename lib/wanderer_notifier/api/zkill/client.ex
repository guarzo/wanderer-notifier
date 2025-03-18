defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the zKillboard API.
  Handles making HTTP requests to the zKillboard API endpoints.
  """

  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  # ^ Adjust or move this to config so that zKill sees you as a real user.

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

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, %{status_code: 200, body: body}} = response ->
        # zKill sometimes returns just "true" or "false" as bare JSON
        case Jason.decode(body) do
          {:ok, true} ->
            Logger.warning("[ZKill] Warning: got `true` from zKill for killmail #{kill_id}")
            {:error, :zkb_returned_true}

          _ ->
            HttpClient.handle_response(response)
        end

      error ->
        error
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

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, _} = response ->
        case HttpClient.handle_response(response) do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)
            {:ok, result}

          {:ok, _} ->
            Logger.warning("[ZKill] Unexpected response format for recent kills")
            {:error, :unexpected_response_format}

          error ->
            error
        end

      error ->
        error
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

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, _} = response ->
        case HttpClient.handle_response(response) do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)
            Logger.info("[ZKill] Successfully parsed #{length(result)} kills for system #{system_id}")
            {:ok, result}

          {:ok, []} ->
            Logger.info("[ZKill] No kills found for system #{system_id}")
            {:ok, []}

          {:ok, other} ->
            Logger.warning("[ZKill] Unexpected response format from zKill for system #{system_id} kills")
            Logger.warning("[ZKill] Response keys: #{inspect(other |> Map.keys())}")
            {:error, :unexpected_response_format}

          error ->
            error
        end

      error ->
        error
    end
  end
end
